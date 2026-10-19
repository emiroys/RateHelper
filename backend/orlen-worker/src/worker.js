// RateHelper Cloudflare Worker (free plan + KV).
//
//   GET  /prices            published fuel prices
//   POST /submissions       fuel proposal -> Telegram approval message
//   POST /telegram/webhook  existing fuel approval/rejection callback
//   POST /bug-report        user-initiated bug report -> administrator
//
// Fuel approval and bug-report processing intentionally use separate routes,
// validation, rate-limit keys, and message builders.

import { STATIONS } from './stations.js';

// Same bounds as priceRange() in lib/fuel/fuel_prices.dart.
const RANGES = { pb95: [4.0, 9.0], lpg: [2.0, 5.0] };
const FUELS = { pb95: 'PB95', lpg: 'LPG' };

const PRICES_KEY = 'prices';
const PENDING_TTL_S = 7 * 24 * 3600;
const RATE_WINDOW_S = 3600;
const RATE_LIMIT = 20;
const MAX_BODY_BYTES = 1024;

const BUG_BODY_BYTES = 6 * 1024 * 1024;
const BUG_SCREENSHOT_BYTES = 5 * 1024 * 1024;
const BUG_RATE_WINDOW_S = 3600;
const BUG_RATE_LIMIT = 5;
const BUG_DEDUPE_TTL_S = 10 * 60;
const BUG_CATEGORIES = new Set([
  'overlay',
  'counters',
  'earningsFuel',
  'steeringNotification',
  'other',
]);
const BUG_MIME = new Set(['image/png', 'image/jpeg']);
const BUG_FIELDS = [
  'schemaVersion',
  'category',
  'description',
  'reportedAt',
  'diagnostics',
  'crashLog',
];
const BUG_DIAGNOSTIC_FIELDS = [
  'appVersion',
  'deviceModel',
  'androidVersion',
  'language',
  'pillOrientation',
  'showOverlayCancel',
  'notificationControls',
  'hidePill',
  'steeringWheel',
  'autoComplete',
  'keepScreenOn',
];

// `ORLEN_KV` is the dashboard binding; `PRICES` is the older wrangler.toml name.
function kv(env) {
  return env.ORLEN_KV ?? env.PRICES;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/bug-report') {
        if (request.method !== 'POST') {
          return json({ error: 'method_not_allowed' }, 405, { Allow: 'POST' });
        }
        // Do not let report contents or endpoint details escape through logs.
        try {
          return await receiveBugReport(request, env);
        } catch {
          return json({ error: 'internal' }, 500);
        }
      }
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

async function receiveBugReport(request, env) {
  if (!kv(env) || !env.TELEGRAM_BOT_TOKEN || !env.TELEGRAM_ADMIN_CHAT_ID) {
    return json({ error: 'unavailable' }, 503);
  }
  const contentType = request.headers.get('content-type') ?? '';
  if (!/^multipart\/form-data\s*;/i.test(contentType)) {
    return json({ error: 'unsupported_media_type' }, 415);
  }
  const declaredLength = Number(request.headers.get('content-length') ?? '0');
  if (Number.isFinite(declaredLength) && declaredLength > BUG_BODY_BYTES) {
    return json({ error: 'too_large' }, 413);
  }

  const raw = await request.arrayBuffer();
  if (raw.byteLength > BUG_BODY_BYTES) {
    return json({ error: 'too_large' }, 413);
  }

  let form;
  try {
    const parsedRequest = new Request(request.url, {
      method: 'POST',
      headers: { 'content-type': contentType },
      body: raw,
    });
    form = await parsedRequest.formData();
  } catch {
    return json({ error: 'invalid_multipart' }, 400);
  }
  const formKeys = [...form.keys()];
  if (formKeys.some((key) => key !== 'payload' && key !== 'screenshot')) {
    return json({ error: 'invalid' }, 400);
  }
  const payloadValues = form.getAll('payload');
  const screenshotValues = form.getAll('screenshot');
  if (payloadValues.length !== 1 || typeof payloadValues[0] !== 'string') {
    return json({ error: 'invalid' }, 400);
  }
  if (screenshotValues.length > 1) return json({ error: 'invalid' }, 400);

  let candidate;
  try {
    candidate = JSON.parse(payloadValues[0]);
  } catch {
    return json({ error: 'bad_json' }, 400);
  }
  const report = validateBugReport(candidate);
  if (!report) return json({ error: 'invalid' }, 400);

  let photo = null;
  if (screenshotValues.length === 1) {
    const file = screenshotValues[0];
    if (!isUploadedFile(file)) return json({ error: 'invalid_image' }, 400);
    const mime = file.type.toLowerCase();
    if (!BUG_MIME.has(mime)) return json({ error: 'invalid_image' }, 400);
    if (file.size < 1 || file.size > BUG_SCREENSHOT_BYTES) {
      return json({ error: 'image_too_large' }, 413);
    }
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (!validImageSignature(mime, bytes)) {
      return json({ error: 'invalid_image' }, 400);
    }
    photo = { mime, bytes };
  }

  const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
  if (!(await allowBugRate(env, ip))) {
    return json({ error: 'rate_limited' }, 429);
  }

  const fingerprint = await bugFingerprint(report, photo);
  const dedupeKey = `bug:dedupe:${fingerprint}`;
  if (await kv(env).get(dedupeKey)) {
    return json({ error: 'duplicate' }, 409);
  }
  // Reserve before delivery. A failed Telegram call removes the reservation so
  // the user can retry; KV consistency still makes this best-effort, not atomic.
  await kv(env).put(dedupeKey, '1', { expirationTtl: BUG_DEDUPE_TTL_S });

  const id = crypto.randomUUID();
  let photoMessageId = null;
  if (photo) {
    const photoResult = await sendBugPhoto(env, photo, id);
    if (!photoResult.ok) {
      await kv(env).delete(dedupeKey);
      return json({ error: 'notify_failed' }, 502);
    }
    photoMessageId = photoResult.result?.message_id ?? null;
  }

  const text = buildBugMessage(report, id, photo !== null);
  if (text.length > 4000) {
    if (photoMessageId !== null) await deleteTelegramMessage(env, photoMessageId);
    await kv(env).delete(dedupeKey);
    return json({ error: 'invalid' }, 400);
  }
  const sent = await telegram(env, 'sendMessage', {
    chat_id: env.TELEGRAM_ADMIN_CHAT_ID,
    text,
  });
  if (!sent.ok) {
    if (photoMessageId !== null) await deleteTelegramMessage(env, photoMessageId);
    await kv(env).delete(dedupeKey);
    return json({ error: 'notify_failed' }, 502);
  }
  return json({ status: 'sent' }, 201);
}

function validateBugReport(body) {
  if (!plainObjectWithExactKeys(body, BUG_FIELDS)) return null;
  if (body.schemaVersion !== 1 || !BUG_CATEGORIES.has(body.category)) return null;
  if (typeof body.description !== 'string') return null;
  const description = cleanTelegramText(body.description.trim());
  if (description.length < 1 || description.length > 1000) return null;
  if (typeof body.reportedAt !== 'string' || body.reportedAt.length > 40) return null;
  if (!Number.isFinite(Date.parse(body.reportedAt))) return null;

  let diagnostics = null;
  if (body.diagnostics !== null) {
    if (!plainObjectWithExactKeys(body.diagnostics, BUG_DIAGNOSTIC_FIELDS)) return null;
    const d = body.diagnostics;
    if (!boundedString(d.appVersion, 1, 40)) return null;
    if (!boundedString(d.deviceModel, 1, 120)) return null;
    if (!boundedString(d.androidVersion, 1, 80)) return null;
    if (!['tr', 'en', 'pl'].includes(d.language)) return null;
    if (!['horizontal', 'vertical'].includes(d.pillOrientation)) return null;
    for (const key of BUG_DIAGNOSTIC_FIELDS.slice(5)) {
      if (typeof d[key] !== 'boolean') return null;
    }
    diagnostics = {
      ...d,
      appVersion: cleanSingleLine(d.appVersion),
      deviceModel: cleanSingleLine(d.deviceModel),
      androidVersion: cleanSingleLine(d.androidVersion),
    };
  }

  let crashLog = null;
  if (body.crashLog !== null) {
    if (typeof body.crashLog !== 'string' || body.crashLog.length > 1800) return null;
    crashLog = cleanTelegramText(body.crashLog);
  }
  return {
    category: body.category,
    description,
    reportedAt: body.reportedAt,
    diagnostics,
    crashLog,
  };
}

function plainObjectWithExactKeys(value, expected) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const keys = Object.keys(value).sort();
  const wanted = [...expected].sort();
  return keys.length === wanted.length && keys.every((key, i) => key === wanted[i]);
}

function boundedString(value, min, max) {
  return typeof value === 'string' && value.length >= min && value.length <= max;
}

function cleanTelegramText(value) {
  // No Telegram parse_mode is used. Removing controls and bidi overrides keeps
  // untrusted text plain and prevents formatting/control-character tricks.
  return value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, '');
}

function cleanSingleLine(value) {
  return cleanTelegramText(value).replace(/[\r\n\t]+/g, ' ').trim();
}

function isUploadedFile(value) {
  return value && typeof value === 'object' &&
    typeof value.type === 'string' && typeof value.size === 'number' &&
    typeof value.arrayBuffer === 'function';
}

function validImageSignature(mime, bytes) {
  if (mime === 'image/png') {
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    return bytes.length >= signature.length && signature.every((byte, i) => bytes[i] === byte);
  }
  return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}

async function allowBugRate(env, ip) {
  const bucket = Math.floor(Date.now() / 1000 / BUG_RATE_WINDOW_S);
  const ipHash = await sha256Hex(new TextEncoder().encode(ip));
  const key = `bug:rl:${ipHash}:${bucket}`;
  const count = Number((await kv(env).get(key)) ?? '0');
  if (count >= BUG_RATE_LIMIT) return false;
  await kv(env).put(key, String(count + 1), {
    expirationTtl: BUG_RATE_WINDOW_S * 2,
  });
  return true;
}

async function bugFingerprint(report, photo) {
  const photoHash = photo ? await sha256Hex(photo.bytes) : '';
  const canonical = JSON.stringify(report) + '|' + photoHash;
  return sha256Hex(new TextEncoder().encode(canonical));
}

async function sha256Hex(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function buildBugMessage(report, id, hasPhoto) {
  const lines = [
    'RateHelper bug report',
    `Report ID: ${id}`,
    `Category: ${report.category}`,
    `Reported at: ${report.reportedAt}`,
    '',
    'Description:',
    report.description,
    '',
    'Diagnostics:',
  ];
  if (report.diagnostics) {
    const d = report.diagnostics;
    lines.push(
      `App version: ${d.appVersion}`,
      `Device: ${d.deviceModel}`,
      `Android: ${d.androidVersion}`,
      `Language: ${d.language}`,
      `Overlay orientation: ${d.pillOrientation}`,
      `Overlay cancel button: ${d.showOverlayCancel ? 'on' : 'off'}`,
      `Notification controls: ${d.notificationControls ? 'on' : 'off'}`,
      `Hide pill: ${d.hidePill ? 'on' : 'off'}`,
      `Steering wheel: ${d.steeringWheel ? 'on' : 'off'}`,
      `Auto-complete: ${d.autoComplete ? 'on' : 'off'}`,
      `Keep screen on: ${d.keepScreenOn ? 'on' : 'off'}`,
    );
  } else {
    lines.push('Excluded by user.');
  }
  if (report.crashLog !== null) {
    lines.push('', 'Recent error logs (client-sanitized):', report.crashLog || 'No recent error entries.');
  }
  lines.push('', `Screenshot: ${hasPhoto ? `attached in report ${id}` : 'none'}`);
  return lines.join('\n');
}

async function sendBugPhoto(env, photo, id) {
  const form = new FormData();
  form.set('chat_id', String(env.TELEGRAM_ADMIN_CHAT_ID));
  form.set('caption', `RateHelper bug report ${id} screenshot`);
  const extension = photo.mime === 'image/png' ? 'png' : 'jpg';
  form.set('photo', new Blob([photo.bytes], { type: photo.mime }), `screenshot.${extension}`);
  return telegramMultipart(env, 'sendPhoto', form);
}

function deleteTelegramMessage(env, messageId) {
  return telegram(env, 'deleteMessage', {
    chat_id: env.TELEGRAM_ADMIN_CHAT_ID,
    message_id: messageId,
  });
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
  try {
    const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${method}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    });
    if (!res.ok) return { ok: false };
    const result = await res.json().catch(() => ({ ok: false }));
    return result?.ok === true ? result : { ok: false };
  } catch {
    return { ok: false };
  }
}

async function telegramMultipart(env, method, body) {
  try {
    const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/${method}`, {
      method: 'POST',
      body,
    });
    if (!res.ok) return { ok: false };
    const result = await res.json().catch(() => ({ ok: false }));
    return result?.ok === true ? result : { ok: false };
  } catch {
    return { ok: false };
  }
}

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...headers },
  });
}
