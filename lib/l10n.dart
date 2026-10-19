import 'dart:ui';
import 'earnings_models.dart';

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
  static String get settings => _p('AYARLAR', 'SETTINGS', 'USTAWIENIA');
  static String get settingsTitle => _p('Ayarlar', 'Settings', 'Ustawienia');
  static String get settingsDriving =>
      _p('SÜRÜŞ VE SAYAÇLAR', 'DRIVING & COUNTERS', 'JAZDA I LICZNIKI');
  static String get settingsOverlay => _p('BALONCUK', 'OVERLAY PILL', 'DYMEK');
  static String get settingsPreferences => _p(
    'UYGULAMA VE TERCİHLER',
    'APP & PREFERENCES',
    'APLIKACJA I PREFERENCJE',
  );
  static String get settingsSystem =>
      _p('SİSTEM VE DESTEK', 'SYSTEM & SUPPORT', 'SYSTEM I POMOC');
  static String get drivingMode =>
      _p('Sürüş Modu', 'Driving Mode', 'Tryb jazdy');
  static String get acceptRate =>
      _p('KABUL ORANI', 'ACCEPT RATE', 'AKCEPTACJA %');
  static String get cancelRate =>
      _p('İPTAL ORANI', 'CANCEL RATE', 'ANULOWANIE %');
  static String formatPercent(String val) => _p('%$val', '$val%', '$val%');
  static String get accepted => _p('Kabul Edilen', 'Accepted', 'Zaakceptowane');
  static String get rejected => _p('Reddedilen', 'Rejected', 'Odrzucone');
  static String get completed => _p('Tamamlanan', 'Completed', 'Ukończone');
  static String get cancelled => _p('İptal Edilen', 'Cancelled', 'Anulowane');
  static String get autoCompleteTrips =>
      _p('Otomatik tamamla', 'Auto-complete trips', 'Automatyczne ukończenie');
  static String get keepScreenOn =>
      _p('Ekranı açık tut', 'Keep screen on', 'Nie wygaszaj ekranu');
  static String get overlayPillOrientation =>
      _p('Baloncuk Yönü', 'Bubble direction', 'Kierunek dymka');
  static String get overlayPillHorizontal =>
      _p('Yatay', 'Horizontal', 'Poziomy');
  static String get overlayPillVertical => _p('Dikey', 'Vertical', 'Pionowy');
  static String get overlayBubbleLetter => _p('R', 'R', 'R');
  static String get overlayCollapse =>
      _p('Baloncuğu küçült', 'Collapse bubble', 'Zwiń dymek');
  static String get overlayExpand =>
      _p('Baloncuğu aç', 'Expand bubble', 'Rozwiń dymek');
  static String get overlayShowCancelButton => _p(
    'Baloncukta İptal Butonu Göster',
    'Show cancellation button in overlay',
    'Pokaż przycisk anulowania na dymku',
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
  static String get openSettings =>
      _p('AYARLARA GİT', 'OPEN SETTINGS', 'OTWÓRZ USTAWIENIA');
  static String get notificationControls => _p(
    'Bildirim kontrolleri',
    'Notification controls',
    'Sterowanie z powiadomienia',
  );
  static String get notificationControlsHint => _p(
    'Baloncuk açıkken bildirim panelini aşağı çek: Kabul +1 / Red +1 ve güncel kabul oranı.',
    'While the bubble is open, pull down the notification shade: Accept +1 / Reject +1 and the live acceptance rate.',
    'Gdy dymek jest otwarty, rozwiń panel powiadomień: Akceptuj +1 / Odrzuć +1 i bieżący wskaźnik akceptacji.',
  );
  static String get notificationControlsDialogTitle => _p(
    'Bildirim İzni Gerekli',
    'Notification Permission Needed',
    'Wymagane uprawnienie do powiadomień',
  );
  static String get notificationControlsDialogDesc => _p(
    'Sayaç düğmeleri baloncuğun bildiriminde durur. Android bu bildirimi ancak izin verirsen gösterir. Bildirimde sadece kabul oranı ve sayılar olur; kilit ekranında görünmez, kazanç bilgisi içermez.',
    'The counter buttons live on the bubble\'s notification. Android only shows it if you allow notifications. It contains only the acceptance rate and counts — never earnings — and stays hidden on the lock screen.',
    'Przyciski licznika są w powiadomieniu dymka. Android pokaże je tylko po zezwoleniu na powiadomienia. Zawiera wyłącznie wskaźnik akceptacji i liczby — bez zarobków — i nie pojawia się na ekranie blokady.',
  );
  static String get notificationControlsContinue =>
      _p('DEVAM', 'CONTINUE', 'DALEJ');
  static String get notificationControlsDeniedTitle => _p(
    'Bildirim kontrolleri kapalı',
    'Notification controls are off',
    'Sterowanie z powiadomienia wyłączone',
  );
  static String get notificationControlsDeniedDesc => _p(
    'Bildirim izni verilmediği için bu ayar kapalı kaldı. Ayarlar\'dan RateHelper bildirimlerine izin verip ayarı tekrar açabilirsin.',
    'Notifications are not allowed, so this setting stayed off. Allow RateHelper notifications in Settings, then switch it on again.',
    'Powiadomienia nie są dozwolone, więc ustawienie pozostało wyłączone. Zezwól na powiadomienia RateHelper w Ustawieniach i włącz je ponownie.',
  );
  static String get hidePill => _p(
    'Yüzen baloncuğu gizle (Sadece bildirim paneli)',
    'Hide floating pill (Notification shade only)',
    'Ukryj pływającą pigułkę (Tylko pasek powiadomień)',
  );
  static String get hidePillHint => _p(
    'Ekranda baloncuk göstermez, kontroller yalnızca bildirim panelinde kalır.',
    'Hides the on-screen bubble and keeps controls only in the notification shade.',
    'Ukrywa dymek na ekranie i zostawia przyciski tylko w panelu powiadomień.',
  );
  static String get contactDeveloper =>
      _p('Geliştiriciyle İletişim', 'Contact developer', 'Kontakt z autorem');
  static String get contactDeveloperWhatsApp => 'Emirhan Metin • WhatsApp';
  static String get contactDeveloperGitHub => 'Emirhan Metin • GitHub';
  static String get contactDeveloperPrefill => _p(
    'Merhaba Emirhan, RateHelper hakkında yazıyorum: ',
    'Hi Emirhan, I\'m writing about RateHelper: ',
    'Cześć Emirhan, piszę w sprawie aplikacji RateHelper: ',
  );
  static String get contactDeveloperFailed => _p(
    'Bağlantı açılamadı.',
    'Could not open the link.',
    'Nie udało się otworzyć linku.',
  );
  static String get fuelTitle =>
      _p('Orlen Yakıt Fiyatları', 'Orlen Fuel Prices', 'Ceny paliw Orlen');
  static String get fuelEntryHint => _p(
    'Kraków istasyonları · PB95 ve LPG',
    'Kraków stations · PB95 and LPG',
    'Stacje w Krakowie · PB95 i LPG',
  );
  static String get fuelSortCheapest => _p('En ucuz', 'Cheapest', 'Najtańsze');
  static String get fuelSortNearest => _p('En yakın', 'Nearest', 'Najbliższe');
  static String get fuelTabAdd => _p('Yakıt ekle', 'Add fuel', 'Dodaj paliwo');
  static String get fuelTabStations => _p('İstasyonlar', 'Stations', 'Stacje');
  static String get fuelBestCheapest =>
      _p('EN UCUZ İSTASYON', 'CHEAPEST STATION', 'NAJTAŃSZA STACJA');
  static String get fuelBestNearest =>
      _p('EN YAKIN İSTASYON', 'NEAREST STATION', 'NAJBLIŻSZA STACJA');
  static String get fuelThisWeek => _p('BU HAFTA', 'THIS WEEK', 'TEN TYDZIEŃ');
  static String fuelWeekSummary(int count, String total) => _p(
    '$count alım · $total PLN',
    count == 1 ? '1 purchase · $total PLN' : '$count purchases · $total PLN',
    '$count zakup(y) · $total PLN',
  );
  static String fuelAddButton(String amount) =>
      _p('Ekle · $amount PLN', 'Add · $amount PLN', 'Dodaj · $amount PLN');
  static String get fuelSplitHint => _p(
    'Fiş başkasıyla ortaksa toplamı gir, payın otomatik hesaplanır.',
    'Shared receipt? Enter the total and your share is worked out.',
    'Wspólny paragon? Wpisz całość, a Twój udział zostanie wyliczony.',
  );
  static String get fuelPb95 => 'PB95';
  static String get fuelLpg => 'LPG';
  static String get fuelPb95Long =>
      _p('PB95 (Benzin)', 'PB95 (Petrol)', 'PB95 (Benzyna)');
  static String get fuelLpgLong =>
      _p('LPG (Otogaz)', 'LPG (Autogas)', 'LPG (Autogaz)');
  static String get fuelNoPrice => _p('Fiyat yok', 'No price yet', 'Brak ceny');
  static String get fuelNoLpg => _p('LPG yok', 'No LPG', 'Brak LPG');
  static String fuelUpdatedAgo(Duration age) {
    if (age.inMinutes < 1) return _p('az önce', 'just now', 'przed chwilą');
    if (age.inHours < 1) {
      final m = age.inMinutes;
      return _p('$m dk önce', '$m min ago', '$m min temu');
    }
    if (age.inDays < 1) {
      final h = age.inHours;
      return _p(
        '$h saat önce',
        h == 1 ? '1 hour ago' : '$h hours ago',
        '$h godz. temu',
      );
    }
    final d = age.inDays;
    return _p(
      '$d gün önce',
      d == 1 ? '1 day ago' : '$d days ago',
      d == 1 ? '1 dzień temu' : '$d dni temu',
    );
  }

  static String fuelPricesFetchedAgo(String ago) =>
      _p('Fiyatlar alındı: $ago', 'Prices fetched $ago', 'Ceny pobrane $ago');
  static String get fuelDirections => _p('Yol tarifi', 'Directions', 'Nawiguj');
  static String get fuelNavigateWith =>
      _p('Navigasyon uygulaması', 'Navigate with', 'Nawiguj przez');
  static String get fuelGoogleMaps => 'Google Maps';
  static String get fuelWaze => 'Waze';
  static String get fuelOpenNavFailed => _p(
    'Navigasyon açılamadı.',
    'Could not open navigation.',
    'Nie udało się otworzyć nawigacji.',
  );
  static String get fuelUpdatePrice =>
      _p('Fiyat bildir', 'Report price', 'Zgłoś cenę');
  static String get fuelSubmitPrompt => _p(
    'Pompadaki fiyatı gir (PLN/litre). Yönetici onayından sonra herkese görünür.',
    'Enter the pump price (PLN/litre). It goes public after admin approval.',
    'Wpisz cenę z dystrybutora (PLN/litr). Pojawi się po akceptacji administratora.',
  );
  static String get fuelPriceLabel =>
      _p('Fiyat (PLN)', 'Price (PLN)', 'Cena (PLN)');
  static String get fuelPriceEmpty =>
      _p('Bir fiyat gir.', 'Enter a price.', 'Wpisz cenę.');
  static String get fuelPriceNotANumber => _p(
    'Sadece rakam gir, örn. 6.29',
    'Numbers only, e.g. 6.29',
    'Tylko liczby, np. 6,29',
  );
  static String get fuelPriceTooPrecise => _p(
    'En fazla 2 ondalık basamak.',
    'At most 2 decimal places.',
    'Najwyżej 2 miejsca po przecinku.',
  );
  static String fuelPriceOutOfRange(String min, String max) => _p(
    'Fiyat $min – $max PLN arasında olmalı.',
    'Price must be between $min and $max PLN.',
    'Cena musi mieścić się w zakresie $min – $max PLN.',
  );
  static String get fuelSubmit =>
      _p('ONAYA GÖNDER', 'SEND FOR APPROVAL', 'WYŚLIJ DO AKCEPTACJI');
  static String get fuelSubmitted => _p(
    'Gönderildi. Onaylanınca yayınlanacak, teşekkürler!',
    'Sent. It will be published once approved, thanks!',
    'Wysłano. Cena pojawi się po akceptacji, dzięki!',
  );
  static String get fuelSubmitInvalid => _p(
    'Sunucu bu fiyatı kabul etmedi.',
    'The server did not accept this price.',
    'Serwer nie przyjął tej ceny.',
  );
  static String get fuelSubmitRateLimited => _p(
    'Çok fazla gönderim. Biraz sonra tekrar dene.',
    'Too many submissions. Try again a bit later.',
    'Zbyt wiele zgłoszeń. Spróbuj ponownie za chwilę.',
  );
  static String get fuelSubmitFailed => _p(
    'Gönderilemedi. İnternet bağlantını kontrol et.',
    'Could not send. Check your connection.',
    'Nie udało się wysłać. Sprawdź połączenie.',
  );
  static String get fuelNotConfigured => _p(
    'Fiyat servisi bu sürümde ayarlı değil; istasyonlar ve yol tarifi çalışır.',
    'The price service is not set up in this build; stations and directions still work.',
    'Usługa cen nie jest skonfigurowana w tej wersji; stacje i nawigacja działają.',
  );
  static String get fuelLoadFailed => _p(
    'Fiyatlar güncellenemedi.',
    'Could not refresh prices.',
    'Nie udało się odświeżyć cen.',
  );
  static String get fuelCommunityNote => _p(
    'Fiyatlar sürücüler tarafından gönderilir ve onaydan sonra yayınlanır.',
    'Prices are sent by drivers and published after review.',
    'Ceny zgłaszają kierowcy, publikowane są po weryfikacji.',
  );
  static String get fuelLocating =>
      _p('Konum alınıyor…', 'Getting location…', 'Ustalanie lokalizacji…');
  static String get fuelLocationDenied => _p(
    'Konum izni yok; en yakın sıralaması yapılamıyor.',
    'No location permission, so Nearest cannot sort.',
    'Brak uprawnień do lokalizacji, nie można posortować wg odległości.',
  );
  static String get fuelLocationDisabled => _p(
    'Konum kapalı. Telefonda konumu aç.',
    'Location is off. Turn it on in the phone settings.',
    'Lokalizacja jest wyłączona. Włącz ją w ustawieniach telefonu.',
  );
  static String get fuelLocationUnavailable => _p(
    'Konum bulunamadı. Tekrar dene.',
    'Could not get a location. Try again.',
    'Nie udało się ustalić lokalizacji. Spróbuj ponownie.',
  );
  static String get shadeChannelName =>
      _p('Sayaç kontrolleri', 'Counter controls', 'Sterowanie licznikiem');
  static String shadeTitle(String percent) =>
      _p('Kabul oranı $percent', 'Acceptance $percent', 'Akceptacja $percent');
  static String shadeCounts(int accepted, int rejected) => _p(
    'Kabul: $accepted · Red: $rejected',
    'Accepted: $accepted · Rejected: $rejected',
    'Zaakceptowane: $accepted · Odrzucone: $rejected',
  );
  static String get shadeAccept => _p('Kabul +1', 'Accept +1', 'Akceptuj +1');
  static String get shadeReject => _p('Red +1', 'Reject +1', 'Odrzuć +1');
  static String get editCompletedTitle =>
      _p('Tamamlanan Sayısı', 'Completed Trips', 'Ukończone przejazdy');
  static String get editAcceptedTitle =>
      _p('Kabul Edilen Sayısı', 'Accepted Rides', 'Zaakceptowane zlecenia');
  static String get editRejectedTitle =>
      _p('Reddedilen Sayısı', 'Rejected Rides', 'Odrzucone zlecenia');
  static String get editCancelledTitle =>
      _p('İptal Edilen Sayısı', 'Cancelled Rides', 'Anulowane przejazdy');
  static String get save => _p('KAYDET', 'SAVE', 'ZAPISZ');

  static String recovery(int n, [double targetRate = 80.0]) {
    final targetStr = targetRate == targetRate.roundToDouble()
        ? targetRate.toStringAsFixed(0)
        : targetRate.toStringAsFixed(1);
    return _p(
      'Oranı %$targetStr üzerine çıkarmak için sıradaki $n isteği üst üste KABUL etmelisin.',
      'To exceed $targetStr%, ACCEPT the next $n requests in a row.',
      'Aby przekroczyć $targetStr%, zaakceptuj $n kolejnych zleceń z rzędu.',
    );
  }

  static String get safeButClose => _p(
    'Güvende ama sınırda: Birkaç ret üst üste gelirse kademeyi kaybedebilirsin.',
    'Safe but close: one bad string of rejects could drop you below requirement.',
    'Bezpiecznie, ale blisko: seria odrzuceń może obniżyć stawkę poniżej wymogu.',
  );

  static String maxAdditionalCancellations(int n) => _p(
    'Bu haftaki %5 iptal sınırını aşmadan en fazla $n iptal daha hakkın var.',
    'You can afford up to $n more cancellations without breaching the 5% limit.',
    'Możesz anulować jeszcze maksymalnie $n razy, nie przekraczając limitu 5%.',
  );

  static String get cancellationLimitExceeded => _p(
    'İptal oranın sınırın üzerinde, kademen risk altında.',
    'Your cancellation rate is over the limit, your tier is at risk.',
    'Twój wskaźnik anulowań przekracza limit, Twój próg jest zagrożony.',
  );

  static String get tripGoalTitle => _p(
    'Haftalık Yolculuk Hedefi',
    'Weekly Trip Goal',
    'Tygodniowy Cel Przejazdów',
  );

  static String _goalRangeLabel(int minTrips) {
    final tiers = activeDriverMode.rentalTiers;
    for (final tier in tiers) {
      if (tier.minTrips == minTrips) return rentalTierRangeLabel(tier);
    }
    return rentalTierRangeLabel(tiers.first);
  }

  static String tripGoalChip(int minTrips, double? reqRate) {
    final rangeStr = _goalRangeLabel(minTrips);
    if (reqRate == null) {
      return _p(
        'Hedef: $rangeStr yolculuk (Gereksinim Yok)',
        'Goal: $rangeStr rides (No Req.)',
        'Cel: $rangeStr przejazdów (Brak Wymag.)',
      );
    }
    final reqStr = reqRate.toStringAsFixed(0);
    return _p(
      'Hedef: $rangeStr yolculuk (Min. %$reqStr)',
      'Goal: $rangeStr rides (Min. $reqStr%)',
      'Cel: $rangeStr przejazdów (Min. $reqStr%)',
    );
  }

  static String tripGoalOption(int minTrips, double? reqRate) {
    final rangeStr = _goalRangeLabel(minTrips);
    if (reqRate == null) {
      return _p(
        '$rangeStr yolculuk (Gereksinim Yok)',
        '$rangeStr rides (No Requirement)',
        '$rangeStr przejazdów (Brak Wymagań)',
      );
    }
    final reqStr = reqRate.toStringAsFixed(0);
    return _p(
      '$rangeStr yolculuk (Min. %$reqStr Kabul)',
      '$rangeStr rides (Min. $reqStr% Accept)',
      '$rangeStr przejazdów (Min. $reqStr% Akcept.)',
    );
  }

  static String get driverModeDialogTitle => _p(
    'Aracı kaç kişi kullanıyor?',
    'How many drivers share the car?',
    'Ilu kierowców dzieli samochód?',
  );
  static String get driverModeSolo =>
      _p('Tek Sürücü', 'Single Driver', 'Jeden kierowca');
  static String get driverModePaired => _p(
    'İki Sürücü (Paylaşımlı)',
    'Two Drivers (Shared)',
    'Dwóch kierowców (Dzielony)',
  );
  static String get driverModeTrio => _p(
    'Üç Sürücü (Paylaşımlı)',
    'Three Drivers (Shared)',
    'Trzech kierowców (Dzielony)',
  );
  static String driverModeLabel(DriverMode mode) => switch (mode) {
    DriverMode.paired => _p(
      'Sürüş Modu: İki Sürücü ✏️',
      'Driving Mode: Two Drivers ✏️',
      'Tryb jazdy: Dwóch kierowców ✏️',
    ),
    DriverMode.trio => _p(
      'Sürüş Modu: Üç Sürücü ✏️',
      'Driving Mode: Three Drivers ✏️',
      'Tryb jazdy: Trzech kierowców ✏️',
    ),
    DriverMode.solo => _p(
      'Sürüş Modu: Tek Sürücü ✏️',
      'Driving Mode: Single Driver ✏️',
      'Tryb jazdy: Jeden kierowca ✏️',
    ),
  };
  static String get pairedTripsHint => _p(
    'İki sürücü modunda: sen ve ortağının birlikte yaptığı toplam yolculuk sayısı',
    'Two-driver mode: combined trips completed by you and your partner',
    'Tryb dwóch kierowców: łączna liczba przejazdów wykonana przez Ciebie i partnera',
  );
  static String sharedCarTotalSubtitle(String fee, int drivers) => drivers == 3
      ? _p(
          'Araç toplamı: $fee PLN (3 sürücü arası paylaşılıyor)',
          'Car total: $fee PLN (shared between 3 drivers)',
          'Razem za auto: $fee PLN (dzielone na 3 kierowców)',
        )
      : _p(
          'Araç toplamı: $fee PLN (2 sürücü arası paylaşılıyor)',
          'Car total: $fee PLN (shared between 2 drivers)',
          'Razem za auto: $fee PLN (dzielone na 2 kierowców)',
        );

  static String get resetWeek =>
      _p('HAFTAYI SIFIRLA', 'RESET WEEK', 'RESETUJ TYDZIEŃ');
  static String get resetWeekTitle =>
      _p('Haftayı Sıfırla', 'Reset Week', 'Resetuj Tydzień');
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
  static String get noTapHistoryTitle =>
      _p('Kayıt Yok', 'No Records', 'Brak zapisów');
  static String get noTapHistoryDesc => _p(
    'Widget üzerindeki + ve − tuşlarına bastığın her istek burada listelenir.',
    'Every request you log with the + and − buttons on the widget shows up here.',
    'Każde zlecenie zapisane przyciskami + i − na widżecie pojawi się tutaj.',
  );
  static String get noHistoryTitle =>
      _p('Arşiv Boş', 'Archive Empty', 'Archiwum puste');
  static String get noHistoryDesc => _p(
    'Haftayı her sıfırladığında o haftanın özeti burada saklanır.',
    'Each time you reset the week, that week’s summary is stored here.',
    'Za każdym razem, gdy resetujesz tydzień, jego podsumowanie trafia tutaj.',
  );
  static String get crashLogEmptyTitle =>
      _p('Kayıt Yok', 'No Entries', 'Brak wpisów');
  static String get tapHistoryClear => _p('Temizle', 'Clear', 'Wyczyść');
  static String get tapHistoryClearConfirm => _p(
    'Tüm kayıtlar silinecek. Emin misin?',
    'All tap records will be deleted. Are you sure?',
    'Wszystkie zapisy dotknięć zostaną usunięte. Na pewno?',
  );
  static String get weeklyArchiveClear => _p('Temizle', 'Clear', 'Wyczyść');
  static String get weeklyArchiveClearConfirm => _p(
    'Tüm haftalık kayıtlar silinecek. Emin misin?',
    'All weekly archive records will be deleted. Are you sure?',
    'Wszystkie cotygodniowe wpisy zostaną usunięte. Na pewno?',
  );
  static String get filterToday => _p('Bugün', 'Today', 'Dziś');
  static String get filterAll => _p('Tümü', 'All', 'Wszystko');
  static String get tapAcceptShort => _p('Kabul', 'Accept', 'Akceptacja');
  static String get tapRejectShort => _p('Red', 'Reject', 'Odrzucenie');
  static String get overlayOn =>
      _p('RateHelper Aktif', 'RateHelper Active', 'RateHelper Aktywny');
  static String get overlayOff =>
      _p('RateHelper Kapatıldı', 'RateHelper Closed', 'RateHelper Wyłączony');
  static String get overlayToggleFailed => _p(
    'Widget başlatılamadı. Tekrar deneyin.',
    'Failed to start widget. Try again.',
    'Nie udało się uruchomić widżetu. Spróbuj ponownie.',
  );
  static String get archiveAccept => _p('Kabul', 'Accept', 'Akceptacja');
  static String get archiveCancel => _p('İptal', 'Cancel', 'Anulowanie');
  static String archiveWeekSummary(int trips, int accepted, int rejected) => _p(
    'Yolculuk: $trips • Kabul: $accepted • Red: $rejected',
    'Trips: $trips • Accept: $accepted • Reject: $rejected',
    'Przejazdy: $trips • Akceptacja: $accepted • Odrzucenie: $rejected',
  );
  static String get archiveCompletedTrips =>
      _p('Tamamlanan Yolculuk', 'Completed Trips', 'Ukończone przejazdy');
  static String get archiveCancelledTrips =>
      _p('İptal Edilen Yolculuk', 'Cancelled Trips', 'Anulowane przejazdy');
  static String get archiveAcceptedRequests =>
      _p('Kabul Edilen İstek', 'Accepted Requests', 'Zaakceptowane zlecenia');
  static String get archiveRejectedRequests =>
      _p('Reddedilen İstek', 'Rejected Requests', 'Odrzucone zlecenia');
  static String get archiveTotalRequests =>
      _p('Toplam İstek', 'Total Requests', 'Wszystkie zlecenia');
  static String get archiveWeeklyGoal =>
      _p('Haftalık Hedef', 'Weekly Goal', 'Cel tygodniowy');
  static String get archiveGoalMet =>
      _p('Hedef Tuttu', 'Goal Met', 'Cel osiągnięty');
  static String get archiveGoalMissed =>
      _p('Hedef Tutmadı', 'Goal Missed', 'Cel nieosiągnięty');

  /// Acceptance target plus met/missed. [threshold] is already localized
  /// (`%80` / `80%`). Null means the tier had no acceptance requirement.
  static String archiveGoalLine(String? threshold, bool met) {
    final status = met ? archiveGoalMet : archiveGoalMissed;
    if (threshold == null || threshold.isEmpty) return status;
    return '$threshold • $status';
  }

  static String get overlayTitle =>
      _p('RateHelper Aktif', 'RateHelper Active', 'RateHelper Aktywny');
  static String get overlayContent => _p('Çalışıyor.', 'Running.', 'Działa.');

  static String get onboardingTitle =>
      _p('RateHelper Kurulumu', 'RateHelper Setup', 'Konfiguracja RateHelper');
  static String get onboardingIntro => _p(
    'RateHelper’in arka planda çalışabilmesi için iki Android iznine ihtiyacı var. Aşağıdaki adımları sırayla yap. Yolculuk ve kazanç verin cihazdan çıkmaz. Uygulama GitHub’a yalnızca sen izin verirsen ya da kendin istersen bağlanır.',
    'RateHelper needs two Android permissions to run in the background. Complete the steps below in order. Your trips and earnings stay on this device. The app contacts GitHub only when you allow it or ask.',
    'RateHelper potrzebuje dwóch uprawnień Androida, aby działać w tle. Wykonaj poniższe kroki po kolei. Twoje przejazdy i zarobki zostają na urządzeniu. Aplikacja łączy się z GitHubem tylko gdy na to pozwolisz albo o to poprosisz.',
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
  static String get stepOverlayCta =>
      _p('İZNİ AÇ', 'GRANT PERMISSION', 'NADAJ UPRAWNIENIE');
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
  static String get stepBatteryCta =>
      _p('AYARLARI AÇ', 'OPEN SETTINGS', 'OTWÓRZ USTAWIENIA');

  static String get finish => _p('BİTİR', 'FINISH', 'ZAKOŃCZ');
  static String get skip => _p('Atla', 'Skip', 'Pomiń');
  static String get setupGuide =>
      _p('Kurulum Rehberi', 'Setup Guide', 'Przewodnik konfiguracji');

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

  // --- First-run onboarding wizard ---

  static String onboardingStepOf(int step, int total) =>
      _p('Adım $step / $total', 'Step $step of $total', 'Krok $step z $total');

  static String get onboardingContinue => _p('DEVAM', 'CONTINUE', 'DALEJ');
  static String get onboardingBack => _p('GERİ', 'BACK', 'WSTECZ');
  static String get onboardingOpenRateHelper =>
      _p('RATEHELPER’I AÇ', 'OPEN RATEHELPER', 'OTWÓRZ RATEHELPER');
  static String get onboardingCloseGuide => _p('KAPAT', 'CLOSE', 'ZAMKNIJ');
  static String get onboardingLanguageSelector =>
      _p('Dil seç', 'Choose language', 'Wybierz język');

  static String languageName(AppLang lang) => switch (lang) {
    AppLang.tr => 'Türkçe',
    AppLang.en => 'English',
    AppLang.pl => 'Polski',
  };

  // Welcome step
  static String get onboardingWelcomeTitle => _p(
    'RateHelper’e hoş geldin',
    'Welcome to RateHelper',
    'Witaj w RateHelper',
  );
  static String get onboardingWelcomeLead => _p(
    'Vardiyanı tek ekrandan yönet: istekler, oranlar, kazanç ve pratik araçlar.',
    'Run your shift from one screen: requests, rates, earnings and handy tools.',
    'Zarządzaj zmianą z jednego ekranu: zlecenia, wskaźniki, zarobki i przydatne narzędzia.',
  );
  static String get onboardingFeatureRequestsTitle =>
      _p('İstekleri takip et', 'Track every request', 'Śledź każde zlecenie');
  static String get onboardingFeatureRequestsBody => _p(
    'Kabul edilen, reddedilen, tamamlanan ve iptal edilen istekleri tek dokunuşla kaydet.',
    'Log accepted, rejected, completed and cancelled requests with a single tap.',
    'Zapisuj zaakceptowane, odrzucone, ukończone i anulowane zlecenia jednym dotknięciem.',
  );
  static String get onboardingFeatureRatesTitle =>
      _p('Oranlarını izle', 'Monitor your rates', 'Kontroluj wskaźniki');
  static String get onboardingFeatureRatesBody => _p(
    'Kabul ve iptal yüzdelerini anlık gör; hedefinin altına düşmeden takip et.',
    'See acceptance and cancellation percentages live, before they drop below your target.',
    'Widz na bieżąco wskaźniki akceptacji i anulowań, zanim spadną poniżej celu.',
  );
  static String get onboardingFeatureOverlayTitle => _p(
    'Uygulamanın üzerinde kontrol',
    'Controls over your app',
    'Sterowanie nad aplikacją',
  );
  static String get onboardingFeatureOverlayBody => _p(
    'Uber Driver veya Bolt Driver açıkken yüzen baloncuk ile saymaya devam et.',
    'Keep counting with the floating pill while Uber Driver or Bolt Driver is open.',
    'Licz dalej przez pływający dymek, gdy Uber Driver lub Bolt Driver jest otwarte.',
  );
  static String get onboardingFeatureAltControlsTitle => _p(
    'Direksiyon veya bildirim',
    'Steering wheel or notifications',
    'Kierownica lub powiadomienia',
  );
  static String get onboardingFeatureAltControlsBody => _p(
    'İsteğe bağlı olarak direksiyon tuşlarını veya bildirim panelindeki butonları kullan.',
    'Optionally count with steering-wheel buttons or the notification-shade buttons.',
    'Opcjonalnie licz przyciskami kierownicy lub przyciskami w panelu powiadomień.',
  );
  static String get onboardingFeatureToolsTitle => _p(
    'Yakıt, kazanç, kayıt ve Radar',
    'Fuel, earnings, records and Radar',
    'Paliwo, zarobki, zapisy i Radar',
  );
  static String get onboardingFeatureToolsBody => _p(
    'Orlen yakıt fiyatları, kazanç takibi, haftalık kayıtlar ve etkinlik radarı bir arada.',
    'Orlen fuel prices, earnings tracking, weekly records and the event radar in one place.',
    'Ceny paliw Orlen, śledzenie zarobków, zapisy tygodniowe i radar wydarzeń w jednym miejscu.',
  );
  static String get onboardingFeatureLocalTitle => _p(
    'Verin cihazında kalır',
    'Your data stays on your device',
    'Dane zostają na urządzeniu',
  );
  static String get onboardingFeatureLocalBody => _p(
    'Yolculuk ve kazanç kayıtları cihazda saklanır. Ağ ve paylaşım özellikleri senin kontrolünde çalışır.',
    'Trip and earnings records are stored on this device. Network and sharing features run under your control.',
    'Zapisy przejazdów i zarobków są przechowywane na urządzeniu. Funkcje sieciowe i udostępnianie działają pod Twoją kontrolą.',
  );

  // Overlay permission step
  static String get onboardingOverlayTitle => _p(
    'Yüzen kontroller için izin',
    'Permission for floating controls',
    'Uprawnienie do pływających kontrolek',
  );
  static String get onboardingOverlayLead => _p(
    'RateHelper’in Uber Driver veya Bolt Driver ekranının üzerinde görünmesi için Android’in “Diğer uygulamaların üzerinde göster” iznine ihtiyacı var.',
    'For RateHelper to appear over Uber Driver or Bolt Driver, Android needs the “Display over other apps” permission.',
    'Aby RateHelper pojawiał się nad Uber Driver lub Bolt Driver, Android potrzebuje uprawnienia „Wyświetlanie nad innymi aplikacjami”.',
  );
  static String get onboardingOverlayWhatTitle =>
      _p('Bu izin nedir?', 'What is this permission?', 'Co to za uprawnienie?');
  static String get onboardingOverlayWhatBody => _p(
    'Android’in küçük bir kontrol penceresinin başka bir uygulamanın üzerinde görünmesine izin verdiği ayardır. RateHelper diğer uygulamanın ekranını okumaz.',
    'It is the Android setting that lets a small control window appear over another app. RateHelper does not read the other app’s screen.',
    'To ustawienie Androida, które pozwala małemu okienku sterowania pojawić się nad inną aplikacją. RateHelper nie odczytuje ekranu innej aplikacji.',
  );
  static String get onboardingOverlayWhyTitle =>
      _p('Neden gerekli?', 'Why is it needed?', 'Dlaczego jest potrzebne?');
  static String get onboardingOverlayWhyBody => _p(
    'Baloncuk ancak bu izinle Uber/Bolt ekranının üzerinde kalabilir. İzin verilmezse sayaçlar ve diğer bölümler yine çalışır; yalnızca yüzen kontroller görünmez.',
    'The pill can stay over Uber/Bolt only with this permission. Without it, counters and the rest of the app still work; only the floating controls are hidden.',
    'Dymek może pozostać nad Uber/Bolt tylko z tym uprawnieniem. Bez niego liczniki i reszta aplikacji nadal działają; ukryte są tylko pływające kontrolki.',
  );
  static String get onboardingOverlayHowTitle =>
      _p('Nasıl açılır?', 'How to enable it', 'Jak je włączyć');
  static String get onboardingOverlayHowStep1 => _p(
    'Aşağıdaki butona dokun.',
    'Tap the button below.',
    'Dotknij przycisku poniżej.',
  );
  static String get onboardingOverlayHowStep2 => _p(
    'Açılan listede RateHelper’i bul.',
    'In the list that opens, find RateHelper.',
    'Na otwartej liście znajdź RateHelper.',
  );
  static String get onboardingOverlayHowStep3 => _p(
    '“Diğer uygulamaların üzerinde göster” seçeneğini aç.',
    'Turn on “Display over other apps”.',
    'Włącz „Wyświetlanie nad innymi aplikacjami”.',
  );
  static String get onboardingOverlayHowStep4 => _p(
    'RateHelper’e geri dön; izin durumu otomatik yenilenir.',
    'Return to RateHelper; the permission status refreshes automatically.',
    'Wróć do RateHelper; status uprawnienia odświeży się automatycznie.',
  );
  static String get onboardingPermissionGranted =>
      _p('İzin verildi', 'Permission granted', 'Uprawnienie nadane');
  static String get onboardingPermissionGrantedBody => _p(
    'Yüzen kontrolleri Uber ve Bolt üzerinde kullanabilirsin.',
    'You can now use the floating controls over Uber and Bolt.',
    'Możesz teraz używać pływających kontrolek nad Uberem i Boltem.',
  );
  static String get onboardingPermissionMissing =>
      _p('İzin verilmedi', 'Permission not granted', 'Brak uprawnienia');
  static String get onboardingPermissionMissingBody => _p(
    'Yüzen kontroller görünmeyecek. İzni açtıktan sonra bu ekrana dön; durum otomatik yenilenir.',
    'Floating controls will not appear. After enabling the permission, return to this screen; the status refreshes automatically.',
    'Pływające kontrolki się nie pojawią. Po włączeniu uprawnienia wróć na ten ekran; status odświeży się automatycznie.',
  );
  static String get onboardingPermissionChecking => _p(
    'İzin durumu kontrol ediliyor…',
    'Checking permission…',
    'Sprawdzanie uprawnienia…',
  );
  static String get onboardingOpenPermissionSettings =>
      _p('AYARLARI AÇ', 'OPEN SETTINGS', 'OTWÓRZ USTAWIENIA');
  static String get onboardingOverlayUnavailable => _p(
    'İzin yokken yüzen baloncuk ve yalnızca bildirim paneli modu kullanılamaz.',
    'Without the permission, the floating pill and shade-only mode are unavailable.',
    'Bez uprawnienia pływający dymek i tryb tylko z powiadomień są niedostępne.',
  );

  // Battery reliability step
  static String get onboardingBatteryTitle => _p(
    'Arka planda güvenilirlik',
    'Background reliability',
    'Niezawodność w tle',
  );
  static String get onboardingBatteryLead => _p(
    'Android’in pil tasarrufu, yüzen kontrolleri veya arka plan sayaçlarını durdurabilir. Vardiya sırasında kapanmaması için telefonunun ayarını bir kez kontrol et.',
    'Android battery saving can stop the floating controls or background counters. Check your phone’s setting once so it keeps working during a shift.',
    'Oszczędzanie baterii Androida może zatrzymać pływające kontrolki lub liczniki w tle. Sprawdź raz ustawienie telefonu, aby działało podczas zmiany.',
  );
  static String get onboardingBatterySystemStatus =>
      _p('SİSTEM DURUMU', 'SYSTEM STATUS', 'STATUS SYSTEMU');
  static String get onboardingBatteryVerified => _p(
    'Pil optimizasyonu kapalı görünüyor',
    'Battery optimization is unrestricted',
    'Optymalizacja baterii wyłączona',
  );
  static String get onboardingBatteryVerifiedBody => _p(
    'Android, bu uygulama için pil optimizasyonunu kapalı bildiriyor. Üreticiye özel arka plan kısıtlamaları yine açık olabilir; aşağıdaki adımları da kontrol et.',
    'Android reports battery optimization is off for this app. Manufacturer-specific background limits may still apply, so also check the steps below.',
    'Android zgłasza, że optymalizacja baterii jest wyłączona dla tej aplikacji. Ograniczenia producenta mogą nadal działać, więc sprawdź też kroki poniżej.',
  );
  static String get onboardingBatteryNotVerified => _p(
    'Pil ayarı doğrulanmadı',
    'Battery setting not confirmed',
    'Ustawienie baterii niepotwierdzone',
  );
  static String get onboardingBatteryNotVerifiedBody => _p(
    'Android, bu uygulamayı hâlâ pil optimizasyonuna tabi tutuyor olabilir. Aşağıdaki adımlarla ayarı kendin kontrol et.',
    'Android may still be optimizing this app. Check the setting yourself with the steps below.',
    'Android może nadal optymalizować tę aplikację. Sprawdź ustawienie samodzielnie, wykonując kroki poniżej.',
  );
  static String get onboardingBatteryChecking => _p(
    'Pil durumu kontrol ediliyor…',
    'Checking battery status…',
    'Sprawdzanie stanu baterii…',
  );
  static String get onboardingBatteryBrandLabel => _p(
    'Telefon markanı seç',
    'Choose your phone brand',
    'Wybierz markę telefonu',
  );
  static String get onboardingBatteryBrandNote => _p(
    'Marka seçimi yalnızca doğru talimatları gösterir; ayarın tamamlandığını kanıtlamaz.',
    'Choosing a brand only shows the right instructions; it does not prove the setting is complete.',
    'Wybór marki pokazuje tylko właściwe instrukcje; nie potwierdza wykonania ustawienia.',
  );
  static String get onboardingBatteryManualNote => _p(
    'Ayarları açtıktan sonra listede RateHelper’i bul ve kısıtlamayı kaldır. Geri döndüğünde sistem durumu yeniden kontrol edilir.',
    'After opening settings, find RateHelper in the list and remove the restriction. When you return, the system status is checked again.',
    'Po otwarciu ustawień znajdź RateHelper na liście i usuń ograniczenie. Po powrocie status systemu zostanie sprawdzony ponownie.',
  );
  static String get onboardingBatteryOpenSettings =>
      _p('PİL AYARLARI', 'BATTERY SETTINGS', 'USTAWIENIA BATERII');
  static String get onboardingOpenAppInfo =>
      _p('UYGULAMA BİLGİSİ', 'APP INFO', 'INFORMACJE O APLIKACJI');

  // Optional features step
  static String get onboardingOptionalTitle =>
      _p('İsteğe bağlı özellikler', 'Optional features', 'Funkcje opcjonalne');
  static String get onboardingOptionalLead => _p(
    'Bu adımdaki hiçbir şey zorunlu değil. İstediğin özelliği daha sonra Ayarlar’dan açıp kapatabilirsin.',
    'Nothing on this step is required. You can turn any feature on or off later in Settings.',
    'Nic na tym etapie nie jest wymagane. Każdą funkcję możesz później włączyć lub wyłączyć w Ustawieniach.',
  );
  static String get onboardingOptionalBadge =>
      _p('İSTEĞE BAĞLI', 'OPTIONAL', 'OPCJONALNE');
  static String get onboardingOptionalSteeringTitle => _p(
    'Direksiyon tuşları',
    'Steering-wheel buttons',
    'Przyciski kierownicy',
  );
  static String get onboardingOptionalSteeringBody => _p(
    'Direksiyondaki sonraki şarkı tuşuna basılı tutarak sayabilirsin. Android Erişilebilirlik izni gerekir; izin yalnızca Ayarlar’dan bu özelliği açtığında istenir.',
    'Count by holding the next-track button on the steering wheel. This needs Android Accessibility permission, requested only when you enable the feature in Settings.',
    'Licz, przytrzymując przycisk następnego utworu na kierownicy. Wymaga to uprawnienia dostępności Androida, o które aplikacja poprosi dopiero po włączeniu funkcji w Ustawieniach.',
  );
  static String get onboardingOptionalNotificationsTitle =>
      _p('Bildirim paneli', 'Notification shade', 'Panel powiadomień');
  static String get onboardingOptionalNotificationsBody => _p(
    'Bildirim panelinden Kabul +1 / Red +1 kullanabilirsin. Android bildirim izni yalnızca bu ayarı açtığında istenir.',
    'Use Accept +1 / Reject +1 from the notification shade. Android notification permission is requested only when you turn this on.',
    'Używaj Akceptuj +1 / Odrzuć +1 z panelu powiadomień. Uprawnienie do powiadomień jest wymagane tylko po włączeniu tej opcji.',
  );
  static String get onboardingOptionalPillTitle =>
      _p('Baloncuk görünümü', 'Pill appearance', 'Wygląd dymka');
  static String get onboardingOptionalPillBody => _p(
    'Yatay veya dikey yönü ve iptal butonunu Ayarlar → Baloncuk bölümünden seç.',
    'Choose horizontal or vertical orientation and the cancel button in Settings → Overlay.',
    'Wybierz kierunek poziomy lub pionowy oraz przycisk anulowania w Ustawieniach → Dymek.',
  );
  static String get onboardingOptionalToolsTitle => _p(
    'Yakıt, kazanç ve kayıtlar',
    'Fuel, earnings and records',
    'Paliwo, zarobki i zapisy',
  );
  static String get onboardingOptionalToolsBody => _p(
    'Orlen yakıt fiyatları, kazanç hesapları ve haftalık kayıtlar alt menüden açılır.',
    'Orlen fuel prices, earnings calculations and weekly records open from the bottom bar.',
    'Ceny paliw Orlen, obliczenia zarobków i zapisy tygodniowe otwierają się z dolnego paska.',
  );
  static String get onboardingOptionalRadarTitle =>
      _p('Etkinlik Radarı', 'Event Radar', 'Radar wydarzeń');
  static String get onboardingOptionalRadarBody => _p(
    'Kraków’daki etkinlikleri ve yoğun talep dönemlerini görmek için Radar’ı kullan.',
    'Use Radar to see events and high-demand periods in Kraków.',
    'Użyj Radaru, aby zobaczyć wydarzenia i okresy dużego popytu w Krakowie.',
  );

  // Ready step
  static String get onboardingReadyTitle =>
      _p('Sürüşe hazırsın', 'Ready to drive', 'Gotowy do jazdy');
  static String get onboardingReadyLead => _p(
    'Kurulum özetin aşağıda. Eksik kalan bir şey varsa sonra Ayarlar’dan tamamlayabilirsin.',
    'Here is your setup summary. If anything is missing, you can finish it later in Settings.',
    'Oto podsumowanie konfiguracji. Jeśli czegoś brakuje, możesz to dokończyć później w Ustawieniach.',
  );
  static String get onboardingSummaryTitle =>
      _p('Kurulum özeti', 'Setup summary', 'Podsumowanie konfiguracji');
  static String get onboardingSummaryOverlay =>
      _p('Yüzen kontroller', 'Floating controls', 'Pływające kontrolki');
  static String get onboardingSummaryBattery => _p(
    'Arka plan güvenilirliği',
    'Background reliability',
    'Niezawodność w tle',
  );
  static String get onboardingSummaryOptional =>
      _p('İsteğe bağlı özellikler', 'Optional features', 'Funkcje opcjonalne');
  static String get onboardingSummaryGranted =>
      _p('İzin verildi', 'Granted', 'Nadano');
  static String get onboardingSummaryNotGranted =>
      _p('İzin yok', 'Not granted', 'Brak uprawnienia');
  static String get onboardingSummaryBatteryVerified =>
      _p('Optimizasyon kapalı', 'Unrestricted', 'Bez ograniczeń');
  static String get onboardingSummaryBatteryUnverified =>
      _p('Manuel kontrol et', 'Check manually', 'Sprawdź ręcznie');
  static String get onboardingSummaryOptionalValue => _p(
    'Ayarlar’dan açılabilir',
    'Available in Settings',
    'Dostępne w Ustawieniach',
  );
  static String get onboardingReadySettingsHint => _p(
    'Ayarlar’a ana ekrandaki dişli simgesinden ulaşabilirsin. Bu rehberi daha sonra Ayarlar → Kurulum Rehberi’nden yeniden açabilirsin.',
    'Open Settings from the gear icon on the home screen. You can reopen this guide later from Settings → Setup Guide.',
    'Otwórz Ustawienia ikoną koła zębatego na ekranie głównym. Ten przewodnik możesz ponownie otworzyć w Ustawieniach → Przewodnik konfiguracji.',
  );

  // Skip confirmation
  static String get onboardingSkipTitle => _p(
    'Kurulumu şimdi atla?',
    'Skip setup for now?',
    'Pominąć konfigurację?',
  );
  static String get onboardingSkipOverlayBody => _p(
    'Yüzen kontroller için izin verilmedi. Kurulumu atlarsan baloncuk Uber/Bolt üzerinde görünmez. Daha sonra Ayarlar → Kurulum Rehberi’nden izni açabilirsin.',
    'The floating-controls permission is not granted. If you skip setup, the pill will not appear over Uber/Bolt. You can enable it later from Settings → Setup Guide.',
    'Nie nadano uprawnienia do pływających kontrolek. Jeśli pominiesz konfigurację, dymek nie pojawi się nad Uber/Bolt. Możesz włączyć je później w Ustawieniach → Przewodnik konfiguracji.',
  );
  static String get onboardingSkipBatteryBody => _p(
    'Pil optimizasyonu doğrulanmadı. Android arka plan kontrollerini durdurabilir. Daha sonra Ayarlar → Kurulum Rehberi’nden kontrol edebilirsin.',
    'Battery optimization is not confirmed. Android may stop the background controls. You can check it later from Settings → Setup Guide.',
    'Optymalizacja baterii nie została potwierdzona. Android może zatrzymać kontrolki w tle. Możesz sprawdzić to później w Ustawieniach → Przewodnik konfiguracji.',
  );
  static String get onboardingSkipStay =>
      _p('KURULUMA DÖN', 'BACK TO SETUP', 'WRÓĆ DO KONFIGURACJI');
  static String get onboardingSkipConfirm =>
      _p('YİNE DE ATLA', 'SKIP ANYWAY', 'POMIŃ MIMO TO');

  // --- One-time pricing & feature-value survey (v1) ---

  static String get surveyLanguageSelector =>
      _p('Dil seç', 'Choose language', 'Wybierz język');
  static String get surveyTitle => _p(
    'RateHelper’ın Geleceği',
    'The Future of RateHelper',
    'Przyszłość RateHelper',
  );
  static String get surveyIntro => _p(
    'RateHelper şu anda tamamen ücretsiz. Geliştirmeye devam edebilmek için ileride aylık 15 PLN’lik isteğe bağlı bir sürüm düşünülüyor. Bu bir ödeme talebi değildir; hiçbir abonelik başlatılmaz.',
    'RateHelper is completely free today. To keep improving it, an optional 15 PLN per month version is being considered for the future. This is not a payment request; no subscription is started.',
    'RateHelper jest dziś całkowicie darmowy. Aby móc dalej go rozwijać, rozważana jest opcjonalna wersja za 15 zł miesięcznie. To nie jest prośba o płatność; nie uruchamiamy żadnej subskrypcji.',
  );
  static String get surveyAnonymousNote => _p(
    'Yanıtlar anonimdir; ad, telefon, e-posta, kazanç veya konum gönderilmez.',
    'Your answers are anonymous; no name, phone, email, earnings or location is sent.',
    'Odpowiedzi są anonimowe; nie wysyłamy imienia, telefonu, e-maila, zarobków ani lokalizacji.',
  );
  static String get surveyQuestion1 => _p(
    'RateHelper ayda 15 zł olsaydı kullanmaya devam eder miydin?',
    'If RateHelper cost 15 zł per month, would you continue using it?',
    'Gdyby RateHelper kosztował 15 zł miesięcznie, czy nadal korzystałbyś z aplikacji?',
  );
  static String get surveyContinueYes =>
      _p('Evet, kesinlikle.', 'Yes, definitely.', 'Tak, zdecydowanie.');
  static String get surveyContinueMaybe => _p(
    'Belki, özelliklere bağlı.',
    'Maybe, depending on the features.',
    'Może, w zależności od funkcji.',
  );
  static String get surveyContinueNo => _p(
    'Hayır, yalnızca ücretsiz sürümü kullanırdım.',
    'No, I would only use the free version.',
    'Nie, korzystałbym tylko z darmowej wersji.',
  );
  static String get surveyQuestion2 => _p(
    'Aylık olarak makul bulduğun fiyat nedir?',
    'What monthly price would you consider reasonable?',
    'Jaka miesięczna cena wydaje Ci się rozsądna?',
  );
  static String get surveyPrice5 => '5 zł';
  static String get surveyPrice10 => '10 zł';
  static String get surveyPrice15 => '15 zł';
  static String get surveyPrice20 => '20 zł';
  static String get surveyPrice25Plus =>
      _p('25 zł veya daha fazla', '25 zł or more', '25 zł lub więcej');
  static String get surveyPriceNotPay => _p(
    'Uygulama için ödeme yapmam.',
    'I would not pay for the application.',
    'Nie chcę płacić za aplikację.',
  );
  static String get surveyQuestion3 => _p(
    'Hangi RateHelper özelliği senin için en değerli?',
    'Which RateHelper feature is most valuable to you?',
    'Która funkcja RateHelper jest dla Ciebie najcenniejsza?',
  );
  static String get surveyFeatureOverlay => _p(
    'Yüzen baloncuk ve yolculuk sayaçları',
    'Floating overlay and trip counters',
    'Pływający dymek i liczniki przejazdów',
  );
  static String get surveyFeatureSteering => _p(
    'Direksiyon ve bildirim kontrolleri',
    'Steering-wheel and notification controls',
    'Sterowanie z kierownicy i powiadomień',
  );
  static String get surveyFeatureEarnings => _p(
    'Kazanç ve kira hesaplamaları',
    'Earnings and rental calculations',
    'Obliczenia zarobków i najmu',
  );
  static String get surveyFeatureFuel => _p(
    'ORLEN yakıt fiyatları ve yakıt kayıtları',
    'ORLEN fuel prices and fuel records',
    'Ceny paliw ORLEN i zapisy paliwa',
  );
  static String get surveyFeatureWeekly => _p(
    'Haftalık hedefler, arşivler ve raporlar',
    'Weekly goals, archives and reports',
    'Cele tygodniowe, archiwa i raporty',
  );
  static String get surveyFeatureOther =>
      _p('Diğer özellikler', 'Other features', 'Inne funkcje');
  static String surveyProgress(int answered) => _p(
    '$answered / 3 yanıtlandı',
    '$answered of 3 answered',
    '$answered z 3 odpowiedzi',
  );
  static String get surveyAnswerRequired => _p(
    'Göndermek için üç soruyu da yanıtla.',
    'Answer all three questions to submit.',
    'Aby wysłać, odpowiedz na wszystkie trzy pytania.',
  );
  static String get surveySubmit =>
      _p('YANITLARI GÖNDER', 'SUBMIT ANSWERS', 'WYŚLIJ ODPOWIEDZI');
  static String get surveySubmitting =>
      _p('GÖNDERİLİYOR…', 'SUBMITTING…', 'WYSYŁANIE…');
  static String get surveySuccessTitle =>
      _p('Teşekkürler!', 'Thank you!', 'Dziękujemy!');
  static String get surveySuccessBody => _p(
    'Yanıtların kaydedildi. Bu anket bir daha gösterilmeyecek.',
    'Your answers have been saved. This survey will not be shown again.',
    'Twoje odpowiedzi zostały zapisane. Ta ankieta nie pojawi się ponownie.',
  );
  static String get surveyQueuedTitle =>
      _p('Yanıtlar kaydedildi', 'Answers saved', 'Odpowiedzi zapisane');
  static String get surveyQueuedBody => _p(
    'Şu anda gönderilemedi. Yanıtların cihazda saklandı ve uygulama açıldığında yeniden denenecek. RateHelper’ı kullanmaya devam edebilirsin.',
    'Could not send right now. Your answers are stored on this device and will be retried when the app is next opened. You can continue using RateHelper.',
    'Nie udało się teraz wysłać. Odpowiedzi są zapisane na urządzeniu i zostaną ponowione przy następnym otwarciu aplikacji. Możesz dalej korzystać z RateHelper.',
  );
  static String get surveyErrorLocal => _p(
    'Yanıtlar kaydedilemedi. Lütfen tekrar dene.',
    'Could not save your answers. Please try again.',
    'Nie udało się zapisać odpowiedzi. Spróbuj ponownie.',
  );
  static String get surveyContinue => _p(
    'RATEHELPER’A DEVAM ET',
    'CONTINUE TO RATEHELPER',
    'PRZEJDŹ DO RATEHELPER',
  );

  static String get crashLogTitle =>
      _p('Çökme Kayıtları', 'Crash Log', 'Dziennik awarii');
  static String get crashLogEmpty => _p(
    'Henüz kayıt yok. Uygulama her şey yolundaysa burası boş kalır.',
    'No entries yet. If everything is working this stays empty.',
    'Brak wpisów. Jeśli wszystko działa, jest pusto.',
  );
  static String get crashLogCopy => _p('KOPYALA', 'COPY', 'KOPIUJ');
  static String get crashLogClear => _p('TEMİZLE', 'CLEAR', 'WYCZYŚĆ');
  static String get crashLogCopied =>
      _p('Panoya kopyalandı', 'Copied to clipboard', 'Skopiowano do schowka');

  static String get version => _p('Sürüm', 'Version', 'Wersja');
  static String get releaseName =>
      _p('2. Büyük Güncelleme', '2nd Major Update', '2. Duża Aktualizacja');
  static String get designer => _p('Tasarımcı', 'Designer', 'Projektant');

  static String get navLang => _p('Dil', 'Language', 'Język');
  static String get quickFuelNavLabel => _p('Yakıt', 'Fuel', 'Paliwo');
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
  static String get vat => _p('VAT (%12)', 'VAT (12%)', 'VAT (12%)');
  static String get settlementFee => _p(
    'Hesap Kesim Ücreti (%4.31)',
    'Settlement Fee (4.31%)',
    'Opłata rozliczeniowa (4.31%)',
  );
  static String get rental => _p('Kira', 'Rental', 'Wynajem');
  static String rentalComputed(String range, String value) => _p(
    'Kira (Kademe: $range): $value PLN',
    'Rental (Tier: $range): $value PLN',
    'Wynajem (Próg: $range): $value PLN',
  );
  static String get hasRentalDiscountToggle => _p(
    'Kira İndirimi Var mı?',
    'Rental Discount Active?',
    'Zniżka na wynajem?',
  );
  static String rentalNoDiscount(String value) => _p(
    'Kira (İndirimsiz): $value PLN',
    'Rental (No Discount): $value PLN',
    'Wynajem (Bez zniżki): $value PLN',
  );
  static String freeWeekProgress(int current, int total) => _p(
    'Ücretsiz Hafta İlerlemesi: $current / $total yolculuk',
    'Free Week Progress: $current / $total trips',
    'Postęp darmowego tygodnia: $current / $total przejazdów',
  );
  static String get freeWeekRewardBadge => _p(
    '🎉 Ücretsiz hafta hakkın var!',
    '🎉 You earned a free week!',
    '🎉 Masz prawo do darmowego tygodnia!',
  );
  static String freeWeekRewardBadgeCount(int count) => _p(
    '🎉 Ücretsiz hafta hakkın var! ($count adet)',
    '🎉 You earned free week(s)! ($count)',
    '🎉 Masz prawo do darmowego tygodnia! ($count)',
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
      _p('Kendi Yolculuk Sayın', 'Your Trip Count', 'Twoje Przejazdy');
  static String get driverTripCountLabel =>
      _p('Kendi Yolculuk Sayın', 'Your Trip Count', 'Twoje Przejazdy');
  static String carTripCountOverrideLabel(DriverMode mode) =>
      mode == DriverMode.trio
      ? _p(
          'Üç sürücünün toplamı (Kira için)',
          'Combined trips of 3 drivers (for rental)',
          'Łącznie 3 kierowców (do wynajmu)',
        )
      : _p(
          'Ortağınla Toplam (Kira için)',
          'Total with Partner (for rental)',
          'Łącznie z partnerem (do wynajmu)',
        );
  static String get carTripCountOverrideHint => _p(
    'Boş bırakırsan kendi sayınla aynı kabul edilir',
    'If left empty, assumed equal to your own trips',
    'Jeśli puste, przyjęta zostanie Twoja liczba przejazdów',
  );
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
  static String get requiredField => _p('Zorunlu', 'Required', 'Wymagane');
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
  static String weekCountLabel(int n) => _p('$n hafta', '$n weeks', '$n tyg.');
  static String get weekCountStat => _p('Hafta sayısı', 'Weeks', 'Tygodnie');

  // Records (rekorlar)
  static String get bestWeek =>
      _p('En İyi Hafta', 'Best Week', 'Najlepszy Tydzień');
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

  // PDF export
  static String get exportPdf =>
      _p('PDF Olarak Dışa Aktar', 'Export as PDF', 'Eksportuj do PDF');
  static String get exportPdfRangeTitle =>
      _p('Tarih Aralığı Seç', 'Select Date Range', 'Wybierz zakres dat');
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
  static String get exportShareText =>
      _p('Kazanç raporu', 'Earnings report', 'Raport zarobków');
  static String get exportPdfInProgress =>
      _p('PDF hazırlanıyor…', 'Preparing PDF…', 'Przygotowywanie PDF…');
  static String get exportFailed => _p(
    'PDF oluşturulamadı. Tekrar deneyin.',
    'Could not create the PDF. Try again.',
    'Nie udało się utworzyć PDF. Spróbuj ponownie.',
  );

  // PDF document content
  static String get pdfTitle =>
      _p('Kazanç Raporu', 'Earnings Report', 'Raport Zarobków');
  static String get pdfDriver => _p('Sürücü', 'Driver', 'Kierowca');
  static String get pdfDriverPlaceholder =>
      _p('__________________', '__________________', '__________________');

  // Driver name setup (PDF header)
  static String get driverNamePrompt => _p(
    'PDF raporunda görünmesi için adını girer misin?',
    'Enter your name so it appears on the PDF report',
    'Podaj swoje imię i nazwisko, aby pojawiło się w raporcie PDF',
  );
  static String get driverNameLabel =>
      _p('Ad Soyad', 'Full Name', 'Imię i nazwisko');
  static String get driverNameContinue =>
      _p('Devam Et', 'Continue', 'Kontynuuj');
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
  static String get pdfColVat => _p('VAT (%12)', 'VAT (12%)', 'VAT (12%)');
  static String get pdfColSettlementFee =>
      _p('Kesim Ücreti (%4.31)', 'Settlement (4.31%)', 'Rozliczenie (4.31%)');
  static String get pdfColNetProfit =>
      _p('Net Kâr', 'Net Profit', 'Zysk netto');
  static String get pdfColHourly =>
      _p('Saatlik Kazanç', 'Hourly', 'Stawka godz.');
  static String get pdfTotals => _p('TOPLAM', 'TOTAL', 'RAZEM');
  static String get pdfSummaryNetIncome =>
      _p('Toplam Net Gelir', 'Total Net Income', 'Całkowity dochód netto');
  static String get pdfSummaryVat => _p(
    'Toplam Ödenen VAT (%12)',
    'Total VAT Paid (12%)',
    'Całkowity zapłacony VAT (12%)',
  );
  static String get pdfSummaryNetProfit =>
      _p('Toplam Net Kâr', 'Total Net Profit', 'Całkowity zysk netto');

  static String updateAvailable(String latest) => _p(
    'Yeni sürüm mevcut: $latest',
    'New version available: $latest',
    'Dostępna nowa wersja: $latest',
  );
  static String get updateDownload => _p('İndir', 'Download', 'Pobierz');
  static String get updateCheckAction =>
      _p('Güncellemeleri Denetle', 'Check for updates', 'Sprawdź aktualizacje');
  static String updateLastCheckedLabel(DateTime? when) {
    if (when == null) {
      return _p(
        'Henüz kontrol edilmedi',
        'Not checked yet',
        'Jeszcze nie sprawdzono',
      );
    }
    final local = when.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final stamp = '$day.$month $hour:$minute';
    return _p(
      'Son kontrol: $stamp',
      'Last checked: $stamp',
      'Ostatnie sprawdzenie: $stamp',
    );
  }

  static String get autoUpdateCheck => _p(
    'Otomatik güncelleme denetimi',
    'Automatic update check',
    'Automatyczne sprawdzanie aktualizacji',
  );
  static String get autoFetchEvents => _p(
    'Etkinlikleri otomatik getir',
    'Fetch events automatically',
    'Pobieraj wydarzenia automatycznie',
  );
  static String get githubConsentBody => _p(
    'Uygulama güncelleme ve etkinlikler için GitHub’a kendiliğinden baksın mı?',
    'Allow the app to check GitHub for updates and events automatically?',
    'Pozwolić aplikacji automatycznie sprawdzać GitHub pod kątem aktualizacji i wydarzeń?',
  );
  static String get githubConsentAllow => _p('İzin ver', 'Allow', 'Zezwól');
  static String get githubConsentDeny => _p(
    'Hayır, yalnız ben isteyince',
    'No, only when I ask',
    'Nie, tylko gdy poproszę',
  );
  static String get updateChecking =>
      _p('Denetleniyor…', 'Checking…', 'Sprawdzanie…');
  static String get updateUpToDate => _p(
    'En güncel sürümü kullanıyorsunuz',
    'You are on the latest version',
    'Masz najnowszą wersję',
  );
  static String get updateUnreachable => _p(
    'Güncelleme sunucusuna ulaşılamadı',
    'Could not reach the update server',
    'Nie udało się połączyć z serwerem aktualizacji',
  );
  static String get updateNetworkError => _p(
    'Güncelleme sunucusuna ulaşılamadı. İnternet bağlantını kontrol et.',
    'Could not reach the update server. Check your internet connection.',
    'Nie udało się połączyć z serwerem aktualizacji. Sprawdź połączenie z internetem.',
  );
  static String get updateHttpError => _p(
    'Güncelleme sunucusu beklenmeyen bir yanıt döndürdü.',
    'The update server returned an unexpected response.',
    'Serwer aktualizacji zwrócił nieoczekiwaną odpowiedź.',
  );
  static String get updateInvalidJson => _p(
    'Güncelleme dosyası okunamadı (geçersiz JSON).',
    'The update file could not be read (invalid JSON).',
    'Nie można odczytać pliku aktualizacji (nieprawidłowy JSON).',
  );
  static String get updateInvalidManifest => _p(
    'Güncelleme bilgisi geçersiz veya eksik.',
    'The update information is invalid or incomplete.',
    'Informacje o aktualizacji są nieprawidłowe lub niekompletne.',
  );
  static String get updateDisabled => _p(
    'Güncelleme denetimi bu derlemede kapalı',
    'Update checks are disabled in this build',
    'Sprawdzanie aktualizacji jest wyłączone',
  );
  static String get updateLaunchFailed => _p(
    'İndirme başlatılamadı',
    'Could not start the download',
    'Nie udało się rozpocząć pobierania',
  );
  static String get updateAvailableTitle =>
      _p('Yeni Sürüm Hazır', 'New Version Ready', 'Nowa wersja gotowa');
  static String get updateMandatoryTitle =>
      _p('Zorunlu Güncelleme', 'Required Update', 'Wymagana aktualizacja');
  static String get updateNow =>
      _p('Şimdi Güncelle', 'Update Now', 'Aktualizuj teraz');
  static String get updateLater => _p('Daha Sonra', 'Later', 'Później');
  static String get updateSkipVersion =>
      _p('Bu sürümü atla', 'Skip this version', 'Pomiń tę wersję');
  static String get updateInstallHint => _p(
    'Güncelleme uygulama içinde indirilir, ardından Android kurulum ekranı açılır.',
    'The update downloads inside the app, then Android opens its installer.',
    'Aktualizacja pobiera się w aplikacji, następnie Android otworzy instalator.',
  );
  static String get updateDownloadingLabel =>
      _p('İndiriliyor', 'Downloading', 'Pobieranie');
  static String get updateInstallingLabel => _p(
    'Kurulum ekranı açılıyor',
    'Opening the installer',
    'Otwieranie instalatora',
  );
  static String updateProgressMb(String received, String total) => _p(
    '$received / $total MB',
    '$received / $total MB',
    '$received / $total MB',
  );
  static String get updateCancel => _p('İptal', 'Cancel', 'Anuluj');
  static String get updatePermissionTitle => _p(
    'Kurulum İzni Gerekli',
    'Install Permission Needed',
    'Potrzebne pozwolenie',
  );
  static String get updatePermissionBody => _p(
    'Android, güncellemeyi kurabilmek için RateHelper\'a izin vermenizi istiyor. '
        'Açılan ekranda izni açın, sonra geri dönüp tekrar deneyin.',
    'Android needs you to allow RateHelper to install updates. '
        'Turn the permission on, then come back and try again.',
    'Android wymaga zezwolenia dla RateHelper na instalację aktualizacji. '
        'Włącz pozwolenie, a następnie wróć i spróbuj ponownie.',
  );
  static String get updateGrantPermission =>
      _p('İzni Aç', 'Open Permission', 'Otwórz ustawienia');
  static String get updateSignatureMismatch => _p(
    'Güncelleme imzası uyuşmuyor, kurulum durduruldu',
    'Update signature does not match, installation stopped',
    'Podpis aktualizacji się nie zgadza, instalacja zatrzymana',
  );
  static String get updateInstallBlocked => _p(
    'Güncelleme doğrulanamadı, kurulum durduruldu',
    'The update could not be verified, installation stopped',
    'Nie udało się zweryfikować aktualizacji, instalacja zatrzymana',
  );
  static String get updateFellBackToBrowser => _p(
    'Uygulama içi indirme olmadı, tarayıcıda açılıyor',
    'In-app download failed, opening your browser',
    'Pobieranie w aplikacji nie udało się, otwieram przeglądarkę',
  );
  static String get updateInstalledLabel =>
      _p('Yüklü', 'Installed', 'Zainstalowana');
  static String get updateLatestLabel => _p('Yeni', 'Latest', 'Najnowsza');

  static String get add => _p('Ekle', 'Add', 'Dodaj');
  static String get quickAddFuel =>
      _p('Yakıt Ekle', 'Add Fuel', 'Dodaj paliwo');
  static String get quickAddFuelTitle =>
      _p('Hızlı Yakıt Ekle', 'Quick Add Fuel', 'Szybkie dodawanie paliwa');
  static String fuelAddedConfirmation(String amount, int count) => _p(
    'Yakıt eklendi: $amount PLN (Bu haftaki $count. alım)',
    'Fuel added: $amount PLN ($count. purchase this week)',
    'Dodano paliwo: $amount PLN ($count. zakup w tym tygodniu)',
  );
  static String get undo => _p('Geri Al', 'Undo', 'Cofnij');
  static String get receiptDeleted => _p('silindi', 'deleted', 'usunięto');
  static String get today => _p('Bugün', 'Today', 'Dzisiaj');
  static String get tomorrow => _p('Yarın', 'Tomorrow', 'Jutro');
  static String get fuelReceiptsTitle =>
      _p('Yakıt Alımları', 'Fuel Purchases', 'Zakupy paliwa');
  static String get addReceipt =>
      _p('+ Alım Ekle', '+ Add Receipt', '+ Dodaj zakup');
  static String get noFuelReceipts => _p(
    'Bu hafta henüz yakıt alımı eklenmedi.',
    'No fuel receipts added for this week yet.',
    'Nie dodano jeszcze zakupów paliwa w tym tygodniu.',
  );
  static String get totalPumpPaid =>
      _p('Toplam (Pompada):', 'Total (At Pump):', 'Razem (na stacji):');
  static String get totalFuelDiscounted => _p(
    'Toplam (%10 İndirimli):',
    'Total (10% Discounted):',
    'Razem (10% zniżki):',
  );
  static String get amountPaidLabel =>
      _p('Ödenen Tutar', 'Amount Paid', 'Zapłacona kwota');
  static String get fuelSplitToggle => _p('Paylaş', 'Split', 'Podziel');
  static String get fuelSplitPeopleLabel =>
      _p('Kaç kişi?', 'How many people?', 'Ile osób?');
  static String fuelSplitYourShare(String amount) => _p(
    'Senin payın: $amount PLN',
    'Your share: $amount PLN',
    'Twój udział: $amount PLN',
  );
  static String get fuelSplitUse => _p('Kullan', 'Use', 'Użyj');
  static String formatReceiptTimestamp(DateTime dt) {
    final weekdaysTr = ['Pzt', 'Sal', 'Çrş', 'Prş', 'Cum', 'Cmt', 'Paz'];
    final weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekdaysPl = ['Pn', 'Wt', 'Śr', 'Czw', 'Pt', 'Sob', 'Nd'];
    List<String> names = weekdaysTr;
    if (_lang == AppLang.en) names = weekdaysEn;
    if (_lang == AppLang.pl) names = weekdaysPl;
    final dayName = names[(dt.weekday - 1) % 7];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$dayName, $h:$m';
  }

  // --- Fix 2: Lifetime trip counter reset / edit ---
  static String get resetLifetimeTrips => _p('Sıfırla', 'Reset', 'Resetuj');
  static String get resetLifetimeTripsTitle => _p(
    'Yolculuk Sayacını Sıfırla',
    'Reset Trip Counter',
    'Zresetuj licznik przejazdów',
  );
  static String get resetLifetimeTripsConfirm => _p(
    'Yolculuk sayacını sıfırlamak istediğine emin misin?',
    'Are you sure you want to reset the trip counter?',
    'Czy na pewno chcesz zresetować licznik przejazdów?',
  );
  static String get editLifetimeTripsTitle => _p(
    'Yolculuk Sayısını Düzenle',
    'Edit Trip Count',
    'Edytuj liczbę przejazdów',
  );
  static String get editLifetimeTripsDesc => _p(
    'ERES takibi ile eşitlemek için mevcut toplam yolculuk sayısını girin.',
    'Enter current total trip count to sync with ERES tracking.',
    'Wprowadź aktualną całkowitą liczbę przejazdów, aby zsynchronizować z ERES.',
  );
  static String get editLifetimeTripsLabel => _p(
    'Toplam yolculuk sayısı',
    'Total trip count',
    'Całkowita liczba przejazdów',
  );

  // --- Fix 3: Events module localization ---
  static String get eventRadarTitle =>
      _p('ETKİNLİK RADARI', 'EVENT RADAR', 'RADAR WYDARZEŃ');
  static String get refresh => _p('Yenile', 'Refresh', 'Odśwież');
  static String get eventsReadError => _p(
    'Etkinlik verileri şu an okunamıyor.',
    'Event data cannot be loaded at the moment.',
    'Dane o wydarzeniach są obecnie niedostępne.',
  );
  static String get eventsEmptyDesc => _p(
    'Yaklaşan büyük bir etkinlik bulunamadı.',
    'No upcoming major events found.',
    'Nie znaleziono nadchodzących dużych wydarzeń.',
  );
  static String get radarDemandTitle => _p(
    'Kraków • Talep Yoğunluğu',
    'Kraków • Demand Intensity',
    'Kraków • Nasilenie popytu',
  );
  static String radarDemandSubtitle(int count) => _p(
    'Önümüzdeki günlerde planlanan $count büyük etkinlik yolcu taleplerini ve çarpanları artıracaktır.',
    '$count major scheduled events in the upcoming days will increase passenger demand and surge.',
    'Zaplanowane na najbliższe dni $count duże wydarzenia zwiększą popyt pasażerów i mnożniki.',
  );
  static String get surgeHigh =>
      _p('Yüksek Yoğunluk', 'High Intensity', 'Wysokie nasilenie');
  static String get surgeMedium =>
      _p('Orta Yoğunluk', 'Medium Intensity', 'Średnie nasilenie');
  static String get surgeLow =>
      _p('Düşük Yoğunluk', 'Low Intensity', 'Niskie nasilenie');
  static String get eventsEmptyTitle =>
      _p('Etkinlik Bulunamadı', 'No Events Found', 'Nie znaleziono wydarzeń');
  static String get loadEvents =>
      _p('Etkinlikleri yükle', 'Load events', 'Wczytaj wydarzenia');
  static String get eventsNotLoadedTitle => _p(
    'Etkinlikler hazır değil',
    'Events not loaded',
    'Wydarzenia niepobrane',
  );
  static String get eventsNotLoadedBody => _p(
    'Otomatik getirme kapalı. Listeyi şimdi GitHub’dan alabilirsin.',
    'Automatic fetch is off. You can load the list from GitHub now.',
    'Automatyczne pobieranie jest wyłączone. Możesz teraz wczytać listę z GitHuba.',
  );
  static String eventsCacheAge(Duration age) {
    if (age.isNegative || age.inMinutes < 1) {
      return _p(
        'Az önce yüklendi',
        'Loaded just now',
        'Załadowano przed chwilą',
      );
    }
    if (age.inHours < 1) {
      final n = age.inMinutes;
      return _p(
        '$n dk önce yüklendi',
        'Loaded $n min ago',
        'Załadowano $n min temu',
      );
    }
    if (age.inDays < 1) {
      final n = age.inHours;
      return _p(
        n == 1 ? '1 saat önce yüklendi' : '$n saat önce yüklendi',
        n == 1 ? 'Loaded 1 hour ago' : 'Loaded $n hours ago',
        n == 1 ? 'Załadowano 1 godz. temu' : 'Załadowano $n godz. temu',
      );
    }
    final n = age.inDays;
    return _p(
      n == 1 ? '1 gün önce yüklendi' : '$n gün önce yüklendi',
      n == 1 ? 'Loaded 1 day ago' : 'Loaded $n days ago',
      n == 1 ? 'Załadowano 1 dzień temu' : 'Załadowano $n dni temu',
    );
  }

  static String get tryAgain =>
      _p('Tekrar Deneyin', 'Try Again', 'Spróbuj ponownie');
  static String get connectionError =>
      _p('Bağlantı Hatası', 'Connection Error', 'Błąd połączenia');
  static String get reload => _p('Yeniden Yükle', 'Reload', 'Załaduj ponownie');
  static String get unknownEvent =>
      _p('Bilinmeyen Etkinlik', 'Unknown Event', 'Nieznane wydarzenie');
  static String get unknownVenue =>
      _p('Bilinmeyen Mekan', 'Unknown Venue', 'Nieznane miejsce');

  // --- Backup & Restore ---
  static String get backupMyData =>
      _p('Verilerimi Yedekle', 'Back Up My Data', 'Utwórz kopię zapasową');
  static String get backupMyDataSubtitle => _p(
    'Vardiya, arşiv, kazanç ve ayarları dışa aktar',
    'Export shift counters, archives, earnings and settings',
    'Eksportuj liczniki, archiwa, zarobki i ustawienia',
  );
  static String get restoreFromBackup => _p(
    'Yedekten Geri Yükle',
    'Restore From Backup',
    'Przywróć z kopii zapasowej',
  );
  static String get restoreFromBackupSubtitle => _p(
    'Kaydedilmiş bir yedek dosyasından geri yükle',
    'Restore from a saved backup file',
    'Przywróć dane z zapisanego pliku kopii',
  );
  static String get restorePreviewTitle =>
      _p('Yedeği Geri Yükle', 'Restore Backup', 'Przywróć kopię zapasową');
  static String get restorePreviewSubtitle => _p(
    'Bu işlem mevcut verilerinizin üzerine yazacaktır. Devam etmeden önce yedek içeriğini kontrol edin:',
    'This will overwrite your current data. Review the backup contents before continuing:',
    'To zastąpi Twoje obecne dane. Sprawdź zawartość kopii przed kontynuowaniem:',
  );
  static String get restoreBackupDateLabel =>
      _p('Yedek Tarihi', 'Backup Date', 'Data kopii');
  static String get restoreShiftCountersLabel =>
      _p('Vardiya Sayaçları', 'Shift Counters', 'Liczniki zmiany');
  static String get restoreWeeklyArchiveLabel =>
      _p('Haftalık Arşiv', 'Weekly Archive', 'Archiwum tygodniowe');
  static String get restoreEarningsLabel =>
      _p('Kazanç Kayıtları', 'Earnings Records', 'Zapisy zarobków');
  static String get restoreFuelReceiptsLabel =>
      _p('Yakıt Fişleri', 'Fuel Receipts', 'Paragony paliwowe');
  static String get restoreLifetimeTripsLabel =>
      _p('Toplam Yolculuk Sayacı', 'Lifetime Trips', 'Suma kursów');
  static String get restoreTapHistoryLabel =>
      _p('Dokunma Geçmişi', 'Tap History', 'Historia dotknięć');
  static String get restoreSettingsLabel =>
      _p('Uygulama Ayarları', 'App Settings', 'Ustawienia aplikacji');
  static String restoreOlderWeekNotice(String weekRange) => _p(
    'Bu yedek geçmiş bir haftaya ($weekRange) ait. Yedekteki vardiya sayaçları o haftanın arşivine kaydedilecek ve bu haftanın sayaçları 0 olarak başlayacaktır.',
    'This backup is from a past week ($weekRange). Its shift counters will be archived under that week, and this week’s counters will start at 0.',
    'Ta kopia pochodzi z poprzedniego tygodnia ($weekRange). Liczniki zmiany zostaną zapisane w archiwum tamtego tygodnia, a liczniki bieżącego tygodnia zaczną się od 0.',
  );
  static String get restoreConfirmAction =>
      _p('Geri Yükle', 'Restore', 'Przywróć');
  static String restoreWeekCount(int count) =>
      _p('$count hafta', '$count weeks', '$count tyg.');
  static String restoreItemCount(int count) =>
      _p('$count kayıt', '$count entries', '$count wpisów');
  static String restoreReceiptCount(int count) =>
      _p('$count fiş', '$count receipts', '$count paragonów');
  static String get backupSuccess => _p(
    'Yedek dosyası kaydedildi',
    'Backup file saved',
    'Zapisano plik kopii zapasowej',
  );
  static String get backupFailed => _p(
    'Yedekleme tamamlanamadı. Lütfen tekrar deneyin.',
    'Backup could not be completed. Please try again.',
    'Nie udało się utworzyć kopii zapasowej. Spróbuj ponownie.',
  );
  static String get restoreSuccess => _p(
    'Veriler başarıyla geri yüklendi',
    'Data restored successfully',
    'Dane zostały pomyślnie przywrócone',
  );
  static String get restoreFailed => _p(
    'Geri yükleme başarısız oldu. Mevcut verileriniz korundu.',
    'Restore failed. Your existing data was preserved.',
    'Przywracanie nie powiodło się. Obecne dane zostały zachowane.',
  );
  static String get backupInvalidFile => _p(
    'Geçersiz veya bozuk yedek dosyası.',
    'Invalid or corrupted backup file.',
    'Nieprawidłowy lub uszkodzony plik kopii zapasowej.',
  );
  static String get backupUnsupportedVersion => _p(
    'Bu yedek dosyası daha yeni bir uygulama sürümü gerektiriyor.',
    'This backup file requires a newer app version.',
    'Ten plik kopii wymaga nowszej wersji aplikacji.',
  );
  static String get backupFileTooLarge => _p(
    'Yedek dosyası çok büyük (maksimum 5 MB).',
    'Backup file is too large (max 5 MB).',
    'Plik kopii jest za duży (maks. 5 MB).',
  );
  static String get backupOverlayBusyError => _p(
    'Üst pencere veya bekleyen sayaç kaydı kapatılamadığı için işlem durduruldu.',
    'Operation aborted because the overlay or pending counter writes could not be safely settled.',
    'Operacja przerwana, ponieważ nie udało się bezpiecznie zamknąć dymka lub zapisać liczników.',
  );

  // --- Bug Reporting ---
  static String get reportProblem =>
      _p('Sorun Bildir', 'Report a Problem', 'Zgłoś problem');
  static String get reportProblemSubtitle => _p(
    'Hata raporu oluştur ve geliştiriciye gönder',
    'Create and send a bug report to the developer',
    'Utwórz i wyślij raport o błędzie do dewelopera',
  );
  static String get reportCategoryEyebrow =>
      _p('SORUN KATEGORİSİ', 'ISSUE CATEGORY', 'KATEGORIA PROBLEMU');
  static String get reportCatOverlay =>
      _p('Baloncuk (Overlay)', 'Overlay', 'Dymek (Overlay)');
  static String get reportCatCounters => _p('Sayaçlar', 'Counters', 'Liczniki');
  static String get reportCatEarningsFuel =>
      _p('Kazanç / Yakıt', 'Earnings / Fuel', 'Zarobki / Paliwo');
  static String get reportCatSteeringNotification => _p(
    'Direksiyon / Bildirim',
    'Steering Wheel / Notification',
    'Kierownica / Powiadomienia',
  );
  static String get reportCatOther => _p('Diğer', 'Other', 'Inne');
  static String get reportDescriptionEyebrow =>
      _p('SORUN AÇIKLAMASI', 'PROBLEM DESCRIPTION', 'OPIS PROBLEMU');
  static String get reportDescriptionHint => _p(
    'Ne olduğunu ve sorunu nasıl tekrarlayabileceğimizi kısaca yazın…',
    'Briefly describe what happened and how to reproduce it…',
    'Krótko opisz, co się stało i jak odtworzyć problem…',
  );
  static String get reportDescriptionEmptyError => _p(
    'Lütfen kısa bir sorun açıklaması yazın.',
    'Please enter a short problem description.',
    'Wpisz krótki opis problemu.',
  );
  static String get reportScreenshotEyebrow => _p(
    'EKRAN GÖRÜNTÜSÜ (İSTEĞE BAĞLI)',
    'SCREENSHOT (OPTIONAL)',
    'ZRZUT EKRANU (OPCJONALNIE)',
  );
  static String get reportAttachScreenshot =>
      _p('Ekran Görüntüsü Ekle', 'Attach Screenshot', 'Dodaj zrzut ekranu');
  static String get reportRemoveScreenshot => _p('Kaldır', 'Remove', 'Usuń');
  static String get reportScreenshotTooLarge => _p(
    'Görsel çok büyük (maksimum 5 MB).',
    'Image is too large (max 5 MB).',
    'Obraz jest za duży (maks. 5 MB).',
  );
  static String get reportScreenshotFailed => _p(
    'Görsel eklenemedi.',
    'Could not attach image.',
    'Nie udało się dodać obrazu.',
  );
  static String get reportOptionsEyebrow => _p(
    'TANI VE HATA BİLGİLERİ',
    'DIAGNOSTICS & LOGS',
    'DIAGNOSTYKA I DZIENNIKI',
  );
  static String get reportIncludeDiagnostics => _p(
    'Cihaz ve uygulama tanı bilgilerini ekle',
    'Include device & app diagnostics',
    'Dołącz dane diagnostyczne urządzenia i aplikacji',
  );
  static String get reportIncludeDiagnosticsSub => _p(
    'Sürüm, Android modeli ve baloncuk ayarları (kazanç veya konum içermez)',
    'App version, Android model and overlay settings (no earnings or location)',
    'Wersja aplikacji, model Androida i ustawienia dymka (bez zarobków i lokalizacji)',
  );
  static String get reportIncludeCrashLogs => _p(
    'Son hata kayıtlarını ekle (Maskelenmiş)',
    'Include recent error logs (Sanitized)',
    'Dołącz ostatnie dzienniki błędów (Zanonimizowane)',
  );
  static String get reportIncludeCrashLogsSub => _p(
    'Varsayılan olarak kapalıdır. Yalnızca son hatalar kişisel veriler maskelenerek eklenir.',
    'Off by default. Only recent errors are included with private data masked.',
    'Domyślnie wyłączone. Dołączane są tylko ostatnie błędy po zamaskowaniu danych.',
  );
  static String get reportPreviewEyebrow => _p(
    'GÖNDERİLECEK RAPOR ÖNİZLEMESİ',
    'REPORT PREVIEW BEFORE SENDING',
    'PODGLĄD RAPORTU PRZED WYSŁANIEM',
  );
  static String get reportDeliveryNotice => _p(
    'Rapor, güvenli sunucu üzerinden geliştiriciye Telegram ile gönderilir. Telegram hesabı veya uygulaması gerekmez.',
    'The report is sent to the developer through a secure server and Telegram. No Telegram account or app is required.',
    'Raport jest wysyłany do dewelopera przez bezpieczny serwer i Telegram. Konto ani aplikacja Telegram nie są potrzebne.',
  );
  static String get reportPrivacyNotice => _p(
    'Gizlilik: Kazançlarınız, yakıt fişleriniz, konumunuz, telefon numaranız ve gizli anahtarlarınız asla rapora dahil edilmez.',
    'Privacy: Your earnings, fuel receipts, location, phone number and secret keys are never included.',
    'Prywatność: Twoje zarobki, paragony paliwowe, lokalizacja, numer telefonu ani klucze nigdy nie są dołączane.',
  );
  static String get reportSendAction =>
      _p('Raporu Gönder', 'Send Report', 'Wyślij zgłoszenie');
  static String get reportSending =>
      _p('Gönderiliyor…', 'Sending…', 'Wysyłanie…');
  static String get reportSendSuccess => _p(
    'Rapor geliştiriciye gönderildi.',
    'Report sent to the developer.',
    'Raport został wysłany do dewelopera.',
  );
  static String get reportSendFailed => _p(
    'Rapor gönderilemedi. Bilgileriniz korunuyor; tekrar deneyin.',
    'Could not send the report. Your entries are preserved; please try again.',
    'Nie udało się wysłać raportu. Dane zostały zachowane; spróbuj ponownie.',
  );
  static String get reportSendInvalid => _p(
    'Rapor doğrulanamadı. Alanları ve ekran görüntüsünü kontrol edin.',
    'The report could not be validated. Check the fields and screenshot.',
    'Nie udało się zweryfikować raportu. Sprawdź pola i zrzut ekranu.',
  );
  static String get reportSendRateLimited => _p(
    'Çok fazla rapor gönderildi. Lütfen daha sonra tekrar deneyin.',
    'Too many reports were sent. Please try again later.',
    'Wysłano zbyt wiele raportów. Spróbuj ponownie później.',
  );
  static String get reportSendDuplicate => _p(
    'Bu rapor kısa süre önce gönderildi.',
    'This report was sent recently.',
    'Ten raport został niedawno wysłany.',
  );
  static String get reportSendUnavailable => _p(
    'Rapor servisi bu sürümde ayarlı değil.',
    'The report service is not configured in this build.',
    'Usługa zgłoszeń nie jest skonfigurowana w tej wersji.',
  );

  static List<String> get months {
    switch (_lang) {
      case AppLang.tr:
        return [
          '',
          'Oca',
          'Şub',
          'Mar',
          'Nis',
          'May',
          'Haz',
          'Tem',
          'Ağu',
          'Eyl',
          'Eki',
          'Kas',
          'Ara',
        ];
      case AppLang.en:
        return [
          '',
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
      case AppLang.pl:
        return [
          '',
          'Sty',
          'Lut',
          'Mar',
          'Kwi',
          'Maj',
          'Cze',
          'Lip',
          'Sie',
          'Wrz',
          'Paź',
          'Lis',
          'Gru',
        ];
    }
  }

  static List<String> get monthsFull {
    switch (_lang) {
      case AppLang.tr:
        return [
          '',
          'Ocak',
          'Şubat',
          'Mart',
          'Nisan',
          'Mayıs',
          'Haziran',
          'Temmuz',
          'Ağustos',
          'Eylül',
          'Ekim',
          'Kasım',
          'Aralık',
        ];
      case AppLang.en:
        return [
          '',
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
      case AppLang.pl:
        return [
          '',
          'Styczeń',
          'Luty',
          'Marzec',
          'Kwiecień',
          'Maj',
          'Czerwiec',
          'Lipiec',
          'Sierpień',
          'Wrzesień',
          'Październik',
          'Listopad',
          'Grudzień',
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
