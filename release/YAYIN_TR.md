# RateHelper — Sürüm yayınlama rehberi (TR)

Her yeni APK çıktığında **dört yer aynı sürümü** göstermeli. Biri kayarsa sürücü ya sürekli “güncelleme var” görür ya da indirme 404 verir.

| Kaynak | Ne yazılır | Örnek (v5.0.3) |
|--------|------------|----------------|
| `pubspec.yaml` | `SÜRÜM+BUILD` | `5.0.3+8` |
| GitHub Release | Tag + APK dosya adı | `v5.0.3` → `app-arm64-v8a-release.apk` |
| Gist `update.json` | `latest`, `build`, `apk_url` | `"5.0.3"`, `8`, URL’de `v5.0.3` |
| Telefonda footer | Otomatik (`PackageInfo`) | `v5.0.3` |

**Kural:** Gist’teki `"latest"` ile `apk_url` içindeki release tag **aynı sürüm** olmalı. `latest: 5.0.3` + `v5.0.2` APK = kurulumdan sonra sonsuz güncelleme döngüsü.

**Build numarası:** `+` sonrası (ör. `8`). Gist `"build": 8`. **Arm64 `versionCode` değil** (`2008` = `2×1000+8`; uygulama `% 1000` ile karşılaştırır). Pubspec build **1000’den küçük** kalsın.

---

## Adım 1 — Sürüm numarasını artır

1. `pubspec.yaml` → `version: X.Y.Z+BUILD` (patch artışı: `5.0.3`; her yayında build +1).
2. `release/update.json` → `latest`, `build`, `apk_url`, kısa `notes_tr` / `notes_pl` / `notes_en`.
3. `release/RELEASE_NOTES_vX.Y.Z_TR.md` (ve isteğe bağlı `_PL.md`) — sürücüye görünen maddeler.
4. `README.md` satır “Wersja bieżąca”.

Detaylı teknik özet: [`CHANGELOG_v5.0.3.md`](CHANGELOG_v5.0.3.md) (şablon olarak kopyalanabilir).

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
2. **Tag:** `v5.0.3` (pubspec’teki sürümle aynı)
3. **Title:** `RateHelper v5.0.3`
4. **Açıklama:** `release/RELEASE_NOTES_v5.0.3_TR.md` veya `_PL.md` içeriği
5. **Publish** (taslak URL indirmez)
6. Asset adı **tam olarak:** `app-arm64-v8a-release.apk`

Doğrula:

```
https://github.com/emiroys/ratehelper/releases/download/v5.0.3/app-arm64-v8a-release.apk
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

## v5.0.3 — sürücü özeti

GitHub Release açıklaması için: [`RELEASE_NOTES_v5.0.3_TR.md`](RELEASE_NOTES_v5.0.3_TR.md) (veya `_PL.md`).  
Teknik detay (geliştirici): [`CHANGELOG_v5.0.3.md`](CHANGELOG_v5.0.3.md).
