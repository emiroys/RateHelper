# RateHelper — Kurulum Rehberi

Bu kısa rehber, telefonuna RateHelper APK’sını yüklediğinde **iki Android iznini** açmana yardım eder. Bunlar olmadan uygulama Uber Driver’ın üstünde **görünmez** veya vardiya sırasında **arka planda öldürülür**.

> Tahmini süre: 60 saniye.

---

## 1) APK’yı yükle

1. Sana gönderilen `ratehelper.apk` dosyasını telefonuna kopyala (WhatsApp, USB, e-posta — fark etmez).
2. Dosyaya dokun. Telefon "Bilinmeyen kaynaklardan yükleme" izni isteyecektir → **İzin Ver** → tekrar APK’ya dön → **Yükle**.
3. İlk açılışta uygulama seni otomatik olarak **Kurulum** ekranına götürür.

---

## 2) Adım 1 — "Diğer uygulamaların üzerine çizim" izni

Kurulum ekranında **"İZNİ AÇ"** butonuna bas. Android’in sistem ayarları açılır.

- Listede **RateHelper** uygulamasını bul.
- Yanındaki anahtarı **AÇIK** konuma getir.
- Geri tuşu ile RateHelper’e dön.

Adım kartında yeşil bir ✓ göründüyse bu adımı tamamladın.

---

## 3) Adım 2 — Pil optimizasyonunu kapat

Bu adım telefonun markasına göre değişir. Doğru markayı seç, ardından uygulama içindeki **"AYARLARI AÇ"** butonuna bas.

### Samsung (One UI)

`Ayarlar` → `Cihaz bakımı` → `Pil` → `Arka plan kullanım sınırları` → `Asla uyutulmayacak uygulamalar` → **+** → listeden **RateHelper**’i seç.

### Xiaomi / Redmi / POCO (MIUI / HyperOS)

İki yer var, ikisini de yap:

1. `Ayarlar` → `Uygulamalar` → `RateHelper` → `Pil tasarrufu` → **Kısıtlama yok**.
2. Aynı sayfada `Otomatik başlatma` → **AÇIK**.

### Huawei / Honor (EMUI)

`Ayarlar` → `Uygulamalar` → `RateHelper` → `Pil` → `Uygulama başlatma` → **Otomatik yönet** seçeneğini KAPAT → ardından açılan üç anahtarı (`Otomatik başlat`, `İkincil başlatma`, `Arka planda çalışma`) hepsini **AÇ**.

### OnePlus / Oppo / Realme (OxygenOS / ColorOS)

`Ayarlar` → `Pil` → `Pil optimizasyonu` → **RateHelper** → **Optimize etme**.

Bonus: Son uygulamalar (Recents) ekranını aç, RateHelper kartının üst kısmındaki kilit ikonuna dokun. Bu kart artık temizlemede silinmeyecek.

### Diğer markalar

Telefonun `Ayarlar` → `Pil` veya `Uygulamalar` altında **RateHelper**’i ara, pil optimizasyonunu **KAPAT** veya **"Kısıtlanmamış"** olarak işaretle.

---

## 4) "BİTİR" → RateHelper’i başlat

1. Ana ekrandaki üst-sağ köşedeki **Picture-in-picture** ikonuna bas: ekrana siyah/yuvarlak butonlar gelecek.
2. **Yeşil ➕** = Kabul edilen yolculuk. **Kırmızı ➖** = Reddedilen istek.
3. Butonların ortasındaki tutamağı sürükleyerek pil hücresini taşıyabilirsin.

---

## 5) Sorun çıkarsa

Uygulama beklenmedik şekilde kapanırsa:

1. RateHelper’i tekrar aç.
2. Sağ üstteki üç-nokta menü → **Çökme Kayıtları**.
3. **KOPYALA** butonuna bas. Yapıştırdığını WhatsApp üzerinden bana gönder.

Çökme kayıtları uygulamanın **dahili** (sandbox) depolama alanında tutulur; dosya yöneticisi veya dış depolama yolundan erişilemez. Kayıtları okumak ve paylaşmak için yalnızca uygulama içindeki **Çökme Kayıtları → KOPYALA** akışını kullan.

---

## 6) Geliştirici notları (sadece kurucu için)

Üretim derlemesi:

```bash
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/
```

- `--obfuscate` → Dart AOT sembollerini siler.
- `--split-debug-info` → orijinal sembolleri proje dışında tutar (geri tracing için sakla).
- `--split-per-abi` → APK boyutunu ~8 MB / mimari seviyesine düşürür.

`android/key.properties` mevcutsa imzalama otomatiktir. Yoksa debug anahtarı kullanılır ve **kullanıcı güncelleyemez** (Android imza eşleşmezliği reddeder). Aynı anahtarı her sürümde yeniden kullan.
