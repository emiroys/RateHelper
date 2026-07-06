import 'dart:ui';

enum AppLang { tr, en, pl }

class S {
  S._();

  static AppLang _lang = AppLang.tr;
  static AppLang get lang => _lang;
  static void setLang(AppLang l) => _lang = l;

  /// Maps device locale to nearest supported language on first launch.
  static AppLang langFromLocale(Locale locale) {
    switch (locale.languageCode.toLowerCase()) {
      case 'tr':
        return AppLang.tr;
      case 'pl':
        return AppLang.pl;
      default:
        return AppLang.en;
    }
  }

  static String get requests => _p('GELEN İSTEKLER', 'REQUESTS', 'ZLECENIA');
  static String get trips => _p('YOLCULUKLAR', 'TRIPS', 'PRZEJAZDY');
  static String get acceptRate => _p('KABUL ORANI', 'ACCEPT RATE', 'AKCEPTACJA %');
  static String get cancelRate => _p('İPTAL ORANI', 'CANCEL RATE', 'ANULOWANIE %');
  static String formatPercent(String val) => _p('%$val', '$val%', '$val%');
  static String get accepted => _p('Kabul Edilen', 'Accepted', 'Zaakceptowane');
  static String get rejected => _p('Reddedilen', 'Rejected', 'Odrzucone');
  static String get completed => _p('Tamamlanan', 'Completed', 'Ukończone');
  static String get cancelled => _p('İptal Edilen', 'Cancelled', 'Anulowane');
  static String get autoCompleteTrips => _p(
        'Otomatik tamamla',
        'Auto-complete trips',
        'Automatyczne ukończenie',
      );
  static String get steeringWheelCounter => _p(
        'Direksiyon Tuşu ile Sayma (Beta)',
        'Steering Wheel Counter (Beta)',
        'Licznik z kierownicy (Beta)',
      );
  static String get steeringWheelDialogTitle => _p(
        'Erişilebilirlik İzni Gerekli',
        'Accessibility Permission Required',
        'Wymagane uprawnienie dostępności',
      );
  static String get steeringWheelDialogDesc => _p(
        'Direksiyondaki Sonraki Şarkı tuşuna basılı tutarak (800ms) müzik kesilmeden sefer sayacı artırma özelliğinin çalışabilmesi için Erişilebilirlik ayarlarından RateHelper servisinin açılması gereklidir.',
        'To count rides by long-pressing (800ms) the Next Track steering wheel button without interrupting music, RateHelper service must be enabled in Accessibility settings.',
        'Aby liczyć przejazdy poprzez długie naciśnięcie (800 ms) przycisku następnego utworu bez przerywania muzyki, musisz włączyć usługę RateHelper w ustawieniach ułatwień dostępu.',
      );
  static String get openSettings => _p(
        'AYARLARA GİT',
        'OPEN SETTINGS',
        'OTWÓRZ USTAWIENIA',
      );
  static String get editCompletedTitle =>
      _p('Tamamlanan Sayısı', 'Completed Trips', 'Ukończone przejazdy');
  static String get editAcceptedTitle =>
      _p('Kabul Edilen Sayısı', 'Accepted Rides', 'Zaakceptowane zlecenia');
  static String get editRejectedTitle =>
      _p('Reddedilen Sayısı', 'Rejected Rides', 'Odrzucone zlecenia');
  static String get editCancelledTitle =>
      _p('İptal Edilen Sayısı', 'Cancelled Rides', 'Anulowane przejazdy');
  static String get save => _p('KAYDET', 'SAVE', 'ZAPISZ');

  static String recovery(int n) => _p(
        'Oranı %80.00 üzerine çıkarmak için sıradaki $n isteği üst üste KABUL etmelisin.',
        'To exceed 80.00%, ACCEPT the next $n requests in a row.',
        'Aby przekroczyć 80.00%, zaakceptuj $n kolejnych zleceń z rzędu.',
      );

  static String get resetWeek => _p('HAFTAYI SIFIRLA', 'RESET WEEK', 'RESETUJ TYDZIEŃ');
  static String get resetWeekTitle => _p('Haftayı Sıfırla', 'Reset Week', 'Resetuj Tydzień');
  static String get resetConfirm => _p(
        'Tüm sayaçlar sıfırlanacak. Emin misin?',
        'All counters will be reset. Are you sure?',
        'Wszystkie liczniki zostaną zresetowane. Na pewno?',
      );
  static String get cancel => _p('İPTAL', 'CANCEL', 'ANULUJ');
  static String get reset => _p('SIFIRLA', 'RESET', 'RESETUJ');
  static String get history => _p('GEÇMİŞ', 'HISTORY', 'HISTORIA');
  static String get noHistory =>
      _p('Henüz geçmiş veri yok.', 'No history yet.', 'Brak historii.');
  static String get tapLogTab => _p('KAYITLAR', 'TAPS', 'DOTKNIĘCIA');
  static String get weeklyTab => _p('HAFTALIK', 'WEEKLY', 'TYGODNIOWE');
  static String get noTapHistory => _p(
        'Henüz dokunuş kaydı yok.',
        'No tap records yet.',
        'Brak zapisów dotknięć.',
      );
  static String get tapHistoryClear => _p('Temizle', 'Clear', 'Wyczyść');
  static String get tapHistoryClearConfirm => _p(
        'Tüm kayıtlar silinecek. Emin misin?',
        'All tap records will be deleted. Are you sure?',
        'Wszystkie zapisy dotknięć zostaną usunięte. Na pewno?',
      );
  static String get filterToday => _p('Bugün', 'Today', 'Dziś');
  static String get filterAll => _p('Tümü', 'All', 'Wszystko');
  static String get tapAcceptShort => _p('Kabul', 'Accept', 'Akceptacja');
  static String get tapRejectShort => _p('Red', 'Reject', 'Odrzucenie');
  static String get overlayOn =>
      _p('RateHelper Aktif', 'RateHelper Active', 'RateHelper Aktywny');
  static String get overlayOff =>
      _p('RateHelper Kapatıldı', 'RateHelper Closed', 'RateHelper Wyłączony');
  static String get archiveAccept => _p('Kabul', 'Accept', 'Akceptacja');
  static String get archiveCancel => _p('İptal', 'Cancel', 'Anulowanie');
  static String get overlayTitle =>
      _p('RateHelper Aktif', 'RateHelper Active', 'RateHelper Aktywny');
  static String get overlayContent => _p(
        'Çalışıyor.',
        'Running.',
        'Działa.',
      );

  static String get onboardingTitle => _p(
        'RateHelper Kurulumu',
        'RateHelper Setup',
        'Konfiguracja RateHelper',
      );
  static String get onboardingIntro => _p(
        'RateHelper’in arka planda çalışabilmesi için iki Android iznine ihtiyacı var. Aşağıdaki adımları sırayla yap.',
        'RateHelper needs two Android permissions to run in the background. Complete the steps below in order.',
        'RateHelper potrzebuje dwóch uprawnień Androida, aby działać w tle. Wykonaj poniższe kroki po kolei.',
      );
  static String get stepOverlayTitle => _p(
        '1. Üzerine Çizim İzni',
        '1. Display Over Other Apps',
        '1. Nakładka nad innymi aplikacjami',
      );
  static String get stepOverlayBody => _p(
        'Uber Driver açıkken RateHelper’in butonlarını göstermesi için bu izin şart. Açılan ayar ekranında RateHelper’i bul ve aç.',
        'Required so RateHelper buttons appear on top of Uber Driver. In the settings screen that opens, find RateHelper and enable the switch.',
        'Wymagane, aby przyciski RateHelper pojawiały się nad Uber Driver. W otwartym ekranie ustawień znajdź RateHelper i włącz przełącznik.',
      );
  static String get stepOverlayCta => _p(
        'İZNİ AÇ',
        'GRANT PERMISSION',
        'NADAJ UPRAWNIENIE',
      );
  static String get stepOverlayDone => _p('VERİLDİ', 'GRANTED', 'NADANO');

  static String get stepBatteryTitle => _p(
        '2. Pil Optimizasyonunu Kapat',
        '2. Disable Battery Optimization',
        '2. Wyłącz oszczędzanie baterii',
      );
  static String get stepBatteryBody => _p(
        'Vardiya boyunca RateHelper’in arka planda öldürülmemesi için pil optimizasyonu KAPALI olmalı. Telefon markana göre talimat aşağıda.',
        'To prevent RateHelper being killed during your shift, battery optimization must be OFF. Instructions per phone brand below.',
        'Aby RateHelper nie został zabity podczas zmiany, optymalizacja baterii musi być WYŁĄCZONA. Instrukcje dla marki telefonu poniżej.',
      );
  static String get stepBatteryCta => _p(
        'AYARLARI AÇ',
        'OPEN SETTINGS',
        'OTWÓRZ USTAWIENIA',
      );

  static String get finish => _p('BİTİR', 'FINISH', 'ZAKOŃCZ');
  static String get skip => _p('Atla', 'Skip', 'Pomiń');
  static String get setupGuide => _p(
        'Kurulum Rehberi',
        'Setup Guide',
        'Przewodnik konfiguracji',
      );

  static String get brandSamsung => 'Samsung (One UI)';
  static String get brandXiaomi => 'Xiaomi / Redmi (MIUI / HyperOS)';
  static String get brandHuawei => 'Huawei / Honor (EMUI)';
  static String get brandOnePlus => 'OnePlus / Oppo (OxygenOS / ColorOS)';
  static String get brandOther => _p('Diğer', 'Other', 'Inne');

  static String get samsungSteps => _p(
        'Ayarlar → Cihaz bakımı → Pil → Arka plan kullanım sınırları → Asla uyutulmayacak uygulamalar → RateHelper ekle.',
        'Settings → Device care → Battery → Background usage limits → Never sleeping apps → add RateHelper.',
        'Ustawienia → Konserwacja → Bateria → Limity tła → Aplikacje, które nigdy nie usypiają → dodaj RateHelper.',
      );
  static String get xiaomiSteps => _p(
        'Ayarlar → Uygulamalar → RateHelper → Pil tasarrufu → Kısıtlama yok. Ayrıca: Otomatik başlatma → AÇIK.',
        'Settings → Apps → RateHelper → Battery saver → No restrictions. Also: Autostart → ON.',
        'Ustawienia → Aplikacje → RateHelper → Oszczędzanie baterii → Brak ograniczeń. Także: Autostart → WŁ.',
      );
  static String get huaweiSteps => _p(
        'Ayarlar → Uygulamalar → RateHelper → Pil → Uygulama başlatma → Otomatik yönet KAPAT → tüm manuel anahtarlar AÇIK.',
        'Settings → Apps → RateHelper → Battery → App launch → turn OFF Manage automatically → turn ON all three switches.',
        'Ustawienia → Aplikacje → RateHelper → Bateria → Uruchamianie aplikacji → wyłącz Zarządzaj automatycznie → wszystkie trzy włączniki WŁ.',
      );
  static String get onePlusSteps => _p(
        'Ayarlar → Pil → Pil optimizasyonu → RateHelper → Optimize etme. Ayrıca: Son uygulamalar ekranında RateHelper kartını yukarıdan kilitle.',
        'Settings → Battery → Battery optimization → RateHelper → Don’t optimize. Also: lock the RateHelper card from the top in Recents.',
        'Ustawienia → Bateria → Optymalizacja baterii → RateHelper → Nie optymalizuj. Także: zablokuj kartę RateHelper w Ostatnich.',
      );
  static String get otherSteps => _p(
        'Telefonun pil ayarlarında "RateHelper" uygulamasını bul ve pil optimizasyonunu KAPAT veya "Kısıtlanmamış" olarak işaretle.',
        'In your phone’s battery settings, find "RateHelper" and turn battery optimization OFF, or mark it as "Unrestricted".',
        'W ustawieniach baterii telefonu znajdź "RateHelper" i wyłącz optymalizację lub oznacz jako "Bez ograniczeń".',
      );

  static String get crashLogTitle => _p(
        'Çökme Kayıtları',
        'Crash Log',
        'Dziennik awarii',
      );
  static String get crashLogEmpty => _p(
        'Henüz kayıt yok. Uygulama her şey yolundaysa burası boş kalır.',
        'No entries yet. If everything is working this stays empty.',
        'Brak wpisów. Jeśli wszystko działa, jest pusto.',
      );
  static String get crashLogCopy => _p(
        'KOPYALA',
        'COPY',
        'KOPIUJ',
      );
  static String get crashLogClear => _p(
        'TEMİZLE',
        'CLEAR',
        'WYCZYŚĆ',
      );
  static String get crashLogCopied => _p(
        'Panoya kopyalandı',
        'Copied to clipboard',
        'Skopiowano do schowka',
      );

  static String get version => _p('Sürüm', 'Version', 'Wersja');
  static String get designer => _p('Tasarımcı', 'Designer', 'Projektant');

  static String get navLang => _p('Dil', 'Lang', 'Język');
  static String get navLogs => _p('Kayıtlar', 'Log', 'Logi');
  static String get navEarnings => _p('Kazanç', 'Earnings', 'Zarobki');

  // Earnings tracker
  static String get earningsTitle => _p('Kazanç Takibi', 'Earnings', 'Zarobki');
  static String get hourlyRate =>
      _p('SAATLİK KAZANÇ', 'HOURLY RATE', 'STAWKA GODZINOWA');
  static String get perHour => _p('PLN/saat', 'PLN/hr', 'PLN/godz');
  static String get netProfit => _p('NET KÂR', 'NET PROFIT', 'ZYSK NETTO');
  static String get breakdown => _p('DÖKÜM', 'BREAKDOWN', 'ROZLICZENIE');

  // Earnings entry — single section
  static String get netIncome => _p('Net Gelir', 'Net Income', 'Dochód Netto');
  static String get netIncomeHint => _p(
        'Uber uygulamasında Kazançlar ekranının en üstünde yazan büyük rakam',
        'The big number at the top of the Earnings screen in the Uber app',
        'Duża liczba na górze ekranu Zarobki w aplikacji Uber',
      );
  static String get cashReceived =>
      _p('Alınan Nakit', 'Cash Received', 'Otrzymana Gotówka');
  static String get vat => _p('VAT (%11.5)', 'VAT (11.5%)', 'VAT (11,5%)');
  static String get commission => _p('Komisyon', 'Commission', 'Prowizja');
  static String get rental => _p('Kira', 'Rental', 'Wynajem');
  static String get rentalDiscountToggle => _p(
        'Kira İndirimi Var mı?',
        'Rental discount?',
        'Zniżka na wynajem?',
      );
  static String rentalComputed(String range, String value) => _p(
        'Kira (Kademe: $range): $value PLN',
        'Rental (Tier: $range): $value PLN',
        'Wynajem (Próg: $range): $value PLN',
      );
  static String rentalComputedFlat(String value) => _p(
        'Kira (İndirimsiz): $value PLN',
        'Rental (No discount): $value PLN',
        'Wynajem (Bez zniżki): $value PLN',
      );
  static String get adminCost =>
      _p('İdari Gider', 'Administrative Cost', 'Koszt Administracyjny');
  static String get fuelPumpPaid =>
      _p('Pompada Ödenen', 'Paid at Pump', 'Zapłacono na stacji');
  static String fuelRealCostPreview(String value) => _p(
        'Gerçek maliyet (%10 indirimli): $value PLN',
        'Real cost (10% discount): $value PLN',
        'Rzeczywisty koszt (10% rabatu): $value PLN',
      );
  static String get fuelDiscounted =>
      _p('Yakıt (İndirimli)', 'Fuel (discounted)', 'Paliwo (rabat)');

  static String get bankDeposit =>
      _p('Hesaba Yatacak', 'To Bank Account', 'Na Konto');
  static String get cashInHand => _p('Elde Nakit', 'Cash in Hand', 'Gotówka');

  static String get onlineTime =>
      _p('Çevrimiçi Süre', 'Online Time', 'Czas Online');
  static String get tripCount => _p('Yolculuk', 'Trips', 'Przejazdy');
  static String get tripCountLabel =>
      _p('Yolculuk Sayısı', 'Trip Count', 'Liczba Przejazdów');
  static String get edit => _p('Düzenle', 'Edit', 'Edytuj');
  static String get addWeek =>
      _p('Yeni Hafta Ekle', 'Add Week', 'Dodaj Tydzień');
  static String get editWeek =>
      _p('Haftayı Düzenle', 'Edit Week', 'Edytuj Tydzień');
  static String get noEarnings => _p(
        'Henüz hafta eklenmedi. İlk haftanı ekle.',
        'No weeks added yet. Add your first week.',
        'Brak tygodni. Dodaj pierwszy tydzień.',
      );
  static String get delete => _p('Sil', 'Delete', 'Usuń');
  static String get deleteWeekConfirm => _p(
        'Bu hafta silinecek. Emin misin?',
        'This week will be deleted. Are you sure?',
        'Ten tydzień zostanie usunięty. Na pewno?',
      );
  static String get requiredField =>
      _p('Zorunlu', 'Required', 'Wymagane');
  static String get enterValidAmount => _p(
        'Eksik veri: 0’dan büyük bir değer girin',
        'Missing data: enter a value greater than 0',
        'Brak danych: podaj wartość większą od 0',
      );
  static String get onlineTimeMissing => _p(
        'Eksik veri: çevrimiçi süreyi girin',
        'Missing data: enter online time',
        'Brak danych: podaj czas online',
      );
  static String get hoursShort => _p('sa', 'h', 'godz');
  static String get minutesShort => _p('dk', 'min', 'min');
  static String get widgetStart => _p('Başlat', 'Start', 'Uruchom');
  static String get widgetStop => _p('Durdur', 'Stop', 'Zatrzymaj');

  // Cross-check warnings (informational, never block saving)
  static String get warnHourlyRate => _p(
        'Bu haftanın saatlik kazancı alışılmadık görünüyor, giriş hatası olabilir',
        'This week’s hourly rate looks unusual — possible entry error',
        'Stawka godzinowa w tym tygodniu wygląda nietypowo — możliwy błąd wpisu',
      );

  // Trend chart titles
  static String get trendTitle =>
      _p('HAFTALIK TREND', 'WEEKLY TREND', 'TREND TYGODNIOWY');
  static String get monthlyTrendTitle => _p(
        'AYLIK SAATLİK KAZANÇ TRENDİ',
        'MONTHLY HOURLY RATE TREND',
        'MIESIĘCZNY TREND STAWKI',
      );
  static String get yearlyTrendTitle => _p(
        'YILLIK SAATLİK KAZANÇ TRENDİ',
        'YEARLY HOURLY RATE TREND',
        'ROCZNY TREND STAWKI',
      );
  static String fourWeekAverage(String value) => _p(
        'Son 4 hafta ortalaması: $value PLN/saat',
        'Last 4 weeks average: $value PLN/hr',
        'Średnia z 4 tygodni: $value PLN/godz',
      );
  static String get trendNoData => _p(
        'Trend için yeterli veri yok.',
        'Not enough data for a trend yet.',
        'Za mało danych na trend.',
      );

  // View toggle: weekly / monthly / yearly
  static String get viewWeekly => _p('Haftalık', 'Weekly', 'Tygodniowo');
  static String get viewMonthly => _p('Aylık', 'Monthly', 'Miesięcznie');
  static String get viewYearly => _p('Yıllık', 'Yearly', 'Rocznie');

  // Monthly / yearly summary card
  static String get totalNetProfit =>
      _p('TOPLAM NET KÂR', 'TOTAL NET PROFIT', 'CAŁKOWITY ZYSK NETTO');
  static String get avgHourlyRate =>
      _p('Ort. saatlik', 'Avg hourly', 'Śr. godzinowa');
  static String get totalOnlineHours =>
      _p('Toplam saat', 'Total hours', 'Suma godzin');
  static String weekCountLabel(int n) => _p(
        '$n hafta',
        '$n weeks',
        '$n tyg.',
      );
  static String get weekCountStat =>
      _p('Hafta sayısı', 'Weeks', 'Tygodnie');

  // Records (rekorlar)
  static String get bestWeek => _p('En İyi Hafta', 'Best Week', 'Najlepszy Tydzień');
  static String get bestWeekEmpty => _p(
        'Bu dönemde henüz kayıtlı hafta yok.',
        'No recorded weeks in this period yet.',
        'Brak zapisanych tygodni w tym okresie.',
      );

  // Break-even indicator
  static String breakEvenLabel(String value) => _p(
        'Başabaş Noktası: bu hafta en az $value PLN net gelir etmen gerekiyor',
        'Break-even: you need at least $value PLN net income this week',
        'Próg rentowności: potrzebujesz min. $value PLN dochodu netto w tym tygodniu',
      );
  static String get belowBreakEven => _p(
        'Bu hafta başabaş noktasının altında',
        'This week is below break-even',
        'Ten tydzień jest poniżej progu rentowności',
      );

  // Monday reminder notification + settings toggle
  static String get reminderSettingsTitle => _p(
        'Pazartesi Hatırlatması',
        'Monday Reminder',
        'Przypomnienie w poniedziałek',
      );
  static String get reminderSettingsBody => _p(
        'Her Pazartesi 09:00’da geçen haftanın kazançlarını girmeni hatırlatır.',
        'Reminds you every Monday at 09:00 to log last week’s earnings.',
        'Przypomina w każdy poniedziałek o 09:00, aby wpisać zarobki z ubiegłego tygodnia.',
      );
  static String get reminderNotificationTitle => _p(
        'Kazanç Takibi',
        'Earnings Tracker',
        'Śledzenie zarobków',
      );
  static String get reminderNotificationBody => _p(
        'Geçen haftanın kazanç verilerini eklemeyi unutma!',
        'Don’t forget to log last week’s earnings!',
        'Nie zapomnij wpisać zarobków z ubiegłego tygodnia!',
      );
  static String get reminderChannelName => _p(
        'Haftalık Hatırlatma',
        'Weekly Reminder',
        'Cotygodniowe przypomnienie',
      );
  static String get reminderChannelDescription => _p(
        'Pazartesi kazanç girme hatırlatması',
        'Monday earnings logging reminder',
        'Poniedziałkowe przypomnienie o zarobkach',
      );

  // PDF export
  static String get exportPdf => _p(
        'PDF Olarak Dışa Aktar',
        'Export as PDF',
        'Eksportuj do PDF',
      );
  static String get exportPdfRangeTitle => _p(
        'Tarih Aralığı Seç',
        'Select Date Range',
        'Wybierz zakres dat',
      );
  static String get rangeThisMonth => _p('Bu Ay', 'This Month', 'Ten miesiąc');
  static String get rangeSpecificMonth =>
      _p('Belirli Bir Ay', 'Specific Month', 'Konkretny miesiąc');
  static String get rangeThisYear => _p('Bu Yıl', 'This Year', 'Ten rok');
  static String get rangeAllTime => _p('Tüm Zamanlar', 'All Time', 'Cały czas');
  static String get exportPickMonthTitle =>
      _p('Ay Seç', 'Select Month', 'Wybierz miesiąc');
  static String get exportNoData => _p(
        'Seçilen aralıkta veri yok.',
        'No data in the selected range.',
        'Brak danych w wybranym zakresie.',
      );
  static String get exportShareText => _p(
        'Kazanç raporu',
        'Earnings report',
        'Raport zarobków',
      );

  // PDF document content
  static String get pdfTitle => _p(
        'Kazanç Raporu',
        'Earnings Report',
        'Raport Zarobków',
      );
  static String get pdfDriver => _p('Sürücü', 'Driver', 'Kierowca');
  static String get pdfDriverPlaceholder =>
      _p('__________________', '__________________', '__________________');

  // Driver name setup (PDF header)
  static String get driverNamePrompt => _p(
        'PDF raporunda görünmesi için adını girer misin?',
        'Enter your name so it appears on the PDF report',
        'Podaj swoje imię i nazwisko, aby pojawiło się w raporcie PDF',
      );
  static String get driverNameLabel => _p('Ad Soyad', 'Full Name', 'Imię i nazwisko');
  static String get driverNameContinue => _p('Devam Et', 'Continue', 'Kontynuuj');
  static String get driverNameDefault => _p('Sürücü', 'Driver', 'Kierowca');
  static String get pdfDateRange =>
      _p('Tarih Aralığı', 'Date Range', 'Zakres dat');
  static String get pdfGeneratedOn =>
      _p('Oluşturulma', 'Generated', 'Wygenerowano');
  static String get pdfColWeek => _p('Hafta', 'Week', 'Tydzień');
  static String get pdfColNetIncome =>
      _p('Net Gelir', 'Net Income', 'Dochód netto');
  static String get pdfColRental => _p('Kira', 'Rental', 'Wynajem');
  static String get pdfColFuel => _p('Yakıt', 'Fuel', 'Paliwo');
  static String get pdfColVat => _p('VAT', 'VAT', 'VAT');
  static String get pdfColCommission =>
      _p('Komisyon', 'Commission', 'Prowizja');
  static String get pdfColNetProfit =>
      _p('Net Kâr', 'Net Profit', 'Zysk netto');
  static String get pdfColHourly =>
      _p('Saatlik Kazanç', 'Hourly', 'Stawka godz.');
  static String get pdfTotals => _p('TOPLAM', 'TOTAL', 'RAZEM');
  static String get pdfSummaryNetIncome => _p(
        'Toplam Net Gelir',
        'Total Net Income',
        'Całkowity dochód netto',
      );
  static String get pdfSummaryVat => _p(
        'Toplam Ödenen VAT',
        'Total VAT Paid',
        'Całkowity zapłacony VAT',
      );
  static String get pdfSummaryNetProfit => _p(
        'Toplam Net Kâr',
        'Total Net Profit',
        'Całkowity zysk netto',
      );

  static String updateAvailable(String latest) => _p(
        'Yeni sürüm mevcut: $latest',
        'New version available: $latest',
        'Dostępna nowa wersja: $latest',
      );
  static String get updateDownload => _p('İndir', 'Download', 'Pobierz');

  static List<String> get months {
    switch (_lang) {
      case AppLang.tr:
        return [
          '', 'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
          'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
        ];
      case AppLang.en:
        return [
          '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
      case AppLang.pl:
        return [
          '', 'Sty', 'Lut', 'Mar', 'Kwi', 'Maj', 'Cze',
          'Lip', 'Sie', 'Wrz', 'Paź', 'Lis', 'Gru',
        ];
    }
  }

  static List<String> get monthsFull {
    switch (_lang) {
      case AppLang.tr:
        return [
          '', 'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
          'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
        ];
      case AppLang.en:
        return [
          '', 'January', 'February', 'March', 'April', 'May', 'June',
          'July', 'August', 'September', 'October', 'November', 'December',
        ];
      case AppLang.pl:
        return [
          '', 'Styczeń', 'Luty', 'Marzec', 'Kwiecień', 'Maj', 'Czerwiec',
          'Lipiec', 'Sierpień', 'Wrzesień', 'Październik', 'Listopad', 'Grudzień',
        ];
    }
  }

  static String _p(String tr, String en, String pl) {
    switch (_lang) {
      case AppLang.tr:
        return tr;
      case AppLang.en:
        return en;
      case AppLang.pl:
        return pl;
    }
  }
}
