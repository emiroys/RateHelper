# RateHelper relay (Cloudflare Worker + Telegram)

Backend for the app's **Orlen Fuel Prices** screen (`lib/fuel/`) and explicit
user-submitted bug reports. Fuel approvals and bug reports have separate routes,
validators, rate-limit prefixes, and Telegram message formats.
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
   npx wrangler deploy                           # prints https://ratehelper-orlen.<you>.workers.dev
   ```
   Dashboard instead of wrangler: Settings → Bindings → KV namespace
   `ORLEN_KV`, and all three values under Variables and Secrets as **Secret**.
3. **Webhook** (only button taps are needed). Run this right after setting
   `TELEGRAM_WEBHOOK_SECRET`; until Telegram sends the same value, every
   button tap is refused with 403:
   ```sh
   curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
     -d "url=https://ratehelper-orlen.<you>.workers.dev/telegram/webhook" \
     -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>" \
     -d 'allowed_updates=["callback_query"]'
   ```
4. **App:** put the Worker URL in the gitignored `dart_defines.json`
   (`"ORLEN_API_URL": "https://ratehelper-orlen.<you>.workers.dev"`) and build
   with `--dart-define-from-file=dart_defines.json`. Without it the screen
   still lists stations, sorts by distance, and opens directions, but shows
   no prices and refuses submissions. `ORLEN_API_URL=mock` gives an in-memory
    backend that publishes every submission at once (developer testing only).
   Bug reporting uses that same HTTPS base URL and appends `/bug-report`; `mock`
   intentionally does not send bug reports.

No new Telegram secret is required. `/bug-report` reuses
`TELEGRAM_BOT_TOKEN` and `TELEGRAM_ADMIN_CHAT_ID`; neither value belongs in the
app or in `dart_defines.json`. The existing webhook secret and approval route
are unchanged.

## Tests

From `backend/orlen-worker`, run `npm test`. The suite uses Node's built-in test
runner and has no package dependencies.

## Free-tier budget

Workers free: 100k requests/day. KV free: 100k reads, **1k writes**/day.
A submission costs 2 writes (rate counter + pending), an approval 2 more
(prices + delete). A successful bug report costs 2 writes (rate counter +
short-lived fingerprint). Plan the shared 1k-write budget accordingly.
`GET /prices` is served with `Cache-Control: max-age=60`.

## Keeping stations in sync

`src/stations.js` must list exactly the ids in `lib/fuel/orlen_stations.dart`;
`test/fuel_screen_test.dart` fails when they differ. Station ids are part of
the stored data, so never rename one; add a new id instead.
