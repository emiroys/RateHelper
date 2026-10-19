# GitHub Release Checklist — RateHelper v5.1.0 (OTA)

**Türkçe adım adım rehber:** [`YAYIN_TR.md`](YAYIN_TR.md)

**OTA manifest şablonu:** [`update.json`](update.json)

**Driver notes:** [`RELEASE_NOTES_v5.1.0_PL.md`](RELEASE_NOTES_v5.1.0_PL.md) (PL/TR/EN)

Use this every time you ship a new version. Misaligned `pubspec`, Gist, and GitHub Release tag is the #1 cause of false update prompts or silent “already up to date”.

**Publish order:** Worker → final checks → signed APK → GitHub Release → verify asset URL → Gist **last**.

## 0. Deploy the Cloudflare Worker first

The fuel-price and survey endpoints must exist before v5.1.0 users update; otherwise fuel submissions and survey answers stay queued locally.

1. Cloudflare Dashboard → **Workers & Pages** → `ratehelper-orlen` → **Edit code**.
2. Paste the whole `backend/orlen-worker/dashboard-worker.js` (no relative imports; 30 stations inlined).
3. Keep the `ORLEN_KV` binding.
4. Secret **names** that must exist (never print values):
   `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ADMIN_CHAT_ID`, `TELEGRAM_WEBHOOK_SECRET`,
   `SURVEY_ADMIN_TOKEN` (new — protects `GET /survey/summary`).
5. Re-run `setWebhook` with the existing valid webhook secret and
   `allowed_updates=["callback_query","message"]` so Telegram `/surveysummary` works.
6. Verify: `/prices` returns prices, `/submissions` reaches Telegram and approval updates `/prices`, `/bug-report` reaches Telegram, `POST /survey` returns `201`/`duplicate`, `/survey/summary` returns `403` without the bearer token and aggregates with it, `/surveysummary` answers in the admin chat.
7. KV is eventually consistent: duplicate/rate-limit controls are best-effort, not strong guarantees.

## 1. Bump `pubspec.yaml`

Example:

```yaml
version: 5.1.0+10
```

- Before `+` → Gist `"latest"` (e.g. `"5.1.0"`).
- After `+` → Gist `"build"` (e.g. `10`) — **not** the arm64 `versionCode` (`2010`).
- `dart_defines.json` must be present and contain `ORLEN_API_URL` for fuel prices/submissions; never print or stage it.

Rebuild after every bump.

## 2. Build the APK

```powershell
Test-Path dart_defines.json # must be True; never print or stage the file
flutter clean
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/ --dart-define-from-file=dart_defines.json
```

Output (S24 Ultra / arm64):

```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Archive `symbols/` for this build.

## 3. Create GitHub Release

1. https://github.com/emiroys/ratehelper/releases → **Draft a new release**
2. **Tag:** `v5.1.0` (match semver; `v` prefix OK)
3. **Title:** `RateHelper v5.1.0`
4. **Description:** paste the Polish driver notes from [`RELEASE_NOTES_v5.1.0_PL.md`](RELEASE_NOTES_v5.1.0_PL.md)
5. **Status:** **Published** — drafts do not serve download URLs
6. Upload asset named exactly:

| Required filename |
|---|
| `app-arm64-v8a-release.apk` |

Case-sensitive. No zip wrapper.

Verify link shape:

```
https://github.com/emiroys/ratehelper/releases/download/v5.1.0/app-arm64-v8a-release.apk
```

`curl -I` → **200**, `Content-Type: application/vnd.android.package-archive`

## 4. Update Gist `update.json` (LAST)

Copy from [`release/update.json`](update.json), remove the local-only `_local_pending` block, and adjust:

```json
{
  "latest": "5.1.0",
  "build": 10,
  "apk_url": "https://github.com/emiroys/ratehelper/releases/download/v5.1.0/app-arm64-v8a-release.apk",
  "mandatory": false,
  "notes_tr": "...",
  "notes_pl": "...",
  "notes_en": "..."
}
```

### Critical rules

| Rule | Why |
|---|---|
| `"latest"` = pubspec version name | Numeric semver compare |
| `"build"` = pubspec build number (after `+`) | Hotfix same version name with higher build |
| `"apk_url"` tag matches published release | Wrong tag → 404 or wrong binary |
| **`latest` matches APK being served** | `latest: 5.1.0` + `v5.0.4` APK → infinite update loop |
| Asset name exactly `app-arm64-v8a-release.apk` | Allowlist rejects other names |
| `"apk_sha256"` optional | If present, lowercase hex SHA-256 of the APK bytes. If absent, the app skips the check and still installs |
| Gist updated **after** the release URL returns 200 | Never advertise an APK that does not exist yet |

**CDN cache:** Gist raw has `max-age=300`. v5 app clients cache-bust automatically. Older APKs may lag up to 5 minutes after the Gist edit.

## 5. Smoke-test on device

### A. Already on previous APK (v5.0.4)

1. Cold start → update dialog (or use manual **Ayarlar → Güncellemeleri denetle**)
2. Grant **Install unknown apps** for RateHelper if prompted
3. Tap update → in-app progress bar → Android installer opens
4. Confirm install → footer shows `v5.1.0`
5. Existing data survives: counters, weekly archive, earnings, settings
6. Onboarding/survey order: a fresh install sees the five-step wizard → survey → home; an existing install sees onboarding skipped and survey once → home
7. Manual check again → **“Masz najnowszą wersję”** / equivalent

### B. Feature regressions

| Check | Expected |
|---|---|
| Fuel hub (Stations) | 30 Kraków stations, cheapest/nearest sort, Maps/Waze directions |
| Fuel submission | Valid price reaches Telegram; approval updates `/prices` |
| Fuel receipt | Amount saves to the current week and appears in earnings |
| Notification controls | Reject/Accept buttons + live rate; denial leaves the switch off |
| Shade-only mode | Pill hidden, counters still work; turning controls off restores the pill |
| Backup & restore | Export JSON, restore preview, data applied; file is not encrypted |
| Bug report | Preview sanitized; optional screenshot/diagnostics; delivery success state |
| Survey | Appears once; no Skip/Later/back dismissal; three answers required; offline answer queues and later sends |
| Settings | Grouped cards, Contact developer, Check for updates, Setup guide |
| Overlay | %→R collapse, +/− live home sync, steering-wheel tap still counts |

### C. If in-app download fails

- **Kayıtlar → Çökme Kayıtları** — look for `[UPDATE]` lines (no secrets logged)
- Browser fallback may still stall at 100% on Chrome/Samsung — fix is the OTA path, not the browser

## 6. First-time OTA bootstrap

Users on APK **without** OTA code must install **one manual** v5.0.1+ build (Samsung Internet / Files). After that, all future updates can flow through in-app OTA (current line: **v5.1.0+10**).

**Do not** point Gist `apk_url` at an older release while testing a higher `latest` — you will reinstall old code and lose OTA.

## Common failures

| Symptom | Fix |
|---|---|
| Update every launch after “install” | Align Gist `latest` with `apk_url` release version |
| Manual check says up to date but Gist is newer | Manifest unreachable; check `[UPDATE]` log |
| İndir / download 404 | Publish release, correct asset name |
| Chrome 100% stuck | Use in-app OTA (v5+) |
| Signature error on upgrade | Same keystore as previous release; else uninstall + reinstall |
| `/surveysummary` does nothing | Webhook missing `message` in `allowed_updates`, or message sent from a non-admin chat |
| `/survey/summary` returns 503 | `SURVEY_ADMIN_TOKEN` secret missing in the Worker |
| Survey answers not visible | Worker still on the old bundle (no `/survey` route), or survey answers are still queued offline |

## Related docs

- **Publish (TR):** [`YAYIN_TR.md`](YAYIN_TR.md)
- **v5.1.0 maintainer changelog:** [`CHANGELOG_v5.1.0.md`](CHANGELOG_v5.1.0.md)
- **Manifest + release notes text:** [`update.json`](update.json)
- Architecture: [`../README.md`](../README.md) §7 OTA flow
