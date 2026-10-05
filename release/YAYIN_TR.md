# RateHelper — Sürüm yayınlama rehberi (TR)

Her yeni APK çıktığında **dört yer aynı sürümü** göstermeli. Biri kayarsa sürücü ya sürekli “güncelleme var” görür ya da indirme 404 verir.

| Kaynak | Ne yazılır | Örnek (v5.0.2) |
|--------|------------|----------------|
| `pubspec.yaml` | `SÜRÜM+BUILD` | `5.0.2+7` |
| GitHub Release | Tag + APK dosya adı | `v5.0.2` → `app-arm64-v8a-release.apk` |
| Gist `update.json` | `latest`, `build`, `apk_url` | `"5.0.2"`, `7`, URL’de `v5.0.2` |
| Telefonda footer | Otomatik (`PackageInfo`) | `v5.0.2` |

**Kural:** Gist’teki `"latest"` ile `apk_url` içindeki release tag **aynı sürüm** olmalı. `latest: 5.0.2` + `v5.0.1` APK = kurulumdan sonra sonsuz güncelleme döngüsü.

**Build numarası:** `+` sonrası (ör. `7`). Gist `"build": 7`. **Arm64 `versionCode` değil** (`2007` = `2×1000+7`; uygulama `% 1000` ile karşılaştırır). Pubspec build **1000’den küçük** kalsın.

---

## Adım 1 — Sürüm numarasını artır

1. `pubspec.yaml` → `version: X.Y.Z+BUILD` (patch artışı: `5.0.2`; her yayında build +1).
2. `release/update.json` → `latest`, `build`, `apk_url`, kısa `notes_tr` / `notes_pl` / `notes_en`.
3. `release/RELEASE_NOTES_vX.Y.Z_TR.md` (ve isteğe bağlı `_PL.md`) — sürücüye görünen maddeler.
4. `README.md` satır “Wersja bieżąca” + `agent-learnings.md` üstteki **Current app version** satırı.

Detaylı teknik özet: [`CHANGELOG_v5.0.2.md`](CHANGELOG_v5.0.2.md) (şablon olarak kopyalanabilir).

---

## Adım 2 — Release APK derle

PowerShell, proje kökünde:

```powershell
flutter clean
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/
```

- **Hedef cihaz (S24 Ultra):** `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk` (~21 MB).
- **`symbols/`** klasörünü bu build için sakla (`flutter symbolize` için).
- **`key.properties`** olmadan imza debug olur; sürücüler üzerine OTA kuramaz.

---

## Adım 3 — GitHub Release

1. https://github.com/emiroys/ratehelper/releases → **Draft a new release**
2. **Tag:** `v5.0.2` (pubspec’teki sürümle aynı)
3. **Title:** `RateHelper v5.0.2`
4. **Açıklama:** `release/RELEASE_NOTES_v5.0.2_TR.md` veya `_PL.md` içeriği
5. **Publish** (taslak URL indirmez)
6. Asset adı **tam olarak:** `app-arm64-v8a-release.apk`

Doğrula:

```
https://github.com/emiroys/ratehelper/releases/download/v5.0.2/app-arm64-v8a-release.apk
```

---

## Adım 4 — Gist manifest

1. Repodaki [`release/update.json`](update.json) ile Gist’teki `update.json` **birebir** hizala.
2. `apk_url` yukarıdaki GitHub linki olmalı.
3. Gist düzenlemesinden sonra CDN ~5 dk gecikebilir; v5+ istemci cache-bust kullanır.

OTA mantığı: `lib/services/update_service.dart` → Gist (`Env.gistUrl`), yedek GitHub Releases API.

---

## Adım 5 — Smoke test (telefonda)

1. Bir önceki APK ile aç → güncelleme diyaloğu veya **Ayarlar → Güncellemeleri denetle**
2. Uygulama içi indirme → Android kurulum ekranı
3. Footer yeni sürümü gösterir → tekrar denetle → “en güncel sürüm”
4. Baloncuk, sayaç, kazanç ekranı hızlı duman testi

Hata: **Kayıtlar → Çökme kayıtları** → `[UPDATE]` satırları.

---

## İngilizce kontrol listesi

Aynı adımlar, ek tablo ve hata matrisi: [`GITHUB_RELEASE_CHECKLIST.md`](GITHUB_RELEASE_CHECKLIST.md).

---

## v5.0.2’de ne değişti? (kısa)

Sürücü notları: [`RELEASE_NOTES_v5.0.2_TR.md`](RELEASE_NOTES_v5.0.2_TR.md).  
Geliştirici özeti: [`CHANGELOG_v5.0.2.md`](CHANGELOG_v5.0.2.md).  
Tam denetim raporu: [`HEALTH_CHECK_AUDIT.md`](HEALTH_CHECK_AUDIT.md).
