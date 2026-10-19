// RateHelper Orlen price relay (Cloudflare Workers free plan + KV).
//
//   GET  /prices            published prices (what the app shows)
//   POST /submissions       driver proposal → Telegram message to the admin
//   POST /telegram/webhook  admin taps ✅ Approve & Publish / ❌ Reject
//
// Nothing a driver sends is public until the admin approves it.

import { STATIONS } from './stations.js';

// Same bounds as priceRange() in lib/fuel/fuel_prices.dart.
const RANGES = { pb95: [4.0, 9.0], lpg: [2.0, 5.0] };
const FUELS = { pb95: 'PB95', lpg: 'LPG' };

const PRICES_KEY = 'prices';
const PENDING_TTL_S = 7 * 24 * 3600;
const RATE_WINDOW_S = 3600;
const RATE_LIMIT = 20;
const MAX_BODY_BYTES = 1024;

// `ORLEN_KV` is the dashboard binding; `PRICES` is the older wrangler.toml name.
function kv(env) {
  return env.ORLEN_KV ?? env.PRICES;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (request.method === 'GET' && url.pathname === '/prices') {
        return await getPrices(env);
      }
      if (request.method === 'POST' && url.pathname === '/submissions') {
        return await submit(request, env);
      }
      if (request.method === 'POST' && url.pathname === '/telegram/webhook') {
        return await telegramWebhook(request, env);
      }
      return json({ error: 'not_found' }, 404);
    } catch (err) {
      console.error(err);
      return json({ error: 'internal' }, 500);
    }
  },
};

async function getPrices(env) {
  const stored = await kv(env).get(PRICES_KEY, 'json');
  return json(stored ?? { stations: {} }, 200, {
    'Cache-Control': 'public, max-age=60',
  });
}

async function submit(request, env) {
  const length = Number(request.headers.get('content-length') ?? '0');
  if (length > MAX_BODY_BYTES) return json({ error: 'too_large' }, 413);

  let body;
  try {
    body = JSON.parse(await request.text());
  } catch {
    return json({ error: 'bad_json' }, 400);
  }
  const proposal = validateProposal(body);
  if (!proposal) return json({ error: 'invalid' }, 400);

  const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
  if (!(await allowRate(env, ip))) return json({ error: 'rate_limited' }, 429);

  const id = crypto.randomUUID();
  const pending = { ...proposal, submittedAt: new Date().toISOString() };
  await kv(env).put(`pending:${id}`, JSON.stringify(pending), {
    expirationTtl: PENDING_TTL_S,
  });

  const station = STATIONS[proposal.stationId];
  const current = (await kv(env).get(PRICES_KEY, 'json'))?.stations?.[proposal.stationId]?.[proposal.fuel];
  const lines = [
    '⛽ New price proposal',
    `${station.name}`,
    `${station.address}`,
    `${FUELS[proposal.fuel]}: ${proposal.price.toFixed(2)} zł`,
    current ? `Current: ${Number(current.price).toFixed(2)} zł (${current.updatedAt})` : 'Current: none',
  ];
  const sent = await telegram(env, 'sendMessage', {
    chat_id: env.TELEGRAM_ADMIN_CHAT_ID,
    text: lines.join('\n'),
    reply_markup: {
      inline_keyboard: [[
        { text: '✅ Approve & Publish', callback_data: `a:${id}` },
        { text: '❌ Reject', callback_data: `r:${id}` },
      ]],
    },
  });
  if (!sent.ok) {
    await kv(env).delete(`pending:${id}`);
    return json({ error: 'notify_failed' }, 502);
  }
  return json({ status: 'pending', id }, 202);
}

function validateProposal(body) {
  if (!body || typeof body !== 'object') return null;
  const { stationId, fuel, price } = body;
  if (typeof stationId !== 'string' || !Object.hasOwn(STATIONS, stationId)) return null;
  const station = STATIONS[stationId];
  if (!Object.hasOwn(FUELS, fuel)) return null;
  if (fuel === 'lpg' && station.lpg === false) return null;
  if (typeof price !== 'number' || !Number.isFinite(price)) return null;
  const rounded = Math.round(price * 100) / 100;
  if (Math.abs(rounded - price) > 1e-9) return null;
  const [min, max] = RANGES[fuel];
  if (rounded < min || rounded > max) return null;
  return { stationId, fuel, price: rounded };
}

// KV is eventually consistent, so this is a soft cap against spam, not a
// hard guarantee. Each check costs one KV write (free plan: 1000/day).
async function allowRate(env, ip) {
  const bucket = Math.floor(Date.now() / 1000 / RATE_WINDOW_S);
  const key = `rl:${ip}:${bucket}`;
  const count = Number((await kv(env).get(key)) ?? '0');
  if (count >= RATE_LIMIT) return false;
  await kv(env).put(key, String(count + 1), { expirationTtl: RATE_WINDOW_S * 2 });
  return true;
}

async function telegramWebhook(request, env) {
  // Telegram echoes the secret given to setWebhook; anything else is forged.
  if (request.headers.get('x-telegram-bot-api-secret-token') !== env.TELEGRAM_WEBHOOK_SECRET) {
    return new Response('forbidden', { status: 403 });
  }
  const update = await request.json();
  const query = update.callback_query;
  if (!query) return new Response('ok');

  const adminId = String(env.TELEGRAM_ADMIN_CHAT_ID);
  if (String(query.from?.id) !== adminId && String(query.message?.chat?.id) !== adminId) {
    await answer(env, query.id, 'Not allowed');
    return new Response('ok');
  }

  const match = /^([ar]):([0-9a-f-]{36})$/.exec(query.data ?? '');
  if (!match) {
    await answer(env, query.id, 'Unknown action');
    return new Response('ok');
  }
  const [, action, id] = match;
  const pendingKey = `pending:${id}`;
  const pending = await kv(env).get(pendingKey, 'json');
  if (!pending) {
    await answer(env, query.id, 'Already handled or expired');
    await closeMessage(env, query, '⏱ Already handled or expired');
    return new Response('ok');
  }

  if (action === 'a') {
    // Single admin, so a read-modify-write race on this key is not a concern.
    // Delete the pending row only AFTER the prices write succeeds — otherwise
    // a transient KV put error would drop the proposal with nothing published.
    const prices = (await kv(env).get(PRICES_KEY, 'json')) ?? { stations: {} };
    prices.stations[pending.stationId] ??= {};
    prices.stations[pending.stationId][pending.fuel] = {
      price: pending.price,
      updatedAt: new Date().toISOString(),
    };
    await kv(env).put(PRICES_KEY, JSON.stringify(prices));
    await kv(env).delete(pendingKey);
    await answer(env, query.id, 'Published');
    await closeMessage(env, query, '✅ Published');
  } else {
    await kv(env).delete(pendingKey);
    await answer(env, query.id, 'Rejected');
    await closeMessage(env, query, '❌ Rejected');
  }
  return new Response('ok');
}

function answer(env, callbackQueryId, text) {
  return telegram(env, 'answerCallbackQuery', { callback_query_id: callbackQueryId, text });
}

// Appends the verdict and removes the buttons so nobody taps twice.
function closeMessage(env, query, verdict) {
  if (!query.message) return Promise.resolve();
  return telegram(env, 'editMessageText', {
    chat_id: query.message.chat.id,
    message_id: query.message.message_id,
    text: `${query.message.text ?? ''}\n\n${verdict}`,
  });
}

async function telegram(env, method, payload) {
  const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return res.json().catch(() => ({ ok: false }));
}

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}
