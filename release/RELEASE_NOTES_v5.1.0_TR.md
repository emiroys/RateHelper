# RateHelper v5.1.0

*(20 Ekim 2026)*

## Öne çıkanlar

- **ORLEN yakıt merkezi:** Kraków’daki **30 ORLEN istasyonu**, **PB95 ve LPG** fiyatları, sürücülerin fiyat bildirimi, **Google Maps / Waze** navigasyonu ve yakıt fişleri. Liste **en ucuz** veya **en yakın** istasyona göre sıralanabilir.
- **Bildirim paneli kontrolleri:** İsteğe bağlı **Reddet +1** ve **Kabul +1** düğmeleri ile panelde anlık kabul oranı. İstersen **yalnızca bildirim paneli** modunu aç — baloncuk ekranda görünmez, sayma panelden ve direksiyon tuşundan devam eder.
- **Yedekleme ve geri yükleme:** Ayarlar, sayaçlar, haftalık arşiv ve kazançların tamamı yerel bir JSON dosyasına aktarılabilir; geri yüklemeden önce önizleme, SHA-256 bütünlük kontrolü ve ani kapanmaya karşı kurtarma günlüğü vardır. **Dışa aktarılan dosya şifreli değildir** — hassas veri gibi sakla.
- **Yeni beş adımlı kurulum sihirbazı:** karşılama, baloncuk izni, pil güvenilirliği, isteğe bağlı özellikler ve özet. **Türkçe / Lehçe / İngilizce** dil seçimi ilk ekrandan yapılabilir.
- **Uygulama içinden hata bildirimi:** “Sorun bildir” ekranında açıklama yazabilir; istersen ekran görüntüsü, cihaz tanılaması ve hata günlüğü ekleyebilirsin. Açıklama gizlilik açısından temizlenir; hata günlüğü varsayılan olarak kapalıdır.
- **Tek seferlik fiyat anketi:** Güncellemeden (veya yeni kurulumda sihirbazdan) sonra uygulama üç kısa soru sorar. Yanıtlar anononimdir, yalnızca bir kez gönderilir; cihaz çevrimdışıysa yerelde saklanır ve uygun olduğunda gönderilir. **Uygulama ücretsiz kalır; anket hiçbir abonelik veya ödeme başlatmaz.**
- **Güvenilirlik:** Baloncuk ile ana ekran sayaç senkronu, değişikliklerin daha güvenli kaydı, haftalık arşiv (haftanın hedef ve eşikleri kayıtta, aynı haftanın ikinci sıfırlamasının birleştirilmesi), kazanç hesapları ve yeniden başlatma sonrası veri kurtarma iyileştirmeleri.
- **Ayarlar:** Gruplanmış kartlar (sürüş ve sayaçlar, baloncuk, tercihler, sistem ve destek), **Geliştiriciyle iletişim** satırı; **Güncellemeleri denetle** ve **Kurulum Rehberi** artık burada.

## ORLEN yakıt merkezi ayrıntıları

Ana ekrandaki **Yakıt** düğmesi yakıt merkezini açar:

- **İstasyonlar:** Kraków şehir sınırları içindeki 30 doğrulanmış ORLEN istasyonu. Mesafe yalnızca **En yakın** sıralamasını seçip konum izni verdiğinde hesaplanır.
- **Fiyatlar:** PB95/LPG fiyatları sürücülerin gönderdiği ve yöneticinin onayladığı kayıtlardan gelir; hafif Cloudflare arka ucundan okunur. `ORLEN_API_URL` tanımlı değilse istasyonlar, sıralama, navigasyon ve fişler çalışmaya devam eder; yalnızca uzak fiyatlar ve fiyat gönderme kapalıdır.
- **Fiyat bildirimi:** İstasyonu ve yakıtı seç, fiyatı yaz; kayıt önce yönetici onayına gider, onaylanınca herkese görünür.
- **Navigasyon:** Yol tarifi düğmesi Google Maps veya Waze açar.
- **Fişler:** İkinci sekmede yakıt tutarını kaydedebilir, araç paylaşıyorsan bölebilirsin; fişler haftalık kazanç hesabına işlenir.

> Her istasyon fiziksel olarak LPG satmak zorunda değildir. Veri modeli, LPG sattığı bilinen istasyonlarda LPG fiyatını destekler; fiyatın olmaması istasyonda LPG olmadığı anlamına gelmez.

## Yedekleme hakkında

- **Dışa aktarma:** Ayarlar → **Verileri yedekle**. JSON dosyasını güvenli bir yerde sakla.
- **Geri yükleme:** Ayarlar → **Yedekten geri yükle**. Onaydan önce sürüm, sayaç haftası ve kayıt sayısı önizlenir.
- **Şifreli değildir:** Dosyayı ele geçiren herkes içeriği okuyabilir. Genel kanallardan gönderme.
- **Kurtarma:** Geri yükleme sırasında uygulama kapanırsa, bir sonraki açılışta kaldığı yerden tamamlanır.

## Anket ve gizlilik

- Anket **üç sorudan** oluşur ve atlanamaz; **kurulum başına bir kez** gösterilir.
- Yanıtlar; ad, telefon, e-posta, GPS, yolculuk veya kazanç verisi içermez. Yalnızca rastgele kurulum kimliği, anket sürümü ve üç seçilen yanıt gönderilir.
- İnternet yoksa yanıt cihazda saklanır ve uygulama bir sonraki ön plana geldiğinde gönderilir.
- Sürüş ve hesap verilerinin çoğu telefonda kalır. Cloudflare arka ucuna yalnızca **yakıt fiyatı bildirimleri**, **hata raporları** ve **anket yanıtları**, yalnızca bu özellikleri kullandığında gider. Hata raporuna eklenen ekran görüntüsü veya açıklama kişisel bilgi içerebilir; bilinçli ekle.
- Uygulama hesap açmaz, reklam kimliği veya üçüncü taraf analitik kullanmaz.

## Değişmeyenler (bunlar yeni değil)

Yüzen baloncuk, temel sayaçlar ve kabul yüzdesi, 2000 yolculuk sayacı, haftalık hedefler ve arşiv, Etkinlik Radarı, PDF dışa aktarma, üç dilli arayüz (ilk açılışta cihaz dili algılama) ve GitHub güncelleme mekanizması aynen çalışmaya devam eder.
