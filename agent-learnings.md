# Agent Learnings — Anti-Eres

Living notes for agents working on this project. Keep this file aligned with **actual code**, not intent. When behavior changes, update here first.

**Agent rule:** Read this file at the **start** of any task. After finishing work that changes behavior, architecture, or known pitfalls, update this file in the **same session**.

**Current app version:** `pubspec.yaml` → `1.0.2+2` (versionName `1.0.2`, versionCode `2`).

---

## Recent Work Summary (2026-05-24)

Consolidated changelog for the overlay + OTA work in this sprint. Do not revert without reading why each decision was made.

### 1. Overlay — native drag (canonical, do not re-litigate)

| Before (broken) | After (current) |
|---|---|
| `enableDrag: false` + Flutter `Transform.translate` / `GestureDetector` / `moveOverlay` | `enableDrag: true` — native `OverlayService.onTouch()` |
| Full-screen `WindowSize.fullCover` + `OverlayFlag.focusPointer` | Small window `720×300` px + `OverlayFlag.defaultFlag` |
| Pub.dev `flutter_overlay_window` | Local fork `packages/flutter_overlay_window` (path override) |
| 5 px drag slop in upstream Java | Patched slop: `dx²+dy² < 400` (20 px) for Samsung S24 Ultra digitizer |

**Why Flutter drag failed:** 30+ attempts — platform-channel IPC jitter, pan/tap confusion on Samsung digitizer, lag on `moveOverlay`. Uber/Bolt-style overlays use native `WindowManager.updateViewLayout()` on the Android main thread.

**Files touched:**
- `packages/flutter_overlay_window/android/.../OverlayService.java` — slop patch
- `pubspec.yaml` — `flutter_overlay_window: path: packages/flutter_overlay_window`
- `lib/home_screen.dart` — `showOverlay()` config (see Overlay section)
- `lib/overlay_widget.dart` — static centered pill; tap + haptic only; `_GripIndicator` is visual

**Rebuild rule:** After editing `OverlayService.java` → `flutter clean` + release build.

### 2. OTA update checker — semver + manifest + download URL

| Issue | Fix |
|---|---|
| False “update available” on latest build | Numeric semver via `_parseVersionParts` / `_isNewerVersion`; current from `PackageInfo.fromPlatform().version` only |
| String compare trap (`1.0.10` vs `1.0.9`) | Compare `List<int>` major → minor → patch; strict `>` only |
| Download 404 | Asset must be published on GitHub Releases as exactly `app-arm64-v8a-release.apk` |
| Gist frozen to one revision | Removed commit hash from URL — must use `/raw/update.json` not `/raw/<sha>/update.json` |

**Files touched:**
- `lib/home_screen.dart` — `_checkForUpdate`, `_fetchUpdateManifest`, `_isValidApkUrl`, security guards
- `release/update.json` — canonical manifest template for Gist
- `release/GITHUB_RELEASE_CHECKLIST.md` — release publish steps
- `test/logic_test.dart` — `isVersionNewer` / `parseVersionParts` tests (6 cases)
- `pubspec.yaml` — bumped to `1.0.2+2`

**Release alignment (all three must match per ship):**
1. `pubspec.yaml` version (before `+`)
2. Gist `update.json` → `"latest"`
3. GitHub Release tag + published asset filename

---

## Archive Logic

**Key:** `weekly_archive` → `List<String>` in SharedPreferences.

**Entry format (Turkish example):** `"11-17 May: %85.00 Kabul | %2.00 İptal"`
- Date range covers Mon–Sun of the week being closed out (reset boundary is Monday 04:00 Warsaw).
- Rates are computed from prefs values *before* counters are zeroed.
- Month abbreviations come from `S.months` in `lib/l10n.dart` (TR / EN / PL — not a hard-coded Turkish-only list).
- Accept/cancel labels use `S.archiveAccept` and `S.archiveCancel` (localized).
- If start/end months differ, format is `"D1 Mon1 - D2 Mon2"`.

**When an entry is written:**
1. **Automatic reset** — `_loadAndCheckReset()` detects `lastResetTimestamp` is before the current week's Monday 04:00 boundary → `_performReset(prefs, boundary)`.
2. **Manual reset** — "RESET WEEK" button confirmed → `_performReset(prefs)` with no boundary; falls back to `_lastMonday4amWarsaw(_nowWarsaw())`.

**Guard:** `_buildArchiveEntry` returns `null` if all four counters are 0. No empty entries are saved.

**Display:** `Icons.history` AppBar button → `showModalBottomSheet` (`Color(0xFF121212)`). List rendered in reverse order (`.reversed`). Empty state: `S.noHistory`.

---

## Performance & Bug Rules (Audit — 2026-05-18)

### Race Condition: Debounced Save
- `_change()` never writes prefs directly. `_scheduleSave()` debounces with a 300 ms timer; rapid taps coalesce into one write.
- `_flushSave()` cancels the timer and calls `_saveDataNow()` immediately. Invoked from `dispose()` and `didChangeAppLifecycleState(paused)` to reduce data loss on kill.

### Reentrancy Guard: `_isLoadingOrResetting`
- `_loadAndCheckReset()` exits early if already running (e.g. rapid resume events).
- `_performReset()` runs inside that guarded block.
- Async paths check `if (!mounted) return` before `setState`.

### UI Overflow: FittedBox
- Rate card values (36 px) and counter values (48 px) use `FittedBox(fit: BoxFit.scaleDown)` to avoid horizontal overflow on narrow screens.

### Math Safety
- Division-by-zero: `total == 0` returns defaults (100.0 acceptance, 0.0 cancellation). No NaN/Infinity path in getters.
- Reset boundary uses `tz.TZDateTime` with `Europe/Warsaw` (handles CET/CEST). Do **not** assume a fixed UTC+3 offset.

### Test Coverage
- `test/logic_test.dart` — **28** unit tests for extracted pure functions:
  - `acceptanceRate`, `cancellationRate`: zero-div, boundaries, large values.
  - `isVersionNewer`, `parseVersionParts`: numeric semver, `1.0.10` vs `1.0.9`, `v` prefix, `+build`.
  - `lastMonday4am`: boundaries, weekdays, month/year crossings, July loop asserting Monday + 04:00.

**Mistake / gap:** Tests mirror reset logic with plain `DateTime`, while production uses `tz.TZDateTime` + `Europe/Warsaw`. DST edge cases are **not** covered by tests.

---

## Driving Hardware Rules (2026-05-18)

### Timezone: Europe/Warsaw (Hard-Locked)
- Package: `timezone` (actively used).
- `tz.initializeTimeZones()` in `main()` before `runApp`.
- All reset/archive boundary logic: `_lastMonday4amWarsaw()`, `_nowWarsaw()`, `_formatDateRange()` with `tz.getLocation('Europe/Warsaw')`. Device locale is irrelevant.

**Mistake:** `flutter_timezone` is listed in `pubspec.yaml` but **not imported anywhere in `lib/`**. Dead dependency unless future code reads device zone.

### Wakelock
- Package: `wakelock_plus`.
- `enable()` in `initState` and on `resumed`; `disable()` in `dispose` and on `paused`.

### Haptic Feedback (Main Screen)
- `HapticFeedback.lightImpact()` on **[+]** taps.
- `HapticFeedback.mediumImpact()` on **[-]** taps.

### Android Permissions (`AndroidManifest.xml`, before `<application>`)
- `WAKE_LOCK`, `VIBRATE`, `SYSTEM_ALERT_WINDOW`
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS` (overlay foreground service)

---

## Recovery Target Calculator (`neededForRecovery`)

**Math:** `(accepted + X) / (total + X) > 0.80` → `X = max(1, 4*rejected - accepted + 1)`.

**Display:** Hidden when `acceptanceRate >= 80.0`. Amber card `Color(0xFFF59E0B)`, copy from `S.recovery(n)`.

---

## Single-Step Undo

**State:** Four nullable ints; `_canUndo` ⇔ `_prevAccepted != null`. One step only — no chain.

---

## Overlay — Separate Isolate State

### Architecture
- Package: **local fork** `packages/flutter_overlay_window` (path override; upstream base `0.5.0`).
- Entry: `@pragma('vm:entry-point') void overlayMain()` in `main.dart`.
- Widget: `lib/overlay_widget.dart` — separate isolate, own `SharedPreferences`.

### Native drag (canonical — do not re-implement in Flutter)
- `enableDrag: true` → `OverlayService.java` `onTouch()` → `WindowManager.updateViewLayout()` on Android main thread.
- Small window **720×300 device pixels** — only pill blocks touches; Uber/Bolt gets the rest of the screen.
- Pill **static** (`Center` in `overlay_widget.dart`); dragging moves the whole native window.

**Local patch (S24 Ultra required):**
```
packages/flutter_overlay_window/android/.../OverlayService.java
dx * dx + dy * dy < 400   // 20 px slop (upstream uses < 25 = 5 px)
```

**Never add back:** `_dragOffset`, `Transform.translate`, pan `GestureDetector`, `moveOverlay`, full-screen overlay for drag.

### SharedPreferences Sync (Critical)
- **Overlay:** `await prefs.reload()` before every read/increment/write.
- **Main app:** On `resumed`, `_reloadAndSync()` → `prefs.reload()` then `_loadAndCheckReset()`.

### `showOverlay()` Config (`home_screen.dart`)
```dart
height: 300,                              // device pixels
width: 720,
alignment: OverlayAlignment.topLeft,
flag: OverlayFlag.defaultFlag,
enableDrag: true,
positionGravity: PositionGravity.none,
startPosition: const OverlayPosition(0, 60),
overlayTitle: 'Anti-Eres',                 // hardcoded; S.overlayTitle exists but unused here
overlayContent: S.overlayContent,
visibility: NotificationVisibility.visibilitySecret,
```

### Overlay UI
- Pill: `200×88` dp, `#E6161616`, centered in native window.
- **−** crimson → `rejectedRequests`; **+** emerald → `acceptedRequests` (increment only).
- `_GripIndicator` — visual only, no gesture handler.
- Watermark: `KK4181R`. No in-overlay close — toggle from main AppBar `picture_in_picture_alt_rounded`.
- Haptics: light on +, medium on −.

### Android
- Runtime overlay permission: `isPermissionGranted()` / `requestPermission()`.
- After Java patch → clean release build.

---

## OTA Update Checker

### Flow (`home_screen.dart`)
1. Cold start → `_init()` → `unawaited(_checkForUpdate())`.
2. Fetch Gist manifest via hardened `HttpClient`.
3. Current version: `PackageInfo.fromPlatform().version.trim()` — **never hardcode**.
4. Show snackbar only if `_isNewerVersion(latest, current)` **and** `_isValidApkUrl(apkUrl)`.

### Gist manifest URL (live — no commit pin)
- Value in `.env` as `GIST_URL` → `Env.gistUrl` (obfuscated at build time).
- Example: `https://gist.githubusercontent.com/emiroys/5215af1f8d82dfeecab20e03eb8d76e1/raw/update.json`
- **Never** use `/raw/<commit-sha>/update.json` — freezes all installed clients to one Gist revision forever.
- Repo template: `release/update.json` — copy contents to Gist on each release.

```json
{
  "latest": "1.0.2",
  "apk_url": "https://github.com/emiroys/anti-eres/releases/latest/download/app-arm64-v8a-release.apk"
}
```

### Semver rules
- `_parseVersionParts`: strip `v`/`V`, ignore `+build` and `-prerelease` suffix, parse segments as `int`.
- `_isNewerVersion`: numeric compare major → minor → patch; equal → **no** update prompt.
- Tests in `test/logic_test.dart` group `isVersionNewer`.

### Security guards (`_fetchUpdateManifest` — do not weaken)
| Guard | Implementation |
|---|---|
| Host allowlist | `_allowedManifestHost = gist.githubusercontent.com`; pre-flight on parsed URI |
| MITM block | `StrictSecurityHttpOverrides` (global) — invalid TLS certs rejected app-wide |
| Redirect block | `request.followRedirects = false` |
| APK host | `_openApkUrl` re-checks `https://github.com/emiroys/anti-eres/releases/` prefix |
| APK shape | `_isValidApkUrl`: must contain `/latest/download/` and end with `/app-arm64-v8a-release.apk` |
| JSON keys | `decoded['latest']` and `decoded['apk_url']` only (not legacy `download_url`) |

Silent failure policy: any fetch/parse/validation error → no snackbar, no download prompt.

### Common failures
| Symptom | Cause | Fix |
|---|---|---|
| Update shown on latest build | `pubspec` < Gist `"latest"` | Align versions, rebuild |
| Update never shown after Gist edit | Pinned Gist URL with commit hash | Use `/raw/update.json` |
| İndir → 404 | No published release, draft release, or wrong asset name | See `release/GITHUB_RELEASE_CHECKLIST.md` |
| İndir blocked silently | `apk_url` fails `_isValidApkUrl` | Use exact canonical URL above |

### Ship checklist (short)
1. Bump `pubspec.yaml` → rebuild APK (`--split-per-abi`).
2. Publish GitHub Release (not draft), upload `app-arm64-v8a-release.apk`.
3. Verify `curl -I` on canonical download URL → 200.
4. Update Gist from `release/update.json`.
5. Smoke: old APK shows snackbar; new APK does not; download works.

---

## App Branding — Anti-Eres

| User-visible | Value |
|---|---|
| Launcher / `android:label` | Anti-Eres |
| `MaterialApp.title` | Anti-Eres |
| Internal package / applicationId | `ubertakip` / `com.ubertakip.ubertakip` |
| Dart app class | `UberTakipApp` |

Overlay notification title in code: hardcoded `'Anti-Eres'` (not `S.overlayTitle`).

---

## Internationalization (`lib/l10n.dart`)

- TR (default), EN, PL via `AppLang` + prefs key `appLanguage`.
- All user-facing strings via `S.*` — including `S.updateAvailable`, `S.updateDownload`, overlay snackbars.

---

## Global HTTP Security Policy (2026-05-24)

All `HttpClient()` instances app-wide reject invalid TLS certificates via `StrictSecurityHttpOverrides` installed at boot.

- **File:** `lib/secure_http.dart`
- **Install:** `HttpOverrides.global = StrictSecurityHttpOverrides();` immediately after `WidgetsFlutterBinding.ensureInitialized()` in **both** `main()` and `overlayMain()` (`lib/main.dart`).
- **Behavior:** `badCertificateCallback → false` (MITM / captive portal / self-signed blocked); default `connectionTimeout` 10 s on factory-created clients.
- **Per-request guards unchanged:** `_fetchUpdateManifest()` still uses host allowlist + `followRedirects = false` — global override does not follow redirects for you.
- **google_fonts:** `GoogleFonts.config.allowRuntimeFetching = false` in `main()` — zero runtime font HTTP; no conflict with `HttpOverrides`.
- **Overlay isolate:** separate VM isolate → must set `HttpOverrides.global` in `overlayMain()` too (patched).

Do not re-add local `badCertificateCallback` in individual fetch sites unless a documented exception is required.

---

## Pre-Release Audit (2026-05-22, still valid)

### Logging
- Use `lib/log.dart`: `logd()` gated in release; `loge()` always logs + writes crash file.
- Crash log: `Android/data/com.ubertakip.ubertakip/files/crash.log` (64 KB FIFO).

### MainActivity MethodChannel `com.ubertakip.ubertakip/system`
- Battery optimization prompts, manufacturer detect, app details — used by onboarding.

### Release build
```
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/
```
- Without `android/key.properties` → debug signing → sideload updates break for users.

### Performance
- `main()` parallelizes timezone + prefs + crash logger via `Future.wait`.
- `GoogleFonts.config.allowRuntimeFetching = false` at boot.

---

## Known Mistakes & Doc Drift (Review Checklist)

| Issue | Detail |
|---|---|
| Flutter overlay drag | Do not re-add — failed 30+ times; use native drag + local Java patch |
| Full-screen overlay for pill | Replaced by 720×300 px window; only pill blocks touches |
| Gist commit hash in app URL | Breaks all future OTA checks; use `/raw/update.json` |
| Semver string compare | Wrong for `1.0.10` vs `1.0.9`; use numeric `_isNewerVersion` |
| pubspec / Gist / GitHub mismatch | False update prompt or 404 download |
| Wrong timezone | Production uses **Europe/Warsaw**, not Turkey UTC+3 |
| Dead dependency | `flutter_timezone` unused in `lib/` |
| Test vs prod TZ | `logic_test.dart` uses `DateTime`; app uses `tz.TZDateTime` |
| Manifest `overlayTitle` | Runtime `showOverlay()` only — not AndroidManifest |
| Overlay prefs sync | Both isolates must `prefs.reload()` |
| Old Gist ID | Was `18e57daf4ea79b2cbf88a7b0d836f11f`; now `5215af1f8d82dfeecab20e03eb8d76e1` |
| Secrets in Dart source | Use `.env` + `envied`; commit `.env.example`, not `.env` or `lib/env.g.dart` |

When adding features, update this file in the same session.

---

## APK Signature Verification (2026-05-24)

### Audit (pre-implementation)
- `PackageInfo.buildSignature` was **not** used anywhere before this feature.
- No existing signature / integrity check in `lib/`.
- `package_info_plus` already imported in `home_screen.dart`; used for `_versionLabel` and OTA.
- Injection point: `_init()` immediately after `await infoFuture`, **before** `_loadAndCheckReset()` and `_checkForUpdate()`.

### Implementation
- `_kExpectedSig` removed — use `Env.appSignature` from `lib/env.dart`.
- `_getActualSignature()` — debug only; shows `SIG: …` under version footer (`SelectableText`).
- `_verifySignature()` — release only (`kReleaseMode`); skips if `Env.appSignature` empty or `PLACEHOLDER`.

### What `buildSignature` actually is (Android)
- **NOT** the same as `keytool -printcert` **SHA1** fingerprint.
- `package_info_plus` ≥ v6: SHA-256 of the **signing certificate DER bytes**, formatted as **uppercase hex without colons** (see plugin `PackageInfoPlugin.kt` → `signatureToSha256`).
- Should match `keytool -list -v -keystore … -alias anti-eres` → **Certificate SHA-256** (after removing colons and uppercasing).
- Debug build uses a **different cert** — always capture hash from a **release-signed** APK on device, or from production keystore via keytool.

### Obtain hash (workflow)
1. `flutter run --release` (or install release APK signed with production keystore) on a device.
2. For first setup with `PLACEHOLDER`: temporarily use debug build → copy `SIG:` from home screen footer.
3. **Production:** build release with `key.properties` + keystore `anti-eres` / alias `anti-eres`, install, copy `SIG:` line — OR run:
   ```
   keytool -list -v -keystore <path-to-keystore> -alias anti-eres
   ```
   Copy **SHA256** certificate fingerprint → remove colons → uppercase → paste into `_kExpectedSig`.
4. Replace `PLACEHOLDER` in `.env` → `APP_SIGNATURE=...` (not in Dart source).
5. Rebuild release APK, install, confirm no tamper dialog; footer has no `SIG:` line in release.

### Package ID
- `com.antieres.app` (`android/app/build.gradle.kts`). Crash log path uses this applicationId.

### Secret storage (`envied` — 2026-05-24)
- **Do not** hardcode `_kExpectedSig` or Gist URL in `home_screen.dart`.
- Secrets live in `.env` (gitignored) → `lib/env.dart` + generated `lib/env.g.dart` (gitignored).
- Fields: `Env.appSignature`, `Env.gistUrl` — both `obfuscate: true` (XOR int arrays in `env.g.dart`, not plain strings).
- Template for new clones: copy `.env.example` → `.env`, fill values, run build_runner.
- Regenerate after any `.env` change:
  ```
  dart run build_runner build --delete-conflicting-outputs
  ```
- **Limitation:** obfuscation ≠ encryption; determined reverse engineer can still recover at runtime. Combine with `--obfuscate` release builds.

---

## Known Limitations

- Tapjacking: small window + `defaultFlag` — acceptable risk (local counters only).
- Foldable screen swap: close/reopen overlay for correct window size.
- Overlay drag slop hard-coded at 20 px in local Java — re-test after plugin upgrade.
- OTA: arm64 split APK only (`app-arm64-v8a-release.apk`); S24 Ultra target.
- GitHub `/releases/latest/` requires at least one **published** release with correctly named asset.
