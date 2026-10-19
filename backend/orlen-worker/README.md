# RateHelper relay (Cloudflare Worker + Telegram)

Backend for the app's **Orlen Fuel Prices** screen (`lib/fuel/`), explicit
user-submitted bug reports and the one-time **v5.1.0 pricing/feature survey**.
Fuel approvals, bug reports and survey responses have separate routes,
validators, rate-limit prefixes, KV key namespaces and Telegram message formats.
Drivers propose PB95 / LPG prices; the admin approves each one from Telegram
before it becomes public.

```
App ──POST /submissions──▶ Worker ──sendMessage──▶ Telegram (admin)
                             │  KV pending:<uuid> (7 days)      │
                             │                                  │ taps ✅ / ❌
App ◀──GET /prices──── Worker ◀──POST /telegram/webhook─────────┘
                       KV "prices"  (only approved values)
```

## API contract (the app depends on this)

| Route | Body / response |
|---|---|
| `GET /prices` | `200 {"stations": {"<stationId>": {"pb95": {"price": 6.29, "updatedAt": "2026-10-17T08:00:00.000Z"}, "lpg": {...}}}}` |
| `POST /submissions` | Request `{"stationId": "nowohucka-71", "fuel": "pb95" \| "lpg", "price": 6.29}` → `202 {"status":"pending","id":"<uuid>"}`; `400` invalid; `429` rate-limited; `502` Telegram unreachable |
| `POST /telegram/webhook` | Telegram only; requires the `X-Telegram-Bot-Api-Secret-Token` header |
| `POST /bug-report` | Public, POST-only multipart request: one fixed-schema JSON `payload` part and optional PNG/JPEG `screenshot` part (max 5 MB). Returns `201` only after Telegram accepts every required message; `400` invalid; `409` duplicate; `413` too large; `429` rate-limited; `502` Telegram failure. |
| `POST /survey` | Public, POST-only JSON body: `{"schemaVersion":1,"installationId":"<32 hex>","continueUsing":"yes\|maybe\|no","monthlyPrice":"5\|10\|15\|20\|25_plus\|not_pay","mostValuableFeature":"overlay_counters\|steering_notifications\|earnings_rental\|fuel_orlen\|weekly_reports\|other"}`. `201 {"status":"recorded"}`; `200 {"status":"duplicate"}` for the same installation id; `400`/`413`/`415`/`429` otherwise. |
| `GET /survey/summary` | Protected aggregate JSON. Requires `Authorization: Bearer <SURVEY_ADMIN_TOKEN>`. `403` without it; `503` when the token or KV is not configured. Returns counts and percentages only, never installation ids. |

Validation matches the app: known station id, `pb95` or `lpg` (LPG refused for
stations with `lpg: false`), at most two decimals, PB95 4.00–9.00 and LPG
2.00–5.00 PLN (LPG sells near 3 zł). The app drops anything outside those
bounds from `/prices` as well.

No device identifier, location, or account is sent. The Worker sees the
caller's IP (used only for the soft rate limit key, which expires after 2 h).

Bug reports are not stored. KV contains only expiring hashed-IP rate counters
and content fingerprints (5 reports/hour and 10-minute duplicate suppression).
Because Workers KV is eventually consistent, these are best-effort controls.
For production-grade atomic enforcement, add a Cloudflare WAF Rate Limiting rule
for `POST /bug-report` (or use a Durable Object); dashboard configuration is
required and cannot be made reliable with an in-memory Worker counter.

Survey responses **are** stored, but in a separate namespace:
`survey:v1:response:<installationId>` holds one anonymous answer set
(`schemaVersion`, `continueUsing`, `monthlyPrice`, `mostValuableFeature`).
The installation id appears only in the KV key and is never returned by
`/survey/summary` or sent to Telegram. `/survey` also writes one expiring
hashed-IP counter under `survey:v1:rl:<hash>:<bucket>`. Re-posting the same
installation id is a duplicate and does not create a second response or a
second counted answer. KV's eventual consistency means two concurrent first
submissions can both write the same key; aggregation reads distinct response
keys, so the answer is still counted once. Prefer the protected summary over
any aggregate counter: no unsafe read-modify-write totals are stored.

## Setup (about 10 minutes, free plans only)

1. **Bot:** message [@BotFather](https://t.me/BotFather) → `/newbot` → copy the token.
   Send any message to your new bot, then open
   `https://api.telegram.org/bot<TOKEN>/getUpdates` and copy `message.chat.id`
   (this is the admin id).
2. **Worker:**
   ```sh
   cd backend/orlen-worker
   npx wrangler login
   npx wrangler kv namespace create ORLEN_PRICES   # paste the id into wrangler.toml (binding ORLEN_KV)
   npx wrangler secret put TELEGRAM_BOT_TOKEN
   npx wrangler secret put TELEGRAM_ADMIN_CHAT_ID
   npx wrangler secret put TELEGRAM_WEBHOOK_SECRET   # any long random string
   npx wrangler secret put SURVEY_ADMIN_TOKEN        # optional; protects GET /survey/summary
   npx wrangler deploy                           # prints https://ratehelper-orlen.<you>.workers.dev
   ```
   Dashboard instead of wrangler: Settings → Bindings → KV namespace
   `ORLEN_KV`, and all four values under Variables and Secrets as **Secret**.
   `SURVEY_ADMIN_TOKEN` is optional for Telegram bot commands but required for
   `GET /survey/summary`.
3. **Webhook** (button taps **and** the admin survey command). Run this right
   after setting `TELEGRAM_WEBHOOK_SECRET`; until Telegram sends the same value,
   every button tap is refused with 403:
   ```sh
   curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
     -d "url=https://ratehelper-orlen.<you>.workers.dev/telegram/webhook" \
     -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>" \
     -d 'allowed_updates=["callback_query","message"]'
   ```
   With `message` enabled, send `/surveysummary` from the admin Telegram chat
   to receive the aggregated totals on demand. No per-respondent message is sent.
4. **App:** put the Worker URL in the gitignored `dart_defines.json`
   (`"ORLEN_API_URL": "https://ratehelper-orlen.<you>.workers.dev"`) and build
   with `--dart-define-from-file=dart_defines.json`. Without it the screen
   still lists stations, sorts by distance, and opens directions, but shows
   no prices and refuses submissions. `ORLEN_API_URL=mock` gives an in-memory
    backend that publishes every submission at once (developer testing only).
   Bug reporting uses that same HTTPS base URL and appends `/bug-report`; `mock`
   intentionally does not send bug reports.

`/bug-report` and `/survey` reuse `TELEGRAM_BOT_TOKEN` and
`TELEGRAM_ADMIN_CHAT_ID`; neither value belongs in the app or in
`dart_defines.json`. `SURVEY_ADMIN_TOKEN` protects the HTTP summary route and
is not sent to the app. The existing webhook secret and approval route are
unchanged.

## Tests

From `backend/orlen-worker`, run `npm test`. The suite uses Node's built-in test
runner and has no package dependencies.

## Free-tier budget

Workers free: 100k requests/day. KV free: 100k reads, **1k writes**/day.
A submission costs 2 writes (rate counter + pending), an approval 2 more
(prices + delete). A successful bug report costs 2 writes (rate counter +
short-lived fingerprint). A new survey response costs 2 writes (hashed-IP rate
counter + response). Duplicate survey retries hit the existing response check
first and normally cost no write. A summary request costs only reads/lists.
Plan the shared 1k-write budget accordingly.
`GET /prices` is served with `Cache-Control: max-age=60`.

## Keeping stations in sync

`src/stations.js` must list exactly the ids in `lib/fuel/orlen_stations.dart`;
`test/fuel_screen_test.dart` fails when the ids, names, addresses or
`lpg: false` flags differ. Station ids are part of the stored data, so never
rename one; add a new id instead.

## Dashboard single-file bundle

`dashboard-worker.js` is the copy pasted into the Cloudflare Dashboard; it
inlines `src/stations.js` and must otherwise stay in sync with `src/worker.js`
(including `/survey` and `/survey/summary`). It has no relative imports.

Regenerate the bundle as **UTF-8** (read and write with the encoding explicitly;
a Windows PowerShell `Get-Content` → `Set-Content` round-trip without `-Encoding utf8`
silently double-encoded Polish station names and Telegram emojis in the
v5.1.0 bundle). After any regeneration: `node --check dashboard-worker.js`,
`npm test`, and `flutter test test/fuel_screen_test.dart` (stations, names,
addresses and `lpg` flags must match).
