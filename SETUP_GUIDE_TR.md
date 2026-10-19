# RateHelper — Kurulum ve Kullanım Rehberi

Bu rehber, RateHelper’i telefonuna kurduktan sonra **doğru çalışması için gereken izinleri** ve **günlük kullanımı** adım adım anlatır.

> **Hedef cihaz:** Android (Samsung Galaxy S24 Ultra ve benzeri flagship’ler için optimize edilmiştir)  
> **Tahmini kurulum süresi:** 2–3 dakika  
> **Lehçe sürüm:** [`SETUP_GUIDE_PL.md`](SETUP_GUIDE_PL.md)

> **Uygulama içi “Kurulum Rehberi”** (**Ayarlar** → dişli ikonu) yalnızca **iki izin adımını** (overlay + pil) gösterir. Bu dosya **tam kullanım kılavuzudur**.

---

## 1) APK’yı yükle

1. Sana gönderilen APK dosyasını telefona kopyala (WhatsApp, USB, e-posta — fark etmez).  
   Dosya adı genelde `app-arm64-v8a-release.apk` veya `ratehelper.apk` olur.
2. Dosyaya dokun. Telefon **“Bilinmeyen kaynaklardan yükleme”** izni isterse → **İzin Ver** → tekrar APK’ya dön → **Yükle**.
3. İlk açılışta uygulama seni otomatik olarak **RateHelper Kurulumu** ekranına götürür.
4. Kurulum bittikten sonra (veya bu sürüme ilk kez güncellediğinde) **bir kez** sorulur: GitHub üzerinden otomatik güncelleme ve Kraków etkinlikleri çekilsin mi? İstemezsen **Hayır** de — verilerin yine telefonda kalır; istersen sonra **Ayarlar**’dan açarsın.

> Kurulum ekranını tekrar okumak için: ana ekran → sağ üst **dişli (Ayarlar)** → **Kurulum Rehberi**.

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

Sağ üstteki **dişli** ikonu **Ayarlar** ekranını açar (sürüş modu, baloncuk, dil, GitHub, güncelleme, çökme kayıtları). Haftalık hedef çipi, sayaçlar, **HAFTAYI SIFIRLA**, alttaki **KK383CT** rozeti ve sürüm satırı ana ekranda kalır.

Ana ekranda dört büyük sayaç vardır:

| Sayaç | Anlamı |
| --- | --- |
| **Kabul Edilen** | Kabul ettiğin yolculuk istekleri |
| **Reddedilen** | Reddettiğin istekler |
| **Tamamlanan** | Bitirdiğin yolculuklar |
| **İptal Edilen** | İptal edilen yolculuklar |

**Kabul oranı** ve **iptal oranı** otomatik hesaplanır.

### Renkli uyarılar (3 durum)

Kabul oranı kartının rengi seçtiğin **Haftalık Yolculuk Hedefi**’ne göre değişir:

| Renk | Anlamı |
| --- | --- |
| **Yeşil** | Hedef oranın üstündesin |
| **Turuncu** | Güvende ama sınırda — birkaç ret üst üste gelirse kademeyi kaybedebilirsin |
| **Kırmızı** | Hedefin altındasın — ekranda **kaç kabul gerektiği** yazılır |

### Haftalık yolculuk hedefi

Üstteki hedef çipine dokun → **Haftalık Yolculuk Hedefi** seç. Her kademe, ERES kira indirimi için gereken minimum yolculuk sayısı ve kabul oranını temsil eder (ör. 100–149 yolculuk, min. %80 kabul). **Gereksinim Yok** seçeneği yalnızca sayaç tutmak içindir.

> Hedef, **Tek / İki / Üç Sürücü** moduna göre farklı eşikler kullanır (**Ayarlar → Sürüş modu**).

### İptal hakkı kartı

Hedef seçiliyken (Gereksinim Yok hariç) ekranda **%5 iptal sınırına** kadar kaç iptal daha yapabileceğin gösterilir. Sınır aşıldıysa kırmızı uyarı çıkar.

### Geri al (undo)

Sol üstteki **↩ geri** ikonu son sayaç değişikliğini **bir adım** geri alır.

### Sayaç düzenleme

Yanlış sayı mı girdin? Sayaç değerine **dokun** veya **uzun bas** → açılan kutuya doğru sayıyı yaz → **KAYDET**.

### Otomatik tamamla

**Ayarlar → Otomatik tamamla** açıksa, kabul sayısına her **+1** eklediğinde tamamlanan yolculuk sayısı da otomatik artar.

### Haftayı sıfırla

Hafta bittiğinde **HAFTAYI SIFIRLA** butonuna bas. Sayacı sıfırlamadan önce o haftanın özeti arşive kaydedilir.

> Otomatik haftalık sıfırlama sınırı: **Pazartesi 04:00** (Varşova saati). Cihazın saat dilimi fark etmez — uygulama `Europe/Warsaw` kullanır.

---

## 3b) Ayarlar ekranı (dişli)

Ana ekran → sağ üst **dişli**. Bölümler:

| Bölüm | Ne var? |
| --- | --- |
| **Sürüş ve sayaçlar** | **Sürüş modu** (Tek / İki / Üç sürücü), **Otomatik tamamla**, **Direksiyon tuşu (Beta)**, **Ekranı açık tut** |
| **Baloncuk** | **Baloncuk yönü** (Yatay / Dikey), **Baloncukta iptal düğmesi** (isteğe bağlı), **Bildirim kontrolleri** (isteğe bağlı) |
| **Tercihler** | **Dil**, **Otomatik güncelleme denetimi**, **Etkinlikleri otomatik getir** |
| **Sistem ve destek** | **Güncellemeleri denetle** (son kontrol saati + sürüm), **Kurulum Rehberi**, **Çökme Kayıtları** |

> Dil de alt menüdeki 🌐 ile değişir; ikisi aynı ayarı kullanır.

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
| **Ortadaki %** | Anlık kabul oranın. **Dokun** → widget küçük bir **R** baloncuğuna küçülür |
| **R baloncuğu** | **Dokun** → widget tekrar açılır |

Widget’ı **sürükleyerek** ekranda istediğin yere taşıyabilirsin. Yatay boyut yaklaşık **276×80 dp**; dikey mod **Ayarlar → Baloncuk yönü → Dikey** ile seçilir (~74×194 dp).

Ekranda yer açmak için **%**’ye dokun: widget 48 dp’lik bir **R** baloncuğuna küçülür; baloncuğun dışındaki dokunuşlar Uber’e gider. **R**’ye dokununca tam baloncuk geri gelir. Baloncuk da sürüklenebilir. Küçükken +/−, sayaç kaydı ve direksiyon tuşu çalışmaya devam eder. Uygulama küçük/açık durumunu hatırlar.

**Ayarlar → Baloncukta iptal düğmesi** açıksa, kırmızı **−** yanında turuncu **iptal** düğmesi de görünür.

Ana ekrandaki sayaçlar, baloncuktan yaptığın değişiklikleri **anında** yansıtır (uygulamayı kapat-aç gerekmez).

### Bildirim kontrolleri (isteğe bağlı)

**Ayarlar → Bildirim kontrolleri** açıkken, baloncuk açık olduğu sürece bildirim panelini aşağı çekince solda büyük **−** (Red +1), sağda **+** (Kabul +1) düğmesi, ortada da güncel kabul oranı görünür. Her dokunuşta telefon titrer: kabulde tek, redde çift titreşim. Ekranı hiç kapatmadan sayabilirsin; baloncuğu **R**’ye küçültüp sadece paneli kullanmak da olur.

Ekranda hiçbir şey istemiyorsan, hemen altındaki **Yüzen baloncuğu gizle (Sadece bildirim paneli)** ayarını aç: baloncuk açıldığında ekranda görünmez, sayaç yalnızca bildirim panelinden (ve direksiyon tuşundan) çalışır. Bildirim kontrollerini kapatınca veya bildirim izni geri alınınca baloncuk otomatik geri gelir.

- İlk açışta uygulama bildirim izni ister. İzin vermezsen ayar kapalı kalır; izni **Ayarlar → Uygulamalar → RateHelper → Bildirimler**’den verip ayarı tekrar açabilirsin.
- Bildirimde sadece kabul oranı ve kabul/red sayıları vardır — kazanç yoktur. Kilit ekranında görünmez.
- Her dokunuşta kısa bir titreşim olur. Oran en fazla saniyede bir güncellenir.

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

Her **HAFTAYI SIFIRLA** işleminde o haftanın özeti buraya **kart** olarak kaydedilir. Karta dokun → detay açılır (tamamlanan / kabul / red sayıları, o haftanın hedefi). **Hedef Tuttu** veya **Hedef Tutmadı** satırı, o hafta seçtiğin kademeye göre kabul ve iptal sınırına bakar. Aynı hafta içinde ikinci kez resetlersen sayılar tek kartta birleşir.

---

## 7) Kazanç takibi (💰)

**Kazanç** ekranı haftalık Uber gelirini, yakıt, kira, vergi ve net kârını hesaplar. Tüm veriler **telefonda kalır** — buluta gönderilmez.

### İlk açılış

1. **Tek / İki / Üç Sürücü** modundan hangisini kullandığını seç (**Ayarlar → Sürüş modu** veya Kazanç ekranındaki ilk kurulum) — kira tabloları buna göre değişir.
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

- Otomatik getirme **kapalı** başlar. Açık değilse liste kendiliğinden inmez.
- Önbellek varsa etkinlikler **ne zaman yüklendiğiyle** gösterilir. Önbellek yoksa **Etkinlikleri yükle** düğmesi çıkar.
- Üstteki yenile düğmesi veya aşağı çekmek listeyi GitHub’dan ister.
- Giden tek şey IP adresin ve standart istek başlıklarıdır. Yolculuk ve kazanç verin gitmez.
- Adres: `raw.githubusercontent.com` (herkese açık Kraków etkinlik listesi).

---

## 9) Direksiyon tuşu ile sayma (isteğe bağlı, Beta)

Ellerini direksiyondan ayırmadan sayaç tutmak istersen:

1. **Ayarlar → Direksiyon tuşu ile sayma (Beta)** anahtarını **AÇ**.
2. **Erişilebilirlik izni** istenirse → **AYARLARA GİT** → RateHelper servisini **AÇ**.
3. Kullanım:
   - **Sonraki şarkı / oynat-dur** tuşuna **800 ms basılı tut** → kabul sayacı +1
   - **Önceki şarkı** tuşuna **800 ms basılı tut** → red sayacı +1
   - **Kısa basış** → müzik uygulaman (Spotify vb.) normal çalışmaya devam eder

> Bu özellik Android **Erişilebilirlik** servisi kullanır. İstemezsen anahtarı kapalı bırak — uygulamanın geri kalanı normal çalışır.

---

## 10) Sürücü modu değiştirme

Araba paylaşımlı mı, üç kişi mi biniyorsunuz?

Ana ekran → **dişli (Ayarlar)** → **Sürüş modu** → **Tek Sürücü**, **İki Sürücü (Paylaşımlı)** veya **Üç Sürücü (Paylaşımlı)**.

> Geçmiş haftaların kayıtlı modu değişmez; yalnızca yeni kayıtlar yeni moda göre hesaplanır. İki ve üç sürücüde **araç toplam yolculuk sayısı** kira kademesi için ayrı girilebilir (Kazanç formu).

---

## 11) Sorun çıkarsa

### Uygulama kapanıyor veya widget kayboluyor

1. **Ayarlar → Kurulum Rehberi**’ni tekrar oku — pil optimizasyonu ve overlay izni hâlâ açık mı kontrol et.
2. Widget’ı **Durdur** → tekrar **Başlat**.
3. Samsung’da Recents’te RateHelper kartını **kilitle**.

### Çökme kaydı gönderme

1. **Ayarlar → Çökme Kayıtları**
2. **KOPYALA** butonuna bas
3. Yapıştırdığını WhatsApp üzerinden geliştiriciye gönder

> Çökme kayıtları uygulamanın **dahili** (sandbox) alanında tutulur. Dosya yöneticisiyle erişilemez — yalnızca uygulama içindeki **KOPYALA** yolunu kullan.

### Güncelleme (OTA)

İlk açılışta (bu sürüme güncellediğinde de bir kez) uygulama sorar: GitHub’a güncelleme ve etkinlik için kendiliğinden baksın mı? **İzin ver** iki anahtarı da açar. **Hayır, yalnız ben isteyince** ikisini de kapalı bırakır. **Ayarlar → Otomatik güncelleme denetimi** ve **Etkinlikleri otomatik getir** ile sonra değiştirirsin.

Kapalıyken açılışta ağ yoktur. Yeni sürüm için **Ayarlar → Güncellemeleri denetle** (aynı satırda son kontrol saati ve kurulu sürüm yazar). APK, ancak güncelleme düğmesine basınca iner — denetlemek indirmez. İndirilen paket imza ve sürüm kontrolünden geçmeden kurulmaz; önceki kurulumla **aynı imza** gerekir.

Bu isteklerde giden: IP adresi ve standart başlıklar. Verin gitmez.

- `gist.githubusercontent.com` — sürüm listesi
- `api.github.com` — liste okunamazsa yedek sorgu
- `github.com` — APK (yalnızca sen indir deyince)
- `raw.githubusercontent.com` — etkinlik listesi

---

## 12) Geliştirici notları (sadece kurucu / maintainer)

Üretim derlemesi:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/ --dart-define-from-file=dart_defines.json
```

- `--obfuscate` → Dart AOT sembollerini siler.
- `--split-debug-info` → sembolleri proje dışında tutar (geri izleme için sakla).
- `--split-per-abi` → APK boyutunu ~8 MB / mimari seviyesine düşürür.
- `--dart-define-from-file` → Git tarafından yok sayılan yerel yapılandırmayı derlemeye ekler; dosyanın içeriğini yazdırma veya commit etme.

`key.properties` proje kökünde durmalı ve okunabilir olmalı (`android/key.properties` değil). Yoksa veya okunamazsa release derlemesi `GradleException` ile durur — debug anahtarına düşmez. Debug derlemesi bu dosya olmadan çalışır. Her sürümde aynı keystore kullan.

Detaylı mimari: [`README.md`](README.md) · Agent notları: [`agent-learnings.md`](agent-learnings.md) · Lehçe rehber: [`SETUP_GUIDE_PL.md`](SETUP_GUIDE_PL.md)

---

> **RateHelper** — Sürücü koltuğundan yazıldı, Kraków yollarında gerçek kazancın için.
