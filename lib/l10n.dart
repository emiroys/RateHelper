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
  static String get accepted => _p('Kabul Edilen', 'Accepted', 'Zaakceptowane');
  static String get rejected => _p('Reddedilen', 'Rejected', 'Odrzucone');
  static String get completed => _p('Tamamlanan', 'Completed', 'Ukończone');
  static String get cancelled => _p('İptal Edilen', 'Cancelled', 'Anulowane');
  static String get autoCompleteTrips => _p(
        'Otomatik tamamla',
        'Auto-complete trips',
        'Automatyczne ukończenie',
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
      _p('Anti-Eres Aktif', 'Anti-Eres Active', 'Anti-Eres Aktywny');
  static String get overlayOff =>
      _p('Anti-Eres Kapatıldı', 'Anti-Eres Closed', 'Anti-Eres Wyłączony');
  static String get archiveAccept => _p('Kabul', 'Accept', 'Akceptacja');
  static String get archiveCancel => _p('İptal', 'Cancel', 'Anulowanie');
  static String get overlayTitle =>
      _p('Anti-Eres Aktif', 'Anti-Eres Active', 'Anti-Eres Aktywny');
  static String get overlayContent => _p(
        'Çalışıyor.',
        'Running.',
        'Działa.',
      );

  static String get onboardingTitle => _p(
        'Anti-Eres Kurulumu',
        'Anti-Eres Setup',
        'Konfiguracja Anti-Eres',
      );
  static String get onboardingIntro => _p(
        'Anti-Eres’in arka planda çalışabilmesi için iki Android iznine ihtiyacı var. Aşağıdaki adımları sırayla yap.',
        'Anti-Eres needs two Android permissions to run in the background. Complete the steps below in order.',
        'Anti-Eres potrzebuje dwóch uprawnień Androida, aby działać w tle. Wykonaj poniższe kroki po kolei.',
      );
  static String get stepOverlayTitle => _p(
        '1. Üzerine Çizim İzni',
        '1. Display Over Other Apps',
        '1. Nakładka nad innymi aplikacjami',
      );
  static String get stepOverlayBody => _p(
        'Uber Driver açıkken Anti-Eres’in butonlarını göstermesi için bu izin şart. Açılan ayar ekranında Anti-Eres’i bul ve aç.',
        'Required so Anti-Eres buttons appear on top of Uber Driver. In the settings screen that opens, find Anti-Eres and enable the switch.',
        'Wymagane, aby przyciski Anti-Eres pojawiały się nad Uber Driver. W otwartym ekranie ustawień znajdź Anti-Eres i włącz przełącznik.',
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
        'Vardiya boyunca Anti-Eres’in arka planda öldürülmemesi için pil optimizasyonu KAPALI olmalı. Telefon markana göre talimat aşağıda.',
        'To prevent Anti-Eres being killed during your shift, battery optimization must be OFF. Instructions per phone brand below.',
        'Aby Anti-Eres nie został zabity podczas zmiany, optymalizacja baterii musi być WYŁĄCZONA. Instrukcje dla marki telefonu poniżej.',
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
        'Ayarlar → Cihaz bakımı → Pil → Arka plan kullanım sınırları → Asla uyutulmayacak uygulamalar → Anti-Eres ekle.',
        'Settings → Device care → Battery → Background usage limits → Never sleeping apps → add Anti-Eres.',
        'Ustawienia → Konserwacja → Bateria → Limity tła → Aplikacje, które nigdy nie usypiają → dodaj Anti-Eres.',
      );
  static String get xiaomiSteps => _p(
        'Ayarlar → Uygulamalar → Anti-Eres → Pil tasarrufu → Kısıtlama yok. Ayrıca: Otomatik başlatma → AÇIK.',
        'Settings → Apps → Anti-Eres → Battery saver → No restrictions. Also: Autostart → ON.',
        'Ustawienia → Aplikacje → Anti-Eres → Oszczędzanie baterii → Brak ograniczeń. Także: Autostart → WŁ.',
      );
  static String get huaweiSteps => _p(
        'Ayarlar → Uygulamalar → Anti-Eres → Pil → Uygulama başlatma → Otomatik yönet KAPAT → tüm manuel anahtarlar AÇIK.',
        'Settings → Apps → Anti-Eres → Battery → App launch → turn OFF Manage automatically → turn ON all three switches.',
        'Ustawienia → Aplikacje → Anti-Eres → Bateria → Uruchamianie aplikacji → wyłącz Zarządzaj automatycznie → wszystkie trzy włączniki WŁ.',
      );
  static String get onePlusSteps => _p(
        'Ayarlar → Pil → Pil optimizasyonu → Anti-Eres → Optimize etme. Ayrıca: Son uygulamalar ekranında Anti-Eres kartını yukarıdan kilitle.',
        'Settings → Battery → Battery optimization → Anti-Eres → Don’t optimize. Also: lock the Anti-Eres card from the top in Recents.',
        'Ustawienia → Bateria → Optymalizacja baterii → Anti-Eres → Nie optymalizuj. Także: zablokuj kartę Anti-Eres w Ostatnich.',
      );
  static String get otherSteps => _p(
        'Telefonun pil ayarlarında "Anti-Eres" uygulamasını bul ve pil optimizasyonunu KAPAT veya "Kısıtlanmamış" olarak işaretle.',
        'In your phone’s battery settings, find "Anti-Eres" and turn battery optimization OFF, or mark it as "Unrestricted".',
        'W ustawieniach baterii telefonu znajdź "Anti-Eres" i wyłącz optymalizację lub oznacz jako "Bez ograniczeń".',
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
  static String get widgetStart => _p('Başlat', 'Start', 'Uruchom');
  static String get widgetStop => _p('Durdur', 'Stop', 'Zatrzymaj');

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
