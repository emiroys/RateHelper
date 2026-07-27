# RateHelper — Kurulum ve Kullanım Rehberi

Bu rehber, RateHelper’i telefonuna kurduktan sonra **doğru çalışması için gereken izinleri** ve **günlük kullanımı** adım adım anlatır.

> **Hedef cihaz:** Android (Samsung Galaxy S24 Ultra ve benzeri flagship’ler için optimize edilmiştir)  
> **Tahmini kurulum süresi:** 2–3 dakika

---

## 1) APK’yı yükle

1. Sana gönderilen APK dosyasını telefona kopyala (WhatsApp, USB, e-posta — fark etmez).  
   Dosya adı genelde `app-arm64-v8a-release.apk` veya `ratehelper.apk` olur.
2. Dosyaya dokun. Telefon **“Bilinmeyen kaynaklardan yükleme”** izni isterse → **İzin Ver** → tekrar APK’ya dön → **Yükle**.
3. İlk açılışta uygulama seni otomatik olarak **RateHelper Kurulumu** ekranına götürür.

> Kurulum ekranını daha sonra tekrar okumak için: ana ekranda sağ üst **⋮ menü** → **Kurulum Rehberi**.

---

## 2) İlk kurulum — iki zorunlu izin

RateHelper’in Uber Driver’ın üstünde çalışabilmesi ve vardiya boyunca arka planda öldürülmemesi için **iki Android izni** şarttır.

### Adım 1 — Üzerine çizim izni

Kurulum ekranında **“İZNİ AÇ”** butonuna bas. Android ayarları açılır.

1. Listede **RateHelper** uygulamasını bul.
2. Anahtarı **AÇIK** konuma getir.
3. Geri tuşu ile RateHelper’e dön.

Adım kartında yeşil **VERİLDİ** göründüyse tamam.

### Adım 2 — Pil optimizasyonunu kapat

Telefon markana göre pil ayarını aç. Kurulum ekranındaki marka seçiciden doğru markayı seç, ardından **“AYARLARI AÇ”** butonuna bas.

#### Samsung (One UI)

`Ayarlar` → `Cihaz bakımı` → `Pil` → `Arka plan kullanım sınırları` → `Asla uyutulmayacak uygulamalar` → **+** → **RateHelper**’i ekle.

#### Xiaomi / Redmi / POCO (MIUI / HyperOS)

İkisini de yap:

1. `Ayarlar` → `Uygulamalar` → `RateHelper` → `Pil tasarrufu` → **Kısıtlama yok**
2. Aynı sayfada `Otomatik başlatma` → **AÇIK**

#### Huawei / Honor (EMUI)

`Ayarlar` → `Uygulamalar` → `RateHelper` → `Pil` → `Uygulama başlatma` → **Otomatik yönet** seçeneğini **KAPAT** → açılan üç anahtarın (`Otomatik başlat`, `İkincil başlatma`, `Arka planda çalışma`) **hepsini AÇ**.

#### OnePlus / Oppo / Realme (OxygenOS / ColorOS)

`Ayarlar` → `Pil` → `Pil optimizasyonu` → **RateHelper** → **Optimize etme**.

**Ek:** Son uygulamalar (Recents) ekranında RateHelper kartının üstündeki **kilit** ikonuna dokun — temizlemede silinmesin.

#### Diğer markalar

`Ayarlar` → `Pil` veya `Uygulamalar` altında **RateHelper**’i bul; pil optimizasyonunu **KAPAT** veya **“Kısıtlanmamış”** olarak işaretle.

### Kurulumu bitir

Her iki adım tamamsa alttaki **BİTİR** butonuna bas. Ana ekrana geçersin.

---

## 3) Ana ekran — sayaçlar

Ana ekranda dört büyük sayaç vardır:

| Sayaç | Anlamı |
| --- | --- |
| **Kabul Edilen** | Kabul ettiğin yolculuk istekleri |
| **Reddedilen** | Reddettiğin istekler |
| **Tamamlanan** | Bitirdiğin yolculuklar |
| **İptal Edilen** | İptal edilen yolculuklar |

**Kabul oranı** ve **iptal oranı** otomatik hesaplanır. Oran hedefinin altına düşersen ekranda turuncu/kırmızı uyarı ve **kaç kabul gerektiği** gösterilir.

### Sayaç düzenleme

Yanlış sayı mı girdin? Sayaç değerine **dokun** veya **uzun bas** → açılan kutuya doğru sayıyı yaz → **KAYDET**.

### Otomatik tamamla

**“Otomatik tamamla”** anahtarını açarsan, kabul sayısına her **+1** eklediğinde tamamlanan yolculuk sayısı da otomatik artar.

### Haftayı sıfırla

Hafta bittiğinde **HAFTAYI SIFIRLA** butonuna bas. Sayacı sıfırlamadan önce o haftanın özeti arşive kaydedilir.

---

## 4) Yüzen widget (Uber üstünde sayaç)

Vardiyadayken Uber’i kapatmadan sayaç tutmak için küçük bir **yüzen pill** kullanılır.

### Widget’ı aç / kapat

Ekranın altındaki menüde ortadaki büyük butona bas:

- **▶ Başlat** → widget açılır, Uber’in üstünde görünür
- **⏹ Durdur** → widget kapanır

### Widget kullanımı

| Buton | İşlev |
| --- | --- |
| **Yeşil ➕** | Kabul edilen istek (+1) |
| **Kırmızı ➖** | Reddedilen istek (+1) |
| **Ortadaki %** | Anlık kabul oranın |

Widget’ı **sürükleyerek** ekranda istediğin yere taşıyabilirsin. Uber’in dokunmatik alanlarını kapatmaması için küçük tutulmuştur (276×80 dp).

> Widget kapalıyken sayaç tutmak için ana ekrana dönüp büyük **+ / −** butonlarını kullan.

---

## 5) Alt menü (5 buton)

| Simge | Ad | Ne işe yarar? |
| --- | --- | --- |
| 🌐 | **Dil** | Türkçe / İngilizce / Lehçe seç |
| ▶/⏹ | **Başlat / Durdur** | Yüzen widget’ı aç veya kapat |
| 📋 | **Kayıtlar** | Dokunma geçmişi + haftalık arşiv |
| 📡 | **Radar** | Kraków’da yaklaşan etkinlikler (talep yoğunluğu) |
| 💰 | **Kazanç** | Haftalık gelir, gider ve kâr takibi |

---

## 6) Kayıtlar ekranı

**Kayıtlar** butonuna basınca alttan açılan panelde **iki sekme** vardır:

### Dokunma geçmişi

Her **+ / −** basımının saati listelenir. **Bugün** / **Tümü** filtresi vardır. Temizlemek için sağ üstteki silme ikonunu kullan.

### Haftalık arşiv

Her **HAFTAYI SIFIRLA** işleminde o haftanın kabul/iptal oranları buraya kaydedilir. Eski kayıtlar da okunabilir.

---

## 7) Kazanç takibi (💰)

**Kazanç** ekranı haftalık Uber gelirini, yakıt, kira, vergi ve net kârını hesaplar. Tüm veriler **telefonda kalır** — buluta gönderilmez.

### İlk açılış

1. **Tek Sürücü** mi yoksa **İki Sürücü (Paylaşımlı)** mı kullandığını seç — kira tabloları buna göre değişir.
2. Haftalık formu doldur: **Net Gelir**, **Alınan Nakit**, **Çevrimiçi Süre**, **Yolculuk Sayısı**, yakıt fişleri vb.

### Görünümler

Üstte **Haftalık / Aylık / Yıllık** seçici vardır. Aylık görünümde en iyi hafta kartı ve grafikler gösterilir.

### PDF dışa aktarma

Sağ üstteki paylaş ikonundan **PDF Olarak Dışa Aktar** → tarih aralığı seç → muhasebecine veya kendine gönder.

### Ücretsiz kira haftası sayacı

2000 yolculuğa ulaştığında kira indirimi hakkı kazanırsın. Bu sayaç **asla geriye gitmez** — eski haftalar silinse bile.

---

## 8) Etkinlik Radarı (📡)

Kraków’da konser, maç ve büyük etkinlikleri listeler. Yoğun talep (surge) beklentisi olan günleri önceden görmen için.

- Liste **internetten** güncellenir (yalnızca public etkinlik verisi; finansal verin gönderilmez).
- Aşağı çekerek **Yenile** yapabilirsin.
- Veri bir saat boyunca önbellekte tutulur.

---

## 9) Direksiyon tuşu ile sayma (isteğe bağlı, Beta)

Ellerini direksiyondan ayırmadan sayaç tutmak istersen:

1. Ana ekranda **“Direksiyon Tuşu ile Sayma (Beta)”** anahtarını **AÇ**.
2. **Erişilebilirlik izni** istenirse → **AYARLARA GİT** → RateHelper servisini **AÇ**.
3. Kullanım:
   - **Sonraki şarkı / oynat-dur** tuşuna **800 ms basılı tut** → kabul sayacı +1
   - **Önceki şarkı** tuşuna **800 ms basılı tut** → red sayacı +1
   - **Kısa basış** → müzik uygulaman (Spotify vb.) normal çalışmaya devam eder

> Bu özellik Android **Erişilebilirlik** servisi kullanır. İstemezsen anahtarı kapalı bırak — uygulamanın geri kalanı normal çalışır.

---

## 10) Sürücü modu değiştirme

Araba paylaşımlı mı kullanıyorsun?

Ana ekranda sağ üst **⋮ menü** → **Tek Sürücü** veya **İki Sürücü (Paylaşımlı)** seç.

> Geçmiş haftaların kayıtlı modu değişmez; yalnızca yeni kayıtlar yeni moda göre hesaplanır.

---

## 11) Sorun çıkarsa

### Uygulama kapanıyor veya widget kayboluyor

1. **Kurulum Rehberi**’ni tekrar oku (⋮ menü) — pil optimizasyonu ve overlay izni hâlâ açık mı kontrol et.
2. Widget’ı **Durdur** → tekrar **Başlat**.
3. Samsung’da Recents’te RateHelper kartını **kilitle**.

### Çökme kaydı gönderme

1. Ana ekranda sağ üst **⋮ menü** → **Çökme Kayıtları**
2. **KOPYALA** butonuna bas
3. Yapıştırdığını WhatsApp üzerinden geliştiriciye gönder

> Çökme kayıtları uygulamanın **dahili** (sandbox) alanında tutulur. Dosya yöneticisiyle erişilemez — yalnızca uygulama içindeki **KOPYALA** yolunu kullan.

### Güncelleme (OTA)

Uygulama yeni sürüm olduğunda alttan bildirim çıkar. **İndir** dediğinde GitHub’dan APK iner. Aynı imzayla yüklenmiş olması gerekir — resmi APK dışında kaynak kullanma.

---

## 12) Geliştirici notları (sadece kurucu / maintainer)

Üretim derlemesi:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/
```

- `--obfuscate` → Dart AOT sembollerini siler.
- `--split-debug-info` → sembolleri proje dışında tutar (geri izleme için sakla).
- `--split-per-abi` → APK boyutunu ~8 MB / mimari seviyesine düşürür.

`android/key.properties` mevcutsa imzalama otomatiktir. Yoksa debug anahtarı kullanılır ve kullanıcı **güncelleme yükleyemez** (imza uyuşmazlığı). Her sürümde aynı keystore kullan.

Detaylı mimari: [`README.md`](README.md) · Agent notları: [`agent-learnings.md`](agent-learnings.md)

---

> **RateHelper** — Sürücü koltuğundan yazıldı, Kraków yollarında gerçek kazancın için.
