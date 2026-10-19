import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';

import worker from '../src/worker.js';

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

class FakeKv {
  constructor() {
    this.values = new Map();
  }

  async get(key, type) {
    const value = this.values.get(key) ?? null;
    if (value !== null && type === 'json') return JSON.parse(value);
    return value;
  }

  async put(key, value) {
    this.values.set(key, String(value));
  }

  async delete(key) {
    this.values.delete(key);
  }

  async list({ prefix = '', cursor } = {}) {
    const keys = [...this.values.keys()]
      .filter((key) => key.startsWith(prefix))
      .map((name) => ({ name }));
    return { keys, list_complete: true, cursor: null };
  }
}

function environment() {
  return {
    ORLEN_KV: new FakeKv(),
    TELEGRAM_BOT_TOKEN: 'test-bot-token',
    TELEGRAM_ADMIN_CHAT_ID: '123456',
    TELEGRAM_WEBHOOK_SECRET: 'test-webhook-secret',
    SURVEY_ADMIN_TOKEN: 'test-survey-token',
  };
}

function surveyPayload(overrides = {}) {
  return {
    schemaVersion: 1,
    installationId: '0123456789abcdef0123456789abcdef',
    continueUsing: 'maybe',
    monthlyPrice: '10',
    mostValuableFeature: 'fuel_orlen',
    ...overrides,
  };
}

function surveyRequest(payload, headers = {}) {
  return new Request('https://worker.test/survey', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'cf-connecting-ip': '192.0.2.30',
      ...headers,
    },
    body: JSON.stringify(payload),
  });
}

function validPayload(overrides = {}) {
  return {
    schemaVersion: 1,
    category: 'overlay',
    description: 'Cancel button changed the overlay layout.',
    reportedAt: '2026-10-19T12:00:00.000Z',
    diagnostics: {
      appVersion: '5.0.4+9',
      deviceModel: 'Samsung SM-S928B',
      androidVersion: 'Android 15 (SDK 35)',
      language: 'tr',
      pillOrientation: 'horizontal',
      showOverlayCancel: true,
      notificationControls: true,
      hidePill: false,
      steeringWheel: true,
      autoComplete: false,
      keepScreenOn: true,
    },
    crashLog: null,
    ...overrides,
  };
}

function bugRequest(payload, screenshot = null, headers = {}) {
  const form = new FormData();
  form.set('payload', JSON.stringify(payload));
  if (screenshot) {
    form.set(
      'screenshot',
      new Blob([screenshot.bytes], { type: screenshot.type }),
      screenshot.name,
    );
  }
  return new Request('https://worker.test/bug-report', {
    method: 'POST',
    headers: { 'cf-connecting-ip': '192.0.2.10', ...headers },
    body: form,
  });
}

function telegramSuccess(calls) {
  globalThis.fetch = async (url, options) => {
    calls.push({ url: String(url), options });
    const messageId = calls.length;
    return Response.json({ ok: true, result: { message_id: messageId } });
  };
}

test('accepts a valid text report and rejects its sequential duplicate', async () => {
  const env = environment();
  const calls = [];
  telegramSuccess(calls);

  const first = await worker.fetch(bugRequest(validPayload()), env);
  assert.equal(first.status, 201);
  assert.deepEqual(await first.json(), { status: 'sent' });
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/sendMessage$/);
  const telegramBody = JSON.parse(calls[0].options.body);
  assert.equal(telegramBody.chat_id, env.TELEGRAM_ADMIN_CHAT_ID);
  assert.match(telegramBody.text, /Cancel button changed/);
  assert.equal('parse_mode' in telegramBody, false);

  const duplicate = await worker.fetch(bugRequest(validPayload()), env);
  assert.equal(duplicate.status, 409);
  assert.equal(calls.length, 1);
});

test('uploads one valid screenshot with sendPhoto before the report text', async () => {
  const env = environment();
  const calls = [];
  telegramSuccess(calls);
  const png = {
    type: 'image/png',
    name: 'screen.png',
    bytes: new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1]),
  };

  const response = await worker.fetch(bugRequest(validPayload(), png), env);
  assert.equal(response.status, 201);
  assert.equal(calls.length, 2);
  assert.match(calls[0].url, /\/sendPhoto$/);
  assert.ok(calls[0].options.body instanceof FormData);
  assert.equal(calls[0].options.body.get('chat_id'), env.TELEGRAM_ADMIN_CHAT_ID);
  assert.match(calls[1].url, /\/sendMessage$/);
});

test('enforces POST, schema, field limits, and screenshot type/signature', async () => {
  const env = environment();
  let telegramCalls = 0;
  globalThis.fetch = async () => {
    telegramCalls++;
    return Response.json({ ok: true });
  };

  const get = await worker.fetch(new Request('https://worker.test/bug-report'), env);
  assert.equal(get.status, 405);
  assert.equal(get.headers.get('allow'), 'POST');

  assert.equal((await worker.fetch(bugRequest(validPayload({ description: '' })), env)).status, 400);
  assert.equal((await worker.fetch(bugRequest(validPayload({ category: 'anything' })), env)).status, 400);
  assert.equal((await worker.fetch(bugRequest(validPayload({ chatId: 'attacker' })), env)).status, 400);
  assert.equal(
    (await worker.fetch(bugRequest(validPayload({ description: 'x'.repeat(1001) })), env)).status,
    400,
  );
  const fakePng = { type: 'image/png', name: 'fake.png', bytes: new Uint8Array([1, 2, 3]) };
  assert.equal((await worker.fetch(bugRequest(validPayload(), fakePng), env)).status, 400);
  assert.equal(telegramCalls, 0);
});

test('rejects an oversized request body before multipart parsing', async () => {
  const env = environment();
  const body = new Uint8Array(6 * 1024 * 1024 + 1);
  const request = new Request('https://worker.test/bug-report', {
    method: 'POST',
    headers: { 'content-type': 'multipart/form-data; boundary=x' },
    body,
  });
  const response = await worker.fetch(request, env);
  assert.equal(response.status, 413);
});

test('Telegram failure returns 502 and allows a retry', async () => {
  const env = environment();
  let fail = true;
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    return fail
      ? Response.json({ ok: false }, { status: 500 })
      : Response.json({ ok: true, result: { message_id: 7 } });
  };

  const failed = await worker.fetch(bugRequest(validPayload()), env);
  assert.equal(failed.status, 502);
  fail = false;
  const retried = await worker.fetch(bugRequest(validPayload()), env);
  assert.equal(retried.status, 201);
  assert.equal(calls, 2);
});

test('rate-limits the public endpoint without storing report contents', async () => {
  const env = environment();
  telegramSuccess([]);
  for (let i = 0; i < 5; i++) {
    const response = await worker.fetch(
      bugRequest(validPayload({ description: `Distinct report ${i}` })),
      env,
    );
    assert.equal(response.status, 201);
  }
  const limited = await worker.fetch(
    bugRequest(validPayload({ description: 'Sixth report' })),
    env,
  );
  assert.equal(limited.status, 429);
  for (const [key, value] of env.ORLEN_KV.values) {
    assert.ok(key.startsWith('bug:rl:') || key.startsWith('bug:dedupe:'));
    assert.doesNotMatch(value, /Distinct report|Sixth report/);
  }
});

test('existing fuel submission and webhook approval behavior remains intact', async () => {
  const env = environment();
  const calls = [];
  telegramSuccess(calls);
  const proposal = new Request('https://worker.test/submissions', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'cf-connecting-ip': '192.0.2.20',
    },
    body: JSON.stringify({ stationId: 'nowohucka-71', fuel: 'pb95', price: 6.29 }),
  });
  const submitted = await worker.fetch(proposal, env);
  assert.equal(submitted.status, 202);
  const { id } = await submitted.json();
  assert.match(calls[0].url, /\/sendMessage$/);
  assert.ok(JSON.parse(calls[0].options.body).reply_markup);

  const callback = new Request('https://worker.test/telegram/webhook', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-telegram-bot-api-secret-token': env.TELEGRAM_WEBHOOK_SECRET,
    },
    body: JSON.stringify({
      callback_query: {
        id: 'callback-1',
        data: `a:${id}`,
        from: { id: env.TELEGRAM_ADMIN_CHAT_ID },
        message: {
          chat: { id: env.TELEGRAM_ADMIN_CHAT_ID },
          message_id: 1,
          text: 'proposal',
        },
      },
    }),
  });
  assert.equal((await worker.fetch(callback, env)).status, 200);
  const prices = await worker.fetch(new Request('https://worker.test/prices'), env);
  assert.equal(prices.status, 200);
  assert.equal((await prices.json()).stations['nowohucka-71'].pb95.price, 6.29);
});

test('records a survey response once and keeps the payload anonymous', async () => {
  const env = environment();
  const first = await worker.fetch(surveyRequest(surveyPayload()), env);
  assert.equal(first.status, 201);
  assert.deepEqual(await first.json(), { status: 'recorded' });

  const duplicate = await worker.fetch(surveyRequest(surveyPayload()), env);
  assert.equal(duplicate.status, 200);
  assert.deepEqual(await duplicate.json(), { status: 'duplicate' });

  const responseKeys = [...env.ORLEN_KV.values.keys()]
    .filter((key) => key.startsWith('survey:v1:response:'));
  assert.equal(responseKeys.length, 1);
  const stored = env.ORLEN_KV.values.get(responseKeys[0]);
  assert.deepEqual(JSON.parse(stored), {
    schemaVersion: 1,
    continueUsing: 'maybe',
    monthlyPrice: '10',
    mostValuableFeature: 'fuel_orlen',
  });
  assert.doesNotMatch(stored, /name|phone|email|location|earnings/i);
});

test('rejects malformed survey bodies and wrong methods', async () => {
  const env = environment();

  const get = await worker.fetch(new Request('https://worker.test/survey'), env);
  assert.equal(get.status, 405);
  assert.equal(get.headers.get('allow'), 'POST');

  const wrongType = await worker.fetch(
    surveyRequest(surveyPayload(), { 'content-type': 'text/plain' }),
    env,
  );
  assert.equal(wrongType.status, 415);

  assert.equal(
    (await worker.fetch(surveyRequest(surveyPayload({ continueUsing: 'probably' })), env)).status,
    400,
  );
  assert.equal(
    (await worker.fetch(surveyRequest(surveyPayload({ monthlyPrice: '99' })), env)).status,
    400,
  );
  assert.equal(
    (await worker.fetch(surveyRequest(surveyPayload({ mostValuableFeature: 'ads' })), env)).status,
    400,
  );
  assert.equal(
    (await worker.fetch(surveyRequest(surveyPayload({ schemaVersion: 2 })), env)).status,
    400,
  );
  assert.equal(
    (await worker.fetch(surveyRequest(surveyPayload({ installationId: 'nope' })), env)).status,
    400,
  );
  assert.equal(
    (await worker.fetch(surveyRequest(surveyPayload({ extra: 'field' })), env)).status,
    400,
  );

  const oversized = new Request('https://worker.test/survey', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'cf-connecting-ip': '192.0.2.31' },
    body: JSON.stringify({ ...surveyPayload(), pad: 'x'.repeat(3000) }),
  });
  assert.equal((await worker.fetch(oversized, env)).status, 413);
  assert.equal(
    [...env.ORLEN_KV.values.keys()].filter((key) => key.startsWith('survey:v1:response:')).length,
    0,
  );
});

test('rate-limits new survey installations from one IP', async () => {
  const env = environment();
  for (let i = 0; i < 60; i++) {
    const id = i.toString(16).padStart(32, '0');
    const response = await worker.fetch(
      surveyRequest(surveyPayload({ installationId: id })),
      env,
    );
    assert.equal(response.status, 201);
  }
  const limited = await worker.fetch(
    surveyRequest(surveyPayload({ installationId: 'f'.repeat(32) })),
    env,
  );
  assert.equal(limited.status, 429);
});

test('survey summary requires the admin token and returns aggregates only', async () => {
  const env = environment();
  await worker.fetch(
    surveyRequest(surveyPayload({ installationId: 'a'.repeat(32) })),
    env,
  );
  await worker.fetch(
    surveyRequest(
      surveyPayload({
        installationId: 'b'.repeat(32),
        continueUsing: 'yes',
        monthlyPrice: '15',
        mostValuableFeature: 'overlay_counters',
      }),
    ),
    env,
  );
  await worker.fetch(
    surveyRequest(
      surveyPayload({
        installationId: 'c'.repeat(32),
        continueUsing: 'no',
        monthlyPrice: 'not_pay',
        mostValuableFeature: 'other',
      }),
    ),
    env,
  );

  const unauthorized = await worker.fetch(
    new Request('https://worker.test/survey/summary'),
    env,
  );
  assert.equal(unauthorized.status, 403);

  const authorized = await worker.fetch(
    new Request('https://worker.test/survey/summary', {
      headers: { authorization: `Bearer ${env.SURVEY_ADMIN_TOKEN}` },
    }),
    env,
  );
  assert.equal(authorized.status, 200);
  const summary = await authorized.json();
  assert.equal(summary.totalResponses, 3);
  assert.equal(summary.continueUsing.yes.count, 1);
  assert.equal(summary.continueUsing.maybe.count, 1);
  assert.equal(summary.continueUsing.no.count, 1);
  assert.equal(summary.monthlyPrice['15'].count, 1);
  assert.equal(summary.mostValuableFeature.fuel_orlen.count, 1);
  const serialized = JSON.stringify(summary);
  assert.doesNotMatch(serialized, /a{32}|b{32}|c{32}/);
  assert.doesNotMatch(serialized, /installationId/);
});

test('telegram admin can request an on-demand survey summary', async () => {
  const env = environment();
  await worker.fetch(
    surveyRequest(surveyPayload({ installationId: 'd'.repeat(32) })),
    env,
  );
  const calls = [];
  telegramSuccess(calls);
  const webhook = new Request('https://worker.test/telegram/webhook', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-telegram-bot-api-secret-token': env.TELEGRAM_WEBHOOK_SECRET,
    },
    body: JSON.stringify({
      message: {
        chat: { id: env.TELEGRAM_ADMIN_CHAT_ID },
        from: { id: env.TELEGRAM_ADMIN_CHAT_ID },
        text: '/surveysummary',
      },
    }),
  });

  assert.equal((await worker.fetch(webhook, env)).status, 200);
  assert.equal(calls.length, 1);
  const body = JSON.parse(calls[0].options.body);
  assert.equal(body.chat_id, env.TELEGRAM_ADMIN_CHAT_ID);
  assert.match(body.text, /Responses: 1/);
  assert.doesNotMatch(body.text, /d{32}|installationId/);
});
