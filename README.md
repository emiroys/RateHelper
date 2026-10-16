# RateHelper v5 — Podręcznik Architektury i Dokumentacja Operacyjna

> **Identyfikator aplikacji:** `com.ratehelper.app`  
> **Platforma docelowa:** Android (arm64-v8a, zoptymalizowane pod flagowce typu Samsung Galaxy S24 Ultra)  
> **Framework:** Flutter (Dart) + Natywny Kotlin/Java (Android OS Layer)  
> **Wersja bieżąca:** `5.0.4+9` (versionName `5.0.4`, pubspec build `9`, arm64 versionCode `2009`)

---

## Spis treści

1. [Tożsamość i cel aplikacji](#1-tożsamość-i-cel-aplikacji)
2. [Główne moduły funkcjonalne](#2-główne-moduły-funkcjonalne)
3. [Architektura systemu i dwuizolatowość (Isolates)](#3-architektura-systemu-i-dwuizolatowość-isolates)
4. [System Designu i Tokenizacja UI (Design System)](#4-system-designu-i-tokenizacja-ui-design-system)
5. [Silnik finansowy i parametry partnera ERES](#5-silnik-finansowy-i-parametry-partnera-eres)
   - [Stawki podatkowe i prowizje](#stawki-podatkowe-i-prowizje)
   - [Tabele progowe najmu (Solo, Paired, Trio)](#tabele-progowe-najmu-solo-paired-trio)
   - [Rozdział kursów: driverTripCount vs. carTripCount](#rozdział-kursów-drivertripcount-vs-cartripcount)
   - [Próg rentowności (Break-Even)](#próg-rentowności-break-even)
6. [Bezpieczeństwo, Prywatność i Integralność Danych](#6-bezpieczeństwo-prywatność-i-integralność-danych)
7. [Model dystrybucji (Brak Play Store)](#7-model-dystrybucji-brak-play-store)
8. [Procedura kompilacji wydania produkcyjnego (Release Build)](#8-procedura-kompilacji-wydania-produkcyjnego-release-build)
9. [Struktura plików projektu](#9-struktura-plików-projektu)

---

## 1. Tożsamość i cel aplikacji

**RateHelper** to asystent kierowcy rideshare (Uber/Bolt) w **Krakowie**, we flocie **ERES Partner**. Przejazdy, paragony i zarobki zostają na telefonie. Aplikacja łączy się z GitHubem tylko wtedy, gdy kierowca na to pozwoli albo sam o to poprosi. W jednym, zoptymalizowanym pod kątem jazdy środowisku:
- Pływający widget nakładki (Floating Pill Overlay) zawieszony bezpośrednio nad aplikacją kierowcy,
- Kalkulator wskaźnika akceptacji (Acceptance Rate) z dynamicznym systemem ostrzegania i celem tygodniowym,
- Precyzyjny moduł księgowo-rozliczeniowy wyliczający realny zysk netto po odliczeniu podatku ryczałtowego VAT, prowizji partnera, progów najmu i rabatów paliwowych,
- Niezależny drogomierz kursów osobistych zliczający postęp do darmowego tygodnia najmu (kamień milowy 2000 kursów),
- Radar wydarzeń masowych w Krakowie (Tauron Arena, stadiony) przewidujący strefy podwyższonego popytu (surge),
- Pełne wsparcie trójjęzyczne: Turecki (domyślny), Polski oraz Angielski.

### Główne zasady projektowe
- **Dane kierowcy zostają na telefonie:** Przejazdy, paragony, zarobki i statystyki nie opuszczają urządzenia. Nie ma konta ani zewnętrznej bazy tych danych. Automatyczne sprawdzanie aktualizacji i automatyczne pobieranie wydarzeń są domyślnie wyłączone. Włączenie ich albo ręczne „Sprawdź aktualizacje” / „Wczytaj wydarzenia” wysyła tylko adres IP i zwykłe nagłówki żądania — bez danych użytkownika.
  - `gist.githubusercontent.com` — manifest aktualizacji
  - `api.github.com` — zapasowy odczyt ostatniego wydania, tylko gdy manifest się nie wczyta podczas sprawdzenia, które już trwa
  - `github.com` oraz przekierowania na `*.githubusercontent.com` — plik APK, dopiero po stuknięciu akcji aktualizacji
  - `raw.githubusercontent.com` — publiczny JSON wydarzeń w Krakowie
- **Driving-First UI:** Ekstremalny ciemny motyw OLED, dotykowe punkty interakcji spełniające normy bezpieczeństwa (minimum 48–68 dp) oraz selektywna haptyka dostosowana do obsługi w uchwycie samochodowym.
- **Kompaktowość i płynność:** Niski narzut na baterię i pamięć RAM podczas 12-godzinnych zmian roboczych.

---

## 2. Główne moduły funkcjonalne

| Moduł | Opis Funkcjonalny | Mechanizm Implementacji |
| :--- | :--- | :--- |
| **Pływająca Nakładka (Pill Overlay)** | Widget **276×80 dp** (Yatay / poziomo) lub **74×194 dp** (Dikey / pionowo) nad aplikacją Uber/Bolt. Stuknięcie **% akceptacji** zwija pigułkę do okrągłej bańki **R** (**48 dp**) — mniej zasłania mapę; stuknięcie **R** przywraca pełną pigułkę. +/− bez opuszczania mapy. Kierunek: **Ayarlar → Baloncuk Yönü**. | Osobny izolat (`packages/flutter_overlay_window`); okno natywne = widoczny stadion. `resizeOverlay` **tylko** w izolacie nakładki (zwijanie/rozwijanie). Zmiana orientacji: zamknij + otwórz ponownie — **nie** z głównego izolatu. |
| **Ekran ustawień** | Wszystkie przełączniki (tryb jazdy, balon, język, GitHub auto, kierownica, wakelock), **Sprawdź aktualizacje**, **Kurulum Rehberi**, wersja. | `lib/settings_screen.dart` — ikona **koła zębatego** na pasku ekranu głównego; `SettingsSnapshot` synchronizuje stan z home. |
| **Pulpit Akceptacji (AR) i Odzyskiwania** | Precyzyjny licznik zleceń (Zaakceptowane, Odrzucone, Ukończone, Anulowane). Dynamiczny bufor ostrzegawczy (2.0% wokół progu celu) oraz kalkulator liczby kursów potrzebnych do odzyskania bezpiecznego wskaźnika. | `home_screen.dart`, wzór odzyskiwania $X = \max(1, \lfloor \frac{r \cdot R - (1-r) \cdot A}{1-r} \rfloor + 1)$, reaktywne notifiery `ValueNotifier`. |
| **Archiwum tygodni (Logi)** | Po resecie tygodnia zapis v2 JSON z celem (`goalTier`, progi akceptacji/iptal); karty `WeeklyArchiveCard` z **Hedef Tuttu / Tutmadı**; scalanie duplikatów tego samego tygodnia. | `weekly_archive_entry.dart`, `weekly_archive_card.dart`, `collapseWeeklyArchive`, prefs `weekly_archive`. |
| **Śledzenie Zarobków i Podatków** | Tygodniowy arkusz rozliczeniowy: VAT 12%, opłata ERES 4.3125%, paliwo −10%, najem progowy. Trend 4-tygodniowy i karty miesiąc/rok używają **`blendedHourlyRate`** (zysk ÷ godziny). Tydzień-placeholder paliwa (`isUnreported`) nie dolicza najmu. | `earnings_screen.dart`, `earnings_models.dart`, podgląd live. |
| **Paragony Paliwowe (Multi-Receipt)** | Rejestracja wielu paragonów paliwowych w danym tygodniu z pełnym formatowaniem walutowym, usuwaniem gestem z opcją cofnięcia (Undo SnackBar) i limitem FIFO (max 100). | `_buildFuelReceiptsSection`, `PolishCurrencyInputFormatter`, formatowanie walutowe zgodne z polskim standardem (`1 250,50 PLN`). |
| **Tryby Najmu: Solo, Paired, Trio** | Dynamiczne dopasowanie kosztu najmu auta dla 1, 2 lub 3 kierowców na jednym pojeździe. | `DriverMode.solo` / `.paired` / `.trio`, odrębne tabele progowe, bezwzględna niezmienność historyczna zapisanych wpisów. |
| **Rozdział Liczników Kursów** | Kursy osobiste kierowcy zliczają postęp do darmowego tygodnia (próg 2000), podczas gdy suma kursów auta w trybie współdzielonym decyduje o progu zniżki najmu. | `driverTripCount` (odometer) oraz `carTripCountOverride` (tier lookup). |
| **Radar Wydarzeń (Kraków)** | Kalendarz imprez masowych w Krakowie prognozujący godziny szczytów i skoków mnożników stawek. | `radar_screen.dart`. JSON z `raw.githubusercontent.com` tylko gdy automatyczne pobieranie jest włączone albo kierowca stuknie odświeżenie / „Wczytaj wydarzenia”. Ostatnia lista zostaje na dysku i pokazuje swój wiek. |
| **Integracja z Przyciskami na Kierownicy** | Rejestracja zleceń za pomocą bezprzewodowego pilota multimedialnego Bluetooth na kierownicy bez odrywania rąk. | `MediaKeyAccessibilityService.kt`: długie przytrzymanie >800 ms; dostarczenie w `TapDelivery.kt` (ACK nakładki 1200 ms + `recordPendingTap`); `drainPendingTaps` odejmuje (nie czyści); `_drainPendingTaps` dopiero po `await _loadAndCheckReset()`. |
| **Sterowanie z powiadomienia (opcjonalne)** | **Ayarlar → Bildirim kontrolleri**, domyślnie wyłączone. Gdy dymek jest otwarty, powiadomienie usługi nakładki ma przyciski **Odrzuć +1** / **Akceptuj +1** i bieżący wskaźnik akceptacji (2 miejsca po przecinku, plus liczby) — bez kwot. Ukryte na ekranie blokady. `POST_NOTIFICATIONS` pytane dopiero przy włączeniu; odmowa = przełącznik zostaje wyłączony. | Treść wysyła izolat nakładki (`ShadeNotificationThrottle`, max 1 re-post/s, bez duplikatów) przez `x-slayer/overlay` → `updateNotification` → `OverlayService.notificationDecorator` (`ShadeControls.kt`, kanał `IMPORTANCE_DEFAULT` bez dźwięku). Przyciski: `PendingIntent` `FLAG_IMMUTABLE` → nieeksportowany `ShadeControlsReceiver` → `TapDelivery` (ta sama ścieżka co kierownica: ACK nakładki albo `ratehelper_pending_taps`). |
| **Raporty PDF do Księgowości** | Generowanie miesięcznych lub rocznych zestawień przychodów i kosztów z podziałem ryczałtowym gotowych do przekazania księgowej. | `earnings_pdf_export.dart`, formatowanie `pdf`, czcionki DM Sans ładowane lokalnie z assetów. |
| **Sprawdzanie i instalacja aktualizacji (OTA)** | Jednorazowe pytanie o GitHub (auto-aktualizacja + wydarzenia); domyślnie wyłączone. Ręcznie: **Ayarlar → Güncellemeleri denetle** (czas ostatniego sprawdzenia + wersja na tym samym wierszu). APK (~21 MB) dopiero po stuknięciu aktualizacji w dialogu; weryfikacja podpisu i `versionCode` przed instalatorem; przeglądarka tylko gdy pobranie w aplikacji się nie uda. | `lib/services/update_service.dart`, `lib/update_dialog.dart`, `lib/github_consent_dialog.dart`, `lib/services/github_access.dart`, manifest Gist (`Env.gistUrl`) + zapas GitHub Releases API, `FileProvider`, `REQUEST_INSTALL_PACKAGES`, opcjonalne `apk_sha256`, cache-bust Gist (`?_=`). |

---

## 3. Architektura systemu i dwuizolatowość (Isolates)

RateHelper działa w oparciu o dwa w pełni rozdzielone izolaty maszyny wirtualnej Dart:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Android OS Layer                              │
│   ┌──────────────────┐  ┌───────────────────────┐  ┌──────────────────┐ │
│   │   MainActivity   │  │    OverlayService     │  │  MediaKey A11y   │ │
│   │     (Kotlin)     │  │   (Java, forked lib)  │  │     (Kotlin)     │ │
│   │  MethodChannel   │  │  WindowManager (OS)   │  │  Przechwytywanie │ │
│   │  Weryfikacja sig │  │  Pill: 276×80 / 74×194│  │  KeyEvent (A11y) │ │
│   └────────┬─────────┘  └───────────┬───────────┘  └────────┬─────────┘ │
└────────────┼────────────────────────┼───────────────────────┼───────────┘
             │ Flutter Main Engine    │ Lean Overlay Engine   │ IPC Event
┌────────────┼────────────────────────┼───────────────────────┼───────────┐
│            ▼                        ▼                       ▼           │
│   ┌──────────────────┐      ┌──────────────────┐                        │
│   │   HomeScreen     │      │  OverlayWidget   │ ◄─ IPC sync payload    │
│   │ (Główny izolat)  │      │ (Izolat nakładki)│    oraz pliki JSON     │
│   └────────┬─────────┘      └──────────────────┘                        │
│            │                                                            │
│   ┌────────┼──────────┬─────────────────┬─────────────┐                │
│   ▼        ▼          ▼                 ▼             ▼                │
│ Zarobki  Radar    Onboarding        Eksport PDF   Przypomnienia         │
│ Screen   Screen   (Uprawnienia)     i Raporty     Lokalne               │
└─────────────────────────────────────────────────────────────────────────┘
```

### Kluczowe decyzje architektoniczne nakładki:
1. **Chudy silnik nakładki (Lean Engine):** Izolat nakładki ma wyłączone automatyczne ładowanie pluginów (`setAutomaticallyRegisterPlugins(false)`). Zarejestrowane są jedynie wtyczki niezbędne (`SharedPreferencesPlugin`, IPC okna oraz JNI/path_provider). Wtyczki ciężkie (URL launcher, share, wakelock) nie są dołączane do pamięci nakładki.
2. **Rozmiar okna zoptymalizowany pod dotyk:** Okno natywne ma dokładnie rozmiar widocznego stadionu — **276×80 dp** poziomo albo **74×194 dp** pionowo (68 dp przycisk + 3 dp ramka; wysokość = 2×68 + 2×8 odstęp + 36 slot procentu + 2×3). Żaden niewidoczny obszar nie blokuje Uber/Bolt. Pion **nie** jest naiwną zamianą 80×276 — to zostawiało puste końce kapsuły.
3. **Synchronizacja stanów bez blokowania wątku:** Liczniki bieżącej zmiany zapisywane są do lekkiego pliku `shift_counters.json` (`ShiftCounterStore`), a dziennik kliknięć do dopisywanego pliku `tap_history.jsonl` (`TapHistoryStore`, max 500 wpisów). Komunikacja między izolatami przesyła wartości bezpośrednio w ładunku wiadomości IPC — eliminuje to kosztowne przeładowania pliku SharedPreferences XML (`prefs.reload()`) przy każdym tapnięciu. `prefs.reload()` wyłącznie przy starcie izolatu nakładki. Stuknięcia na pigułce wysyłają `OverlaySync.pingCountersChanged` do ekranu głównego (współbieżne odświeżenie liczników bez minimalizacji aplikacji).
4. **Zwijanie pigułki:** Pref `overlay_pill_collapsed` (tylko izolat nakładki). Kolejność: zwinięcie = narysuj bańkę **R** → `endOfFrame` → `resizeOverlay`; rozwinięcie = powiększ okno → `didChangeMetrics` → pełna pigułka. Treść w `OverflowBox`, żeby układ Row/Column nie pękał w oknie 48 dp.
5. **Slop przeciągania 20 dp (nie 20 px):** Na S24 Ultra (~3×) 20 pikseli fizycznych ≈ 7 dp i kradnie tapnięcia. Po przekroczeniu progu natywny `onTouch` wysyła do Fluttera `ACTION_CANCEL`, potem konsumuje MOVE/UP. Silnik nakładki jest niszczony w `OverlayService.onDestroy` (prawdziwy restart izolatu).

---

## 4. System Designu i Tokenizacja UI (Design System)

Aplikacja posiada rygorystyczny, scentralizowany system tokenów projektowych. **Zabronione jest stosowanie surowych liczb (tzw. magic numbers)** dla paddingów, marginesów, promieni zaokrągleń (radius), rozmiarów krojów pisma oraz kolorów.

### Pliki tokenów
- [`lib/app_spacing.dart`](lib/app_spacing.dart) — definicja `AppSpacing` oraz `AppRadius`.
- [`lib/app_text_styles.dart`](lib/app_text_styles.dart) — 6-stopniowa hierarchia typograficzna `AppTextStyles` oparta na kroju DM Sans, wsparcie `tabularFigures()` oraz zachowana zgodność `T.*`.
- [`lib/app_colors.dart`](lib/app_colors.dart) — 3-tonowa architektura ciemnych powierzchni OLED, semantyczne barwy stanu i akcentów.
- [`lib/app_widgets.dart`](lib/app_widgets.dart) — standaryzowane prymitywy przycisków i komponentów (`AppPrimaryButton`, `AppSecondaryButton`, `AppIconActionButton`, `AppDangerButton`, `AppEmptyState`, `AppTapTarget`).

### Matryca tokenów projektowych

| Rola / Zastosowanie | Stara wartość (Ad-hoc) | Nowy Token Projektowy | Definicja / Wartość |
| :--- | :--- | :--- | :--- |
| **Główne liczby wskaźników (Hero)** | `36px`, `46px`, `48px`, `56px` | `AppTextStyles.heroNumber` / `AppTextStyles.hero` | `48.0`, w900, DM Sans z `tabularFigures()` |
| **Tytuły sekcji** | `18px`, `20px`, `22px` | `AppTextStyles.sectionTitle` | `20.0`, w800, DM Sans |
| **Nagłówki kart i formularzy** | `15px`, `16px`, `17px` | `AppTextStyles.headline` | `16.0`, w800, DM Sans |
| **Tekst podstawowy (Body)** | `13px`, `14px`, `15px` | `AppTextStyles.body` | `14.0`, w500, DM Sans |
| **Podpisy i etykiety pomocnicze** | `11px`, `12px`, `13px` | `AppTextStyles.caption` | `12.0`, w500, DM Sans |
| **Etykiety nadtytułowe (Eyebrow)** | `10px`, `11px`, `12px` | `AppTextStyles.eyebrow` / `eyebrowStyle` | `11.0`, w800, tracking 1.5, DM Sans |
| **Mikro promień zaokrąglenia** | `3px`, `4px`, `5px` | `AppRadius.xs` / `AppRadius.xsBorder` | `4.0` (paski postępu, mikro indykatory) |
| **Mały promień zaokrąglenia** | `6px`, `8px`, `10px`, `12px` | `AppRadius.sm` / `AppRadius.smBorder` | `8.0` (odznaki, tagi, kontenery podrzędne) |
| **Standardowy promień karty** | `14px`, `16px`, `18px` | `AppRadius.md` / `AppRadius.mdBorder` | `16.0` (wszystkie karty, modale, formularze) |
| **Duży promień (Hero / Arkusze)** | `18px`, `20px`, `24px` | `AppRadius.lg` / `AppRadius.lgBorder` | `20.0` (karty wyróżnione, arkusze dolne) |
| **Kapsułka / Pigułka (Pill)** | `99px`, `999px`, `StadiumBorder` | `AppRadius.pill` / `AppRadius.pillBorder`| `999.0` (pigułka nakładki, chipy, FAB) |
| **Wewnętrzny padding kart** | `14px`, `18px`, `20px`, `24px` | `AppSpacing.cardPadding` | `EdgeInsets.all(16.0)` (likwidacja dryfu paddingów) |
| **Główny margines ekranu** | `20px`, `16px` | `AppSpacing.screenPadding` | `EdgeInsets.symmetric(horizontal: 16.0)` |
| **Podkładowa czerń ekranu** | `#000000` / `#0D0D0D` | `AppColors.background` | `0xFF0D0D0D` (Głębokie tło OLED) |
| **Standardowa powierzchnia karty** | `#161616` / `#181818` | `AppColors.surface` | `0xFF161616` (Karty bazowe) |
| **Powierzchnia wyniesiona** | `#1E1E1E` / `#222222` | `AppColors.surfaceElevated` | `0xFF1E1E1E` (Nakładka, dialogi, arkusze) |
| **Złoto rekordów i kamieni milowych** | `#F59E0B` / `#FFC107` | `AppColors.recordGold` | `0xFFFFD54A` (Kamienie milowe, 2000 kursów) |
| **Złoto sygnatury KK383CT** | Cichy pill na `surfaceElevated` | `AppColors.designerGold` | `0xFFD4AF37` (obramowanie ~22% alpha, JetBrains Mono 12 — **bez** `ShaderMask` / poświaty) |
| **Błękit interakcji i akcji** | Złoto / Morski | `AppColors.actionAccent` | `0xFF38BDF8` (Dodawanie paragonów, przyciski akcji) |

### Zasady typografii i ikonografii
- **Monospace wyłącznie do tabel walutowych i plakietki KK383CT:** Czcionka `JetBrains Mono` jest zarezerwowana **wyłącznie** dla wyrównanych w kolumnach kwot walutowych PLN oraz złotej sygnatury projektanta (`KK383CT`) na stopce ekranu głównego.
- **Wszystkie pozostałe liczby:** Liczniki kursów, wskaźniki procentowe oraz daty używają kroju `DM Sans` z włączoną funkcją `FontFeature.tabularFigures()`, co całkowicie zapobiega poziomemu drganiu (jitter) tekstu przy zmianie cyfr.
- **Standaryzacja ikon Material Rounded:** Interfejs stosuje zaokrąglone warianty ikon Material (`Icons.*_rounded`). Funkcjonalne emoji interfejsowe (🟢, 🔴, 🏆, ⛽) zostały zastąpione ikonami wektorowymi. Flagi wyboru języka (`🇹🇷`, `🇬🇧`, `🇵🇱`) pozostają w formie natywnej.

---

## 5. Silnik finansowy i parametry partnera ERES

Silnik kalkulacyjny opiera się na rzeczywistych warunkach rozliczeniowych krakowskiego partnera **ERES Partner**. Wszystkie parametry są zdefiniowane centralnie w [`lib/earnings_models.dart`](lib/earnings_models.dart).

> **Ważna uwaga:** Wartości te odzwierciedlają aktualną umowę partnerską ERES. W przypadku renegocjacji lub zmiany cennika przez partnera, stałe te muszą zostać zaktualizowane w kodzie źródłowym.

### Stawki podatkowe i prowizje
- **Podatek VAT ryczałtowy:** **12.0%** (`FLAT_VAT_RATE = 0.12`). Obliczany bezpośrednio z obrotu netto Ubera: $\text{VAT} = \text{round}_2(\text{netIncome} \times 0.12)$.
- **Opłata rozliczeniowa partnera (Settlement Fee):** **4.3125%** (`SETTLEMENT_FEE_RATE = 0.043125`, zaktualizowana z wcześniejszej stawki 3.0%). Etykieta w interfejsie i na wydrukach PDF prezentuje zaokrąglenie do 2 miejsc po przecinku: `Hesap Kesim Ücreti (%4.31)`.
- **Rabat partnerski na paliwo:** **10.0%** (`FUEL_PARTNER_DISCOUNT = 0.10`). Koszt paliwa kierowcy: $\text{fuelAfterDiscount} = \text{round}_2(\text{fuelPumpPaid} \times 0.90)$.

### Tabele progowe najmu (Solo, Paired, Trio)

Aplikacja wylicza koszt najmu pojazdu automatycznie na podstawie liczby przejazdów:

#### 1. Tryb Solo (Jeden kierowca na aucie)
| Liczba wykonanych kursów | Koszt najmu kierowcy |
| :--- | :--- |
| 0 – 99 kursów | **900 PLN** |
| 100 – 149 kursów | **700 PLN** |
| 150 – 199 kursów | **500 PLN** |
| 200 – 249 kursów | **300 PLN** |
| 250+ kursów | **100 PLN** |
*(Gdy zniżka najmu jest wyłączona przełącznikiem: stała opłata bazowa 900 PLN)*

#### 2. Tryb Paired (Dwaj kierowcy dzielący auto w systemie zmianowym)
| Łączna liczba kursów auta | Koszt przypadający na kierowcę | Łączny koszt auta |
| :--- | :--- | :--- |
| 0 – 119 kursów | **450 PLN** | 900 PLN |
| 120 – 169 kursów | **350 PLN** | 700 PLN |
| 170 – 219 kursów | **250 PLN** | 500 PLN |
| 220 – 269 kursów | **150 PLN** | 300 PLN |
| 270+ kursów | **50 PLN** | 100 PLN |
*(Gdy zniżka najmu jest wyłączona przełącznikiem: stała opłata bazowa 450 PLN na kierowcę)*

#### 3. Tryb Trio (Trzech kierowców dzielących auto)
Opłata na kierowcę to płaski podział faktury ERES (suma / 3), nie podział ważony liczbą kursów.

| Łączna liczba kursów auta | Koszt na kierowcę | Łączny koszt auta | Min. akceptacja |
| :--- | :--- | :--- | :--- |
| 0 – 139 kursów | **300 PLN** | 900 PLN | brak |
| 140 – 189 kursów | **235 PLN** | 705 PLN | 80% |
| 190 – 239 kursów | **167 PLN** | 501 PLN | 70% |
| 240 – 289 kursów | **100 PLN** | 300 PLN | 60% |
| 290+ kursów | **33 PLN** | 99 PLN | 50% |
*(Gdy zniżka najmu jest wyłączona przełącznikiem: stała opłata bazowa 300 PLN na kierowcę / 900 PLN za auto)*

### Rozdział kursów: driverTripCount vs. carTripCount
W modelu danych [`WeekEarning`](lib/earnings_models.dart) występuje ścisły rozdział odpowiedzialności liczników:
- `driverTripCount` — **wyłącznie osobiste kursy danego kierowcy**. To ta wartość jest bezwzględnie sumowana do długoterminowego licznika przebiegu (odometru) monitorującego próg darmowego tygodnia najmu (2000 kursów).
- `carTripCountOverride` — opcjonalna, łączna liczba kursów wykonanych autem w trybie współdzielonym (2 lub 3 kierowców). Właściwość pomocnicza `carTripCount` przyjmuje tę wartość wyłącznie do ustalenia progu najmu (`RENTAL_TIERS_PAIRED` albo `RENTAL_TIERS_TRIO`). Kursy partnerów **nigdy nie zanieczyszczają osobistego kamienia milowego**.
- **Tydzień niezaraportowany (`isUnreported`):** wpis z `netIncome == 0 && onlineHours == 0 && driverTripCount == 0` to placeholder po szybkim dodaniu paliwa w środku tygodnia. `rentalFee` i `totalCarRentalFee` zwracają **0**, dopóki kierowca nie uzupełni danych Ubera — w przeciwnym razie poniedziałek z paragonem doliczał ~900 PLN najmu do miesięcznego i rocznego salda.

### Średnia stawka godzinowa (blended vs unweighted)
- `averageHourlyRate` — średnia **nieważona** stawek tygodniowych (każdy tydzień liczy się tak samo).
- `blendedHourlyRate` — `suma(netProfit) / suma(onlineHours)`, identycznie jak `MonthSummary.avgHourlyRate` i `YearSummary.avgHourlyRate`.
- Wykres trendu 4-tygodniowego **musi** używać `blendedHourlyRate`. Przykład: 10 h @ 50 PLN/h + 40 h @ 1,25 PLN/h → nieważone 25,63, blended **11,00**.

### Próg rentowności (Break-Even)
Aplikacja w czasie rzeczywistym wskazuje obrót brutto, od którego kierowca zaczyna zarabiać na czysto:
$$\text{Break-Even} = \frac{\text{Koszty Stałe (Paliwo po rabacie + Koszt najmu)}}{\text{1} - \text{FLAT\_VAT\_RATE (0.12)} - \text{SETTLEMENT\_FEE\_RATE (0.043125)}} = \frac{\text{Koszty Stałe}}{\text{0.836875}}$$

---

## 6. Bezpieczeństwo, Prywatność i Integralność Danych

- **Dane na urządzeniu:** Księgowość i historia w `SharedPreferences`, liczniki zmiany i dziennik stuknięć w plikach aplikacji. Kopia zapasowa w chmurze wyłączona (`android:allowBackup="false"`). Te dane nie są wysyłane.
- **GitHub tylko za zgodą albo na żądanie:** Przy pierwszym uruchomieniu tej wersji (także u kogoś, kto aktualizuje starszą) pada jedno pytanie. „Zezwól” włącza oba przełączniki, „Nie, tylko gdy poproszę” zostawia je wyłączone. Da się je zmienić w ustawieniach. Dopóki oba są wyłączone i kierowca nic nie stuknie, aplikacja nie otwiera połączenia. Wychodzą wtedy wyłącznie adres IP i standardowe nagłówki (między innymi `Accept` i `User-Agent: RateHelper-Updater` przy sprawdzeniu aktualizacji) — bez przejazdów, zarobków ani identyfikatora konta.
  - `gist.githubusercontent.com` — manifest aktualizacji
  - `api.github.com` — zapas, tylko gdy manifest podczas tego samego sprawdzenia się nie wczyta
  - `github.com` i przekierowania `*.githubusercontent.com` — APK po stuknięciu aktualizacji
  - `raw.githubusercontent.com` — JSON wydarzeń
- **Zaciemnianie `envied` (to nie sekret):** Adres URL manifestu Gist i oczekiwany skrót certyfikatu APK trafiają do wygenerowanego `env.g.dart` jako tablice XOR. Utrudnia to odczyt ciągu w pliku binarnym. Nie szyfruje wartości i nie ukrywa ich przed kimś, kto uruchomi albo zdekompiluje aplikację — zaciemnienie nie jest tajemnicą.
- **Ostrzeżenie o naruszeniu sygnatury (to nie granica bezpieczeństwa):** W buildzie release aplikacja porównuje skrót certyfikatu z `package_info_plus` z wartością z `.env`. Przy rozbieżności kierowca widzi ostrzeżenie, po czym aplikacja się zamyka. To sygnał o możliwej podmianie APK. Przepakowany pakiet może ten kod usunąć. Granicą instalacji pozostaje podpis Androida (keystore z `key.properties`; brak `key.properties` → build release kończy się błędem Gradle, bez cichego podpisu debug).
- **Brama instalacji OTA:** Przed `startActivity` instalatora Kotlin weryfikuje pakiet `com.ratehelper.app`, wyższy `versionCode`, ten sam SHA-256 certyfikatu co zainstalowana aplikacja oraz (opcjonalnie) `apk_sha256` z manifestu Gist. Pobranie tylko z przycisku aktualizacji; strumieniowy SHA-256, limit 100 MB, magic ZIP `PK`.
- **Odporność na błędy formatowania:** Filtry `LengthLimitingTextInputFormatter(7)` oraz rygorystyczna obsługa separatorów dziesiętnych zapobiegają błędom przepełnienia bufora i błędnemu parsowaniu kwot.

---

## 7. Model dystrybucji (Brak Play Store)

Aplikacja **nie jest i nie będzie publikowana w sklepie Google Play**. Dystrybucja odbywa się w modelu bezpośrednim (**Sideloaded APK**):

1. **Ryzyko weryfikacji uprawnień nakładki:** Google Play nakłada drastyczne ograniczenia na uprawnienie `SYSTEM_ALERT_WINDOW` (rysowanie na wierzchu) oraz usługi ułatwień dostępu (`AccessibilityService`), regularnie odrzucając aplikacje narzędziowe stworzone dla kierowców.
2. **Bez sklepu i bez własnego serwera:** Wydania leżą na GitHub Releases, manifest na Gist. Nie ma konta ani backendu z danymi kierowcy. Kontakt z GitHubem następuje tylko po zgodzie na automatyczne sprawdzenia albo po ręcznym żądaniu. To daje niezależność od review Google bez udawania, że aplikacja w ogóle nie korzysta z sieci.
3. **Optymalizacja pod architekturę kierowców:** Budowanie paczek `split-per-abi` zmniejsza rozmiar pobieranego pliku APK z ~60 MB do zaledwie ~21 MB dla urządzeń `arm64-v8a` (np. Samsung Galaxy S24 Ultra).

### Przepływ OTA (v5)

```
Jednorazowa zgoda GitHub (github_network_prompt_answered)
        │
        ├─► auto wyłączone → brak sieci przy starcie
        │
        ▼
Cold start: checkOnStartup() tylko gdy włączone auto-aktualizacje
Ręcznie: Ayarlar → Güncellemeleri denetle → UpdateService.check()
        │
        ▼
UpdateService.check() / checkOnStartup()
        │
        ├─► GET manifest Gist (z parametrem anty-cache)
        │         │
        │         ├─ latest, build, apk_url, notes_*
        │         └─ allowlist hostów + brak follow redirects
        │
        ├─► (zapas) GET api.github.com/.../releases/latest
        │
        ▼
AppVersion.parse + porównanie numeryczne (semver + build)
        │
        ├─► brak nowszej → toast „Masz najnowszą wersję”
        │
        └─► nowsza → UpdateDialog
                  │
                  ├─► canInstallPackages? → ustawienia Androida
                  ├─► downloadApk() → cache/updates/ (weryfikacja rozmiaru + PK)
                  ├─► installApk() → FileProvider → ACTION_VIEW
                  └─► błąd → launchDownload() (przeglądarka)
```

**Wyrównanie wersji (obowiązkowe przy każdym release):** `pubspec.yaml`, pole Gist `"latest"`, pole Gist `"build"` (numer z pubspec, **nie** versionCode z offsetem ABI), tag GitHub Release oraz plik asset muszą opisywać **tę samą** wersję binarną wskazaną przez `apk_url`. Szablon manifestu: [`release/update.json`](release/update.json).

| Dokument | Cel |
|---|---|
| [`release/YAYIN_TR.md`](release/YAYIN_TR.md) | Publikacja krok po kroku (TR) |
| [`release/GITHUB_RELEASE_CHECKLIST.md`](release/GITHUB_RELEASE_CHECKLIST.md) | Checklist EN + smoke test |
| [`release/update.json`](release/update.json) | OTA manifest (Gist şablonu) + `notes_*` (GitHub Release metni) |
| [`release/RELEASE_NOTES_v5.0.4_*.md`](release/RELEASE_NOTES_v5.0.4_TR.md) | Pełne notatki dla kierowcy (TR / PL / EN) |
| [`release/CHANGELOG_v5.0.4.md`](release/CHANGELOG_v5.0.4.md) | Lista zmian dla maintainerów |

**Offset versionCode przy `--split-per-abi`:** arm64 build `7` → `versionCode` **2007** (`2×1000+7`). `UpdateService.pubspecBuildNumber()` redukuje `% 1000` przed porównaniem z polem `"build"` w manifeście.

---

## 8. Procedura kompilacji wydania produkcyjnego (Release Build)

Do przygotowania oficjalnego, zoptymalizowanego wydania produkcyjnego służy poniższa, ścisła procedura:

### 1. Przygotowanie klucza podpisującego (`key.properties`)
Upewnij się, że w głównym katalogu projektu znajduje się plik `key.properties` (plik ten jest dodany do `.gitignore` i **nigdy nie może trafić do repozytorium**):
```properties
storeFile=/sciezka/do/twojego_keystore.jks
storePassword=haslo_keystore
keyAlias=RateHelper
keyPassword=haslo_klucza
```

Release (`flutter build apk --release` i zadania `*Release`) **przerywa się `GradleException`**, gdy plik nie istnieje albo nie daje się go odczytać. Nie ma cichego podpisu kluczem debug. Build debug działa bez tego pliku.

### 2. Generowanie kodu zaciemniającego
Przed kompilacją należy wygenerować klasy `envied` na podstawie lokalnego pliku `.env`:
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Kompilacja produkcyjna ze stripowaniem i obfuskacją
Oficjalne polecenie budowania paczek APK:
```bash
flutter clean && dart run build_runner build --delete-conflicting-outputs && flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/
```

> **Krytyczny wymóg archiwizacji symboli:**  
> Katalog `symbols/` wygenerowany podczas kompilacji **musi zostać zarchiwizowany przez wydawcę dla każdej opublikowanej wersji**. Ponieważ kod produkcyjny jest poddawany zaciemnianiu (`--obfuscate`), zrzuty błędów z pliku `crash.log` zgłaszane przez kierowców będą zawierać zaszyfrowane ścieżki stosu. Ich odszyfrowanie możliwe jest wyłącznie przy użyciu zachowanego katalogu symboli danej kompilacji (`flutter symbolize`).

Wygenerowany plik produkcyjny dla nowoczesnych smartfonów:  
`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

---

## 9. Struktura plików projektu

```
lib/
├── main.dart                  # Wstępna konfiguracja, inicjalizacja wątków
├── home_screen.dart           # Główny kokpit, liczniki ValueNotifier, reset tygodnia, plakietka KK383CT
├── settings_screen.dart       # Wszystkie ustawienia, UpdateCheckTile, przewodnik konfiguracji
├── github_consent_dialog.dart # Jednorazowa zgoda na połączenia GitHub
├── weekly_archive_card.dart   # Rozwijalne karty archiwum tygodni (zakładka Logi)
├── update_dialog.dart         # Dialog aktualizacji OTA + UpdateCheckTile (używany w Settings)
├── app_spacing.dart           # [DESIGN SYSTEM] Tokeny odstępów (AppSpacing) i zaokrągleń (AppRadius)
├── app_text_styles.dart       # [DESIGN SYSTEM] Skala typograficzna (AppTextStyles) i cyfry tabelaryczne
├── app_colors.dart            # [DESIGN SYSTEM] 3-tonowe tła OLED, recordGold, designerGold, actionAccent
├── app_widgets.dart           # [DESIGN SYSTEM] Przycisk podstawowy, dodatkowy, ikony i stany puste
├── earnings_models.dart       # Silnik ERES, VAT 12% / opłata 4.3125%, blendedHourlyRate, isUnreported
├── earnings_screen.dart       # Tygodniowy arkusz zarobków, lista paragonów, wykresy i wskaźniki
├── earnings_pdf_export.dart   # Generator miesięcznych i rocznych raportów PDF dla księgowości
├── radar_screen.dart          # Kalendarz i wskaźnik zapotrzebowania imprez masowych w Krakowie
├── overlay_widget.dart        # Pigułka nakładki: 276×80 dp poziomo / 74×194 dp pionowo
├── overlay_sync.dart          # Bezpośredni protokół synchronizacji liczników IPC
├── shift_counter_store.dart   # Trwały magazyn liczników bieżącej zmiany (shift_counters.json)
├── tap_history_store.dart     # Dziennik kliknięć typu append-only (tap_history.jsonl, max 500)
├── onboarding_screen.dart     # Asystent przyznawania uprawnień systemowych (Nakładka + Bateria)
├── fonts.dart                 # Deklaracje lokalnych rodzin czcionek (DM Sans, JetBrains Mono)
├── l10n.dart                  # Wielojęzyczność (TR / EN / PL) oraz lokalne formatowanie walutowe
├── crash_logger.dart          # Lokalny bufor dziennika awarii i błędów (crash.log)
├── models/
│   ├── event_model.dart       # Struktura danych wydarzenia masowego (Radar)
│   └── weekly_archive_entry.dart # Model archiwalny podsumowań tygodniowych (v2 JSON)
└── services/
    ├── event_service.dart     # Pobieranie i buforowanie danych krakow_events.json
    ├── github_access.dart     # Przełączniki auto-update / auto-events, promptSettled
    ├── github_http.dart       # HttpClient z allowlistą hostów GitHub
    ├── apk_install_check.dart # Wspólna brama podpisu/wersji przed instalacją
    └── update_service.dart    # Manifest Gist, semver, pobieranie APK, instalacja natywna

android/
├── build.gradle.kts           # Konfiguracja nadrzędna z obejściem Kotlin DSL dla modułu :jni
└── app/
    ├── build.gradle.kts       # Konfiguracja aplikacji, weryfikacja key.properties, desugaring
    └── src/main/kotlin/com/ratehelper/app/
        ├── MainActivity.kt    # MethodChannel: bateria, A11y, drainPendingTaps, installApk (FileProvider)
        └── MediaKeyAccessibilityService.kt # Przechwytywanie przycisków na kierownicy
```

---

> **RateHelper v5.0.4** — Bezkompromisowe narzędzie stworzone z perspektywy fotela kierowcy. Realna kontrola zysków na krakowskich drogach.
