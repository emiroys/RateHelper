# GitHub Release Checklist — RateHelper v5 (OTA)

**Türkçe adım adım rehber:** [`YAYIN_TR.md`](YAYIN_TR.md)  
**v5.0.3 teknik özet:** [`CHANGELOG_v5.0.3.md`](CHANGELOG_v5.0.3.md)

Use this every time you ship a new version. Misaligned `pubspec`, Gist, and GitHub Release tag is the #1 cause of false update prompts or silent “already up to date”.

## 1. Bump `pubspec.yaml`

Example:

```yaml
version: 5.0.3+8
```

- Before `+` → Gist `"latest"` (e.g. `"5.0.3"`).
- After `+` → Gist `"build"` (e.g. `8`) — **not** the arm64 `versionCode` (`2008`).

Rebuild after every bump.

## 2. Build the APK

```powershell
flutter clean
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/
```

Output (S24 Ultra / arm64):

```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Archive `symbols/` for this build.

## 3. Create GitHub Release

1. https://github.com/emiroys/ratehelper/releases → **Draft a new release**
2. **Tag:** `v5.0.3` (match semver; `v` prefix OK)
3. **Title:** e.g. `RateHelper v5.0.3`
4. **Description:** copy from [`RELEASE_NOTES_v5.0.3_PL.md`](RELEASE_NOTES_v5.0.3_PL.md) (or TR: [`RELEASE_NOTES_v5.0.3_TR.md`](RELEASE_NOTES_v5.0.3_TR.md))
5. **Status:** **Published** — drafts do not serve download URLs
6. Upload asset named exactly:

| Required filename |
|---|
| `app-arm64-v8a-release.apk` |

Case-sensitive. No zip wrapper.

Verify link shape:

```
https://github.com/emiroys/ratehelper/releases/download/v5.0.3/app-arm64-v8a-release.apk
```

`curl -I` → **200**, `Content-Type: application/vnd.android.package-archive`

## 4. Update Gist `update.json`

Copy from [`release/update.json`](update.json) and adjust:

```json
{
  "latest": "5.0.3",
  "build": 8,
  "apk_url": "https://github.com/emiroys/ratehelper/releases/download/v5.0.3/app-arm64-v8a-release.apk",
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
| **`latest` matches APK being served** | `latest: 5.0.3` + `v5.0.2` APK → infinite update loop |
| Asset name exactly `app-arm64-v8a-release.apk` | Allowlist rejects other names |

**CDN cache:** Gist raw has `max-age=300`. v5 app clients cache-bust automatically. Older APKs may lag up to 5 minutes after Gist edit.

## 5. Smoke-test on device

### A. Already on previous APK (e.g. 5.0.0)

1. Cold start → update dialog (or wait out 12 h cooldown / use manual **Sprawdź aktualizacje**)
2. Grant **Install unknown apps** for RateHelper if prompted
3. Tap update → in-app progress bar → Android installer opens
4. Confirm install → footer shows new version (e.g. `v5.0.3`)
5. Manual check again → **“Masz najnowszą wersję”** / equivalent

### B. Regression checks

| Check | Expected |
|---|---|
| Gist `latest` rolled back to installed version | No update prompt |
| Airplane mode + manual check | Unreachable message (not “up to date”) |
| Second update attempt same session | In-app download works (cache sweep non-fatal) |

### C. If in-app download fails

- **Kayıtlar → Çökme Kayıtları** — look for `[UPDATE]` lines (no secrets logged)
- Browser fallback may still stall at 100% on Chrome/Samsung — fix is OTA path, not browser

## 6. First-time OTA bootstrap

Users on APK **without** OTA code must install **one manual** v5.0.1+ build (Samsung Internet / Files). After that, all future updates can flow through in-app OTA (current line: **v5.0.3+8**).

**Do not** point Gist `apk_url` at an older release while testing a higher `latest` — you will reinstall old code and lose OTA.

## Common failures

| Symptom | Fix |
|---|---|
| Update every launch after “install” | Align Gist `latest` with `apk_url` release version |
| Manual check says up to date but Gist is newer | Manifest unreachable; check `[UPDATE]` log |
| İndir / download 404 | Publish release, correct asset name |
| Chrome 100% stuck | Use in-app OTA (v5+) |
| Signature error on upgrade | Same keystore as previous release; else uninstall + reinstall |

## Related docs

- **Publish (TR):** [`YAYIN_TR.md`](YAYIN_TR.md)
- **Current notes:** [`RELEASE_NOTES_v5.0.3_TR.md`](RELEASE_NOTES_v5.0.3_TR.md) · [`RELEASE_NOTES_v5.0.3_PL.md`](RELEASE_NOTES_v5.0.3_PL.md) · [`RELEASE_NOTES_v5.0.3_EN.md`](RELEASE_NOTES_v5.0.3_EN.md)
- **Changelog:** [`CHANGELOG_v5.0.3.md`](CHANGELOG_v5.0.3.md)
- Legacy v5.0.1 notes: [`RELEASE_NOTES_v5_PL.md`](RELEASE_NOTES_v5_PL.md)
- Architecture: [`../README.md`](../README.md) §7 OTA flow
