# GitHub Release Checklist — RateHelper APK Update

Use this every time you ship a new version. A 404 on **İndir** means one of these steps was skipped or mismatched.

## 1. Build the APK

```powershell
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/
```

Output file (S24 Ultra / arm64):

```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## 2. Bump version in `pubspec.yaml`

Example: `version: 1.0.2+2` → app reports **1.0.2** via `PackageInfo.fromPlatform().version`.

Rebuild after bumping so the APK embeds the new version.

## 3. Create or edit the GitHub Release

1. Open https://github.com/emiroys/ratehelper/releases
2. **Draft a new release** (or edit the latest published release).
3. **Tag:** `v1.0.2` (must match semver; `v` prefix is OK on GitHub).
4. **Title:** e.g. `RateHelper 1.0.2`
5. **Status:** must be **Published** — drafts do not serve `/releases/latest/download/...`.

## 4. Upload asset — filename must match EXACTLY

| Required | Value |
|---|---|
| Asset filename | `app-arm64-v8a-release.apk` |
| Case-sensitive | Yes — `App-arm64...` or `app-arm64-v8a-release.APK` will 404 |

**How to verify on the release page:**

1. Scroll to **Assets**.
2. Confirm a row named exactly `app-arm64-v8a-release.apk` (not renamed, not inside a zip).
3. Right-click → Copy link. It should look like:
   `https://github.com/emiroys/ratehelper/releases/download/v1.0.2/app-arm64-v8a-release.apk`

## 5. Test the canonical download URL

Open in browser (or `curl -I`):

```
https://github.com/emiroys/ratehelper/releases/latest/download/app-arm64-v8a-release.apk
```

- **200** + `Content-Type: application/vnd.android.package-archive` → OK
- **404** → no published release, wrong asset name, or asset missing

`/latest/download/` always resolves to the **latest published** release’s asset with that exact name.

## 6. Update Gist `update.json`

Copy contents from `release/update.json` in this repo to the Gist:

```json
{
  "latest": "1.0.2",
  "apk_url": "https://github.com/emiroys/ratehelper/releases/latest/download/app-arm64-v8a-release.apk"
}
```

Rules:

- `"latest"` must match `pubspec.yaml` version (before `+`).
- `"apk_url"` must use `/releases/latest/download/app-arm64-v8a-release.apk` — do not use tag-specific URLs unless you also change app validation.
- After editing the Gist, wait for raw URL cache or bump the Gist revision if needed.

## 7. Smoke-test on device

1. Install the **previous** APK (e.g. 1.0.1).
2. Cold-start app → should show update snackbar for 1.0.2.
3. Tap **İndir** → browser downloads APK (no 404).
4. Install **1.0.2** → cold-start again → **no** update snackbar.

## Common 404 causes

| Symptom | Fix |
|---|---|
| Release is draft | Click **Publish release** |
| Asset named `ratehelper.apk` or `app-release.apk` | Re-upload as `app-arm64-v8a-release.apk` |
| Only universal APK uploaded | Upload the arm64 split from `--split-per-abi` |
| Tag `1.0.2` but URL uses `/download/v1.0.1/` | Use `/releases/latest/download/...` or match tag to release |
| Gist `latest` > installed version but no release yet | Publish release **before** updating Gist |
