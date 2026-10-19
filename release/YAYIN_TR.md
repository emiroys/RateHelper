# RateHelper — Sürüm yayınlama rehberi (TR)

> **Bu sürüm:** `v5.1.0` (`5.1.0+10`). Örnekler v5.1.0 içindir; komutlar aynıdır.
> **Altın kural:** APK GitHub Release'de yayınlanıp indirme URL'si doğrulanmadan **canlı Gist manifestini güncelleme**. Hiçbir kullanıcı yeni sürümden bu andan önce haberdar edilmemeli.

Her yeni APK çıktığında **dört yer aynı sürümü** göstermeli. Biri kayarsa sürücü ya sürekli “güncelleme var” görür ya da indirme 404 verir.

| Kaynak | Ne yazılır | v5.1.0 örneği |
|--------|------------|----------------|
| `pubspec.yaml` | `SÜRÜM+BUILD` | `5.1.0+10` |
| GitHub Release | Tag + APK dosya adı | `v5.1.0` → `app-arm64-v8a-release.apk` |
| Gist `update.json` | `latest`, `build`, `apk_url` | `"5.1.0"`, `10`, URL'de `v5.1.0` |
| Telefonda footer | Otomatik (`PackageInfo`) | `v5.1.0` |

**Kural:** Gist'teki `"latest"` ile `apk_url` içindeki release tag **aynı sürüm** olmalı. `latest: 5.1.0` + `v5.0.4` APK = kurulumdan sonra sonsuz güncelleme döngüsü.

**`apk_sha256` isteğe bağlı.** Alan yoksa veya geçersizse uygulama kontrolü atlar ve kuruluma devam eder. Varsa APK baytlarının SHA-256 özeti (küçük harf, 64 hex) olmalı; uyuşmazsa kurulum açılmaz. **v5.1.0 APK'sı derlenmeden bu alana değer yazma.**

**Build numarası:** `+` sonrası (`10`). Gist `"build": 10`. **Arm64 `versionCode` değil** (`2010` = `2×1000+10`; uygulama `% 1000` ile karşılaştırır). Pubspec build **1000'den küçük** kalsın.

---

## Cloudflare Worker dağıtımı (v5.1.0)

`/survey` ve `/survey/summary` canlı Worker'a dağıtılmadan anket yanıtları sunucuya ulaşmaz. Uygulama bu durumda yanıtı cihazda kuyruklar ve anketi tamamlandı işaretler; kullanıcı engellenmez, ancak veri toplanmaz.

1. Cloudflare Dashboard → **Workers & Pages** → `ratehelper-orlen` → **Edit code**.
2. `backend/orlen-worker/dashboard-worker.js` dosyasının **tamamını** yapıştır. Dosyada göreli import yoktur; 30 istasyon gömülüdür.
3. **Binding:** `ORLEN_KV` (mevcut KV namespace) korunmalı.
4. **Secrets (yalnızca isimler; değerleri asla yazdırma veya repoya koyma):**
   - `TELEGRAM_BOT_TOKEN` (mevcut)
   - `TELEGRAM_ADMIN_CHAT_ID` (mevcut)
   - `TELEGRAM_WEBHOOK_SECRET` (mevcut)
   - `SURVEY_ADMIN_TOKEN` (**yeni** — `GET /survey/summary` için; uzun, rastgele bir değer)
5. **Save and Deploy**.
6. **Webhook:** mevcut geçerli webhook secret'ı korunarak `allowed_updates=["callback_query","message"]` ile yeniden kurulmalı. `message` olmadan Telegram `/surveysummary` komutu Worker'a ulaşmaz:
   ```sh
   curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
     -d "url=https://ratehelper-orlen.<sizin>.workers.dev/telegram/webhook" \
     -d "secret_token=<TELEGRAM_WEBHOOK_SECRET>" \
     -d 'allowed_updates=["callback_query","message"]'
   ```
7. **Dağıtım sonrası doğrulama:**
   - `GET /prices` → mevcut fiyatlar gelmeye devam ediyor.
   - `POST /submissions` → Telegram onay mesajı düşüyor; onay sonrası `/prices` güncelleniyor.
   - `POST /bug-report` → test raporu Telegram'a ulaşıyor.
   - `POST /survey` → geçerli gövde `201 {"status":"recorded"}`; aynı kurulum kimliği ikinci kez `200 {"status":"duplicate"}`.
   - `GET /survey/summary` → token'sız `403`; `Authorization: Bearer <SURVEY_ADMIN_TOKEN>` ile sayım/yüzde özeti.
   - Telegram admin sohbetinden `/surveysummary` → toplam yanıt, Yes/Maybe/No yüzdeleri, fiyat ve özellik dağılımı.
8. Eski uygulamalar (`/prices`, `/submissions`, `/bug-report`) etkilenmez; mevcut sözleşmeler korunur.

**Not:** KV nihayetinde tutarlıdır (eventually consistent). Yinelenen gönderim ve IP hız sınırı “en iyi çaba”dır; üretim düzeyinde sert koruma için Cloudflare Dashboard'dan WAF hız sınırı kuralı veya Durable Object gerekir.

---

## Adım 1 — Sürüm numarasını artır

1. `pubspec.yaml` → `version: 5.1.0+10`.
2. [`release/update.json`](update.json) → `latest: "5.1.0"`, `build: 10`, `apk_url` `v5.1.0` tag'ini gösterir; kısa `notes_tr` / `notes_pl` / `notes_en`.
3. `README.md` başlığındaki “Wersja bieżąca” satırı.

## Adım 2 — Release APK derle

PowerShell, proje kökünde:

```powershell
Test-Path dart_defines.json # True olmalı; içeriği yazdırma veya stage etme
flutter clean
dart run build_runner build --delete-conflicting-outputs
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/ --dart-define-from-file=dart_defines.json
```

- `dart_defines.json` içinde **`ORLEN_API_URL`** bulunmalı; yoksa yakıt fiyatları ve fiyat gönderme release'de kapalı kalır.
- **Hedef cihaz (S24 Ultra):** `build\app\outputs\flutter-apk\app-arm64-v8a-release.apk` (~21 MB).
- **`symbols/`** klasörünü bu build için sakla (`flutter symbolize` için).
- **`key.properties`** olmadan imza debug olur; sürücüler üzerine OTA kuramaz.

## Adım 3 — GitHub Release

1. https://github.com/emiroys/ratehelper/releases → **Draft a new release**
2. **Tag:** `v5.1.0` (pubspec'teki sürümle aynı)
3. **Title:** `RateHelper v5.1.0`
4. **Açıklama:** [`release/RELEASE_NOTES_v5.1.0_PL.md`](RELEASE_NOTES_v5.1.0_PL.md) içeriğini kopyala (kısa OTA metni `update.json` içindeki `notes_pl`'dir; ikisi farklı amaçlar içindir).
5. **Publish** (taslak URL indirmez)
6. Asset adı **tam olarak:** `app-arm64-v8a-release.apk`

Doğrula:

```
https://github.com/emiroys/ratehelper/releases/download/v5.1.0/app-arm64-v8a-release.apk
```

`curl -I` → **200** ve `Content-Type: application/vnd.android.package-archive`.

## Adım 4 — Gist manifest (EN SON)

1. Repodaki [`release/update.json`](update.json) ile Gist'teki `update.json` **birebir** hizala.
2. `_local_pending` alanı **yerel şablona** aittir; canlı Gist'e kopyalarken bu bloğu çıkar (uygulama bilinmeyen alanları yok sayar, ama manifest temiz kalsın).
3. `apk_url` yukarıdaki doğrulanmış GitHub linki olmalı.
4. İstersen `apk_sha256` ekle (APK derlendikten sonra hesaplanan küçük harf özet).
5. Gist düzenlemesinden sonra CDN ~5 dk gecikebilir; v5+ istemci cache-bust kullanır.

OTA mantığı: `lib/services/update_service.dart` → Gist (`Env.gistUrl`), yedek GitHub Releases API.

## Adım 5 — Smoke test (telefonda)

1. Bir önceki APK (v5.0.4) ile aç → güncelleme diyaloğu veya **Ayarlar → Güncellemeleri denetle**
2. Uygulama içi indirme → Android kurulum ekranı
3. Footer yeni sürümü gösterir → tekrar denetle → “en güncel sürüm”
4. v5.0.4'ten yükseltme sonrası veri kaybı yok: sayaçlar, haftalık arşiv, kazançlar, ayarlar
5. Beş adımlı kurulum → anket → ana ekran akışı; geri tuşu anketi atlamıyor
6. Baloncuk (%→R küçültme), bildirim paneli kontrolleri, sayaç senkronu
7. Yakıt merkezi: 30 istasyon, yön sıralaması, fişler; fiyat gönderme (varsa)
8. Yedek al → geri yükleme önizlemesi
9. Hata raporu gönder (isteğe bağlı ekran görüntüsü ile)
10. Anketi yanıtla → başarı ekranı → ana ekran; uygulamayı kapatıp açınca anket bir daha çıkmaz

Hata: **Kayıtlar → Çökme kayıtları** → `[UPDATE]` satırları.

---

## v5.1.0 yayın sırası (A–L)

| # | Adım | Not |
|---|------|-----|
| A | Tüm yerel değişiklikleri incele | `git status --short`, `git diff` |
| B | Uzak Git commit'ini güvenli şekilde entegre et | Çalışanı kaybetmeden; gerekirse maintainer yönetir |
| C | Cloudflare Dashboard Worker'ı doğrula ve manuel dağıt | Yukarıdaki Cloudflare bölümü |
| D | `/prices`, `/bug-report`, `/survey`, `/surveysummary` doğrula | Canlıda test yanıtı |
| E | Son kontroller | `flutter analyze`, `flutter test`, `npm test` (Worker) |
| F | v5.1.0 APK'yı derle ve imzala | Adım 2 komutu; maintainer yapar |
| G | İmzalı APK'yı gerçek cihazda test et | v5.0.4'ten veri kaybetmeden yükseltme |
| H | Git değişikliklerini ve secret dışlamayı incele | `dart_defines.json`, `key.properties`, `*.jks`, `.env`, `.dev.vars` **stage edilmemeli** |
| I | Onaylanan kaynak değişikliklerini commit et ve push et | Maintainer onayından sonra |
| J | `v5.1.0` tag'i ve GitHub Release oluştur; doğrulanmış APK'yı yükle | Asset adı `app-arm64-v8a-release.apk` |
| K | Genel APK asset URL'sinin çalıştığını doğrula | `curl -I` → 200 |
| L | Canlı Gist manifestini **en son** güncelle | Bundan önce hiçbir kullanıcı haberdar edilmez |

---

## İngilizce kontrol listesi

Aynı adımlar, ek tablo ve hata matrisi: [`GITHUB_RELEASE_CHECKLIST.md`](GITHUB_RELEASE_CHECKLIST.md).
