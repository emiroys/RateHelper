# RateHelper v5.0.4 — maintainer changelog

**Version:** `5.0.4+9` (arm64 `versionCode` 2009)  
**Driver notes:** `release/RELEASE_NOTES_v5.0.4_{TR,PL,EN}.md`  
**OTA one-liners:** `release/update.json` → `notes_*`

---

## Settings screen (`lib/settings_screen.dart`)

- Home: removed inline `AYARLAR` block and AppBar **⋮** menu; gear pushes `SettingsScreen` with `SettingsBindings` / `SettingsSnapshot`.
- Sections: driving & counters, overlay pill, app preferences, system & support. Pref keys and handlers unchanged; `OverlaySync.notifySettingsChanged()` on relevant toggles.
- `UpdateCheckTile` only on Settings (removed home footer tile and menu row).
- Setup guide entry moved to Settings → `SetupGuideScreen` (overlay + battery only).

## Weekly archive v2 (`lib/models/weekly_archive_entry.dart`, `lib/weekly_archive_card.dart`)

- Reset stores `goalTier`, `targetAcceptRate`, `maxCancelRate`, `canceledTrips` on v2 JSON.
- `collapseWeeklyArchive` on reset and when Logs opens; duplicate week-start merges counts; legacy string rows fold into structured entries.
- `WeeklyArchiveCard`: `AnimatedSize` expand/collapse; goal met/missed from week thresholds (not hardcoded 80%).

## Overlay collapse → R bubble (`lib/overlay_widget.dart`, fork `resizeOverlay`)

- Tap **%** → 48 dp **R** bubble; pref `overlay_pill_collapsed`; native window resize from overlay isolate only (fixed top-left, screen clamp, optional `enableDrag`).
- Expand/collapse ordering avoids RenderFlex overflow and touch-blocking transparent window.
- Tests: `test/overlay_widget_test.dart`.

## GitHub access opt-in (`lib/github_consent_dialog.dart`, `lib/services/github_access.dart`, `lib/services/github_http.dart`)

- Defaults: `github_auto_update` and `github_auto_events` off; one-time `GithubConsentDialog`; events/update cache behavior documented in `agent-learnings.md`.

## Overlay ↔ home live counters

- `WindowSetup.suppressMessengerClaim` so pill `shareData` reaches main isolate; `OverlaySync.pingCountersChanged` + `OverlayCounterBurst` on home.

## Overlay IPC validation (`lib/overlay_sync.dart`)

- `OverlaySync.deliver()` strict parsing; tests in `test/overlay_sync_test.dart`.

## Security / OTA (2026-10-14 carry-in)

- Release signing required in `build.gradle.kts`; APK install gate in Kotlin + `UpdateService`; optional manifest `apk_sha256`; removed `secure_http.dart`.

## Hygiene

- Removed `.github/workflows/update_events.yml` (missing scraper; events ship as `krakow_events.json`).
- Plate badge **KK383CT** on home footer.

## Tests

- `flutter test` → **344** passing (2026-10-15).

## Release alignment

`pubspec.yaml` · `release/update.json` · GitHub `v5.0.4` · Gist — [`YAYIN_TR.md`](YAYIN_TR.md).
