# RateHelper v5.1.0 — maintainer changelog

**Version:** `5.1.0+10` (arm64 `versionCode` 2010)  
**Driver notes:** `release/RELEASE_NOTES_v5.1.0_{TR,PL,EN}.md`  
**OTA one-liners:** `release/update.json` → `notes_*`  
**Baseline:** `v5.0.4` (tag `e52e2fb`), baseline post-release commits `c11a9f2`, `80a68e5`, `1ab1b27`, `c56caa3`, `51cc138`, `b493e85`

---

## ORLEN fuel hub (`lib/fuel/*`, `backend/orlen-worker/*`)

- `FuelScreen` with two tabs: **Stations** (PB95/LPG prices, cheapest/nearest sort, directions) and **Add fuel** (fuel receipt amount, quick pills, co-driver split, current week receipts).
- 30 ORLEN stations inside Kraków city limits; station ids are stable stored keys and match `backend/orlen-worker/src/stations.js`. Non-fuel ORLEN points (Paczka, car wash, EV-only, convenience) excluded.
- Station audit (2026-10): 28 → 30 records; 11 address/name corrections; duplicates and wrong addresses (`kolorowe-9f`, `opolska-5`, `strusia-24`, `wandy-30a`, `wielicka-31`) resolved without changing existing ids. Two records added: `kazimierza-wielkiego-121`, `kolorowe-10a`. LPG availability left unchanged (manual review notes in `handoff.md`; `wloczkow` and `kolorowe-10a` are `lpg: false`).
- Cloudflare Worker endpoints used by the app: `GET /prices`, `POST /submissions`; Telegram admin approval/rejection flow unchanged.
- `ORLEN_API_URL` must be present in the release build's `dart_defines.json`; without it the hub still shows stations, sorting, navigation and receipts but remote prices and submissions are disabled.
- Worker tests: `backend/orlen-worker/test/worker.test.js`.

## Notification shade controls and shade-only mode

- Optional Reject +1 / Accept +1 buttons and the live acceptance rate in the overlay foreground notification (`ShadeControls`, `ShadeControls.kt`, `ShadeNotificationThrottle`).
- Optional **shade-only** mode hides the floating pill while counters keep working from the shade and the steering wheel; it is offered only while notification controls are on and is cleared when they are turned off or the permission is revoked.
- `POST_NOTIFICATIONS` is requested only when the driver turns the feature on; denial leaves it off.

## Local backup & restore

- `lib/services/backup_service.dart`: portable JSON export (settings, shift counters, weekly archive, earnings), strict validation, SHA-256, crash-safe `restore_journal.json` and startup recovery.
- Settings UI: backup, restore preview (version/week/entry count), confirmation; exported JSON is **not encrypted**.
- Home/earnings/overlay entry points run `recoverPendingRestoreIfNeeded()` so an interrupted restore finishes on the next launch.
- Survey completion keys are deliberately excluded from the backup-managed preference set.

## Five-step onboarding and startup language

- `lib/onboarding_screen.dart` rewritten as a five-step wizard: welcome, overlay permission, battery reliability, optional features, ready summary; skip consequences explained honestly.
- TR/EN/PL header selector; `lib/startup_language.dart`: a saved `appLanguage` always wins, a fresh install follows the device locale (tr/pl, otherwise English).
- Setup Guide in Settings reuses the wizard and forwards language changes to home/overlay.

## In-app bug reporting

- `lib/bug_report_sheet.dart` + `lib/bug_report_api.dart`: fixed-schema multipart `POST /bug-report` through the Worker; optional screenshot (PNG/JPEG, 5 MB), optional diagnostics, crash logs **off** by default; full preview and one direct Send action with loading/success/failure states.
- No Telegram tokens or chat ids in the app. Worker tests cover schema, size/signature limits, duplicate suppression and rate limiting.

## One-time pricing/feature survey (market research only)

- `lib/survey_screen.dart`, `lib/survey_store.dart`, `lib/survey_api.dart`: one survey per installation, shown after onboarding (fresh install) or after updating (existing install); no skip/later/back dismissal; three required questions; versioned `survey_v1_completed` flag.
- Offline answers are queued in `survey_v1_pending` before completion is marked and retried once per foreground/resume (5-minute guard, no timers/background polling).
- Anonymous payload only: schema version, random 32-hex installation id, three answer ids. No name, phone, email, GPS, trip or earnings data.
- Worker: `POST /survey`, protected `GET /survey/summary` (`SURVEY_ADMIN_TOKEN`, hashed comparison) and Telegram `/surveysummary` from the admin chat. KV namespace `survey:v1:*`; individual responses only, aggregates computed on demand; hashed-IP 60/hour counter. KV is eventually consistent — dedupe/rate limiting are best-effort.
- No payment, subscription, paywall or feature restriction was added.

## Reliability and data integrity

- Overlay ↔ home live counter sync (`OverlaySync.pingCountersChanged`, `OverlayCounterBurst`) and strict IPC validation.
- Tap ACK / dirty-delta persistence, pending-tap drain order after week reset.
- Weekly archive v2: goal tier and thresholds stored per week, duplicate week merges, goal met/missed per saved thresholds.
- Earnings: `parseStoredAmount`, snapshot rate/rental fields, `blendedHourlyRate`, `isUnreported` placeholder weeks charge 0 rental.
- Auto-reset archives an ended week before clearing counters.

## Settings and contact

- Grouped Settings cards; **Check for updates**, **Setup guide**, **Fuel prices**, **Backup**, **Restore** and **Report a problem** rows.
- **Contact developer** row: WhatsApp via the gitignored `CONTACT_WHATSAPP` define, otherwise the GitHub issues page.
- Version fallbacks in the bug-report diagnostics and backup metadata now read the real package version or the updater's installed version instead of a hardcoded release number.

## Hardcoded version fixes

- `lib/bug_report_sheet.dart`: diagnostics fallback no longer reports `5.0.4`; it uses the native/package version and falls back to `unknown`.
- `lib/home_screen.dart`: backup metadata fallback no longer reports `5.0.5`; it reads `UpdateService.instance.installedVersion()` and lets `BackupService` write `unknown` when unavailable.

## Dashboard deployment bundle

- `backend/orlen-worker/dashboard-worker.js` regenerated from `src/worker.js` + inlined `src/stations.js` with correct UTF-8. Previous bundle had mojibake in station names/addresses and non-ASCII Telegram strings (e.g. `Åšliwiaka`, `zÅ‚`, `â›½`); fixed locally, not deployed.
- The bundle contains `/prices`, `/submissions`, `/telegram/webhook`, `/bug-report`, `/survey`, `/survey/summary` and the `/surveysummary` command, with no relative imports.

## Tests

- `flutter analyze` → no issues.
- `flutter test` → **517 passed** (survey suite 14, fuel suite 65, release-manifest guard 4).
- `cd backend/orlen-worker && npm test` → **12 passed**.
- Station parity validated across `lib/fuel/orlen_stations.dart`, `src/stations.js` and `dashboard-worker.js` (30 ids, same names/addresses/LPG flags, no duplicates).

## Release alignment

`pubspec.yaml` (`5.1.0+10`) · `release/update.json` · GitHub `v5.1.0` · Gist — [`YAYIN_TR.md`](YAYIN_TR.md). The local manifest is a template and must not be copied to the live Gist before the v5.1.0 APK exists and its URL returns 200.
