# RateHelper v5 — Podręcznik Architektury i Dokumentacja Operacyjna

> **Identyfikator aplikacji:** `com.ratehelper.app`  
> **Platforma docelowa:** Android (arm64-v8a, zoptymalizowane pod flagowce typu Samsung Galaxy S24 Ultra)  
> **Framework:** Flutter (Dart) + Natywny Kotlin/Java (Android OS Layer)  
> **Wersja bieżąca:** `5.0.1+6` (versionName `5.0.1`, pubspec build `6`, arm64 versionCode `2006`)

---

## Spis treści

1. [Tożsamość i cel aplikacji](#1-tożsamość-i-cel-aplikacji)
2. [Główne moduły funkcjonalne](#2-główne-moduły-funkcjonalne)
3. [Architektura systemu i dwuizolatowość (Isolates)](#3-architektura-systemu-i-dwuizolatowość-isolates)
4. [System Designu i Tokenizacja UI (Design System)](#4-system-designu-i-tokenizacja-ui-design-system)
5. [Silnik finansowy i parametry partnera ERES](#5-silnik-finansowy-i-parametry-partnera-eres)
   - [Stawki podatkowe i prowizje](#stawki-podatkowe-i-prowizje)
   - [Tabele progowe najmu (Solo vs. Paired)](#tabele-progowe-najmu-solo-vs-paired)
   - [Rozdział kursów: driverTripCount vs. carTripCount](#rozdział-kursów-drivertripcount-vs-cartripcount)
   - [Próg rentowności (Break-Even)](#próg-rentowności-break-even)
6. [Bezpieczeństwo, Prywatność i Integralność Danych](#6-bezpieczeństwo-prywatność-i-integralność-danych)
7. [Model dystrybucji (Brak Play Store)](#7-model-dystrybucji-brak-play-store)
8. [Procedura kompilacji wydania produkcyjnego (Release Build)](#8-procedura-kompilacji-wydania-produkcyjnego-release-build)
9. [Struktura plików projektu](#9-struktura-plików-projektu)

---

## 1. Tożsamość i cel aplikacji

**RateHelper** to zaawansowany, całkowicie lokalny asystent kierowcy rideshare (Uber/Bolt) operującego w **Krakowie** w ramach partnerstwa flotowego **ERES Partner**. Aplikacja łączy w jednym, zoptymalizowanym pod kątem jazdy środowisku:
- Pływający widget nakładki (Floating Pill Overlay) zawieszony bezpośrednio nad aplikacją kierowcy,
- Kalkulator wskaźnika akceptacji (Acceptance Rate) z dynamicznym systemem ostrzegania i celem tygodniowym,
- Precyzyjny moduł księgowo-rozliczeniowy wyliczający realny zysk netto po odliczeniu podatku ryczałtowego VAT, prowizji partnera, progów najmu i rabatów paliwowych,
- Niezależny drogomierz kursów osobistych zliczający postęp do darmowego tygodnia najmu (kamień milowy 2000 kursów),
- Radar wydarzeń masowych w Krakowie (Tauron Arena, stadiony) przewidujący strefy podwyższonego popytu (surge),
- Pełne wsparcie trójjęzyczne: Turecki (domyślny), Polski oraz Angielski.

### Główne zasady projektowe
- **100% Local Finance:** Wszystkie dane finansowe, paragony paliwowe i statystyki pozostają wyłącznie na urządzeniu kierowcy. Brak zewnętrznych baz danych, brak telemetrii, brak kont użytkowników.
- **Driving-First UI:** Ekstremalny ciemny motyw OLED, dotykowe punkty interakcji spełniające normy bezpieczeństwa (minimum 48–68 dp) oraz selektywna haptyka dostosowana do obsługi w uchwycie samochodowym.
- **Kompaktowość i płynność:** Niski narzut na baterię i pamięć RAM podczas 12-godzinnych zmian roboczych.

---

## 2. Główne moduły funkcjonalne

| Moduł | Opis Funkcjonalny | Mechanizm Implementacji |
| :--- | :--- | :--- |
| **Pływająca Nakładka (Pill Overlay)** | Widget **276×80 dp** (Yatay / poziomo) lub **74×194 dp** (Dikey / pionowo) wiszący nad aplikacją Uber/Bolt Driver. Natychmiastowe zliczanie zleceń (+/−) bez opuszczania ekranu mapy. Kierunek: ustawienie **Baloncuk Yönü**. | Osobny, odchudzony izolat Fluttera (`packages/flutter_overlay_window`), natywny `WindowManager.updateViewLayout()`, okno natywne = widoczny stadion (brak martwego pola dotyku). Zmiana orientacji zamyka i otwiera nakładkę na nowo — **bez** `resizeOverlay` z izolatu głównego. |
| **Pulpit Akceptacji (AR) i Odzyskiwania** | Precyzyjny licznik zleceń (Zaakceptowane, Odrzucone, Ukończone, Anulowane). Dynamiczny bufor ostrzegawczy (2.0% wokół progu celu) oraz kalkulator liczby kursów potrzebnych do odzyskania bezpiecznego wskaźnika. | `home_screen.dart`, wzór odzyskiwania $X = \max(1, \lfloor \frac{r \cdot R - (1-r) \cdot A}{1-r} \rfloor + 1)$, reaktywne notifiery `ValueNotifier`. |
| **Śledzenie Zarobków i Podatków** | Tygodniowy arkusz rozliczeniowy: VAT 12%, opłata ERES 4.3125%, paliwo −10%, najem progowy. Trend 4-tygodniowy i karty miesiąc/rok używają **`blendedHourlyRate`** (zysk ÷ godziny). Tydzień-placeholder paliwa (`isUnreported`) nie dolicza najmu. | `earnings_screen.dart`, `earnings_models.dart`, podgląd live. |
| **Paragony Paliwowe (Multi-Receipt)** | Rejestracja wielu paragonów paliwowych w danym tygodniu z pełnym formatowaniem walutowym, usuwaniem gestem z opcją cofnięcia (Undo SnackBar) i limitem FIFO (max 100). | `_buildFuelReceiptsSection`, `PolishCurrencyInputFormatter`, formatowanie walutowe zgodne z polskim standardem (`1 250,50 PLN`). |
| **Tryby Najmu: Solo vs. Paired** | Dynamiczne dopasowanie kosztu najmu auta w zależności od jednoosobowej lub dwuosobowej obsady pojazdu. | `DriverMode.solo` / `DriverMode.paired`, odrębne tabele progowe, bezwzględna niezmienność historyczna zapisanych wpisów. |
| **Rozdział Liczników Kursów** | Kursy osobiste kierowcy zliczają postęp do darmowego tygodnia (próg 2000), podczas gdy suma kursów auta w trybie współdzielonym decyduje o progu zniżki najmu. | `driverTripCount` (odometer) oraz `carTripCountOverride` (tier lookup). |
| **Radar Wydarzeń (Kraków)** | Asynchroniczny kalendarz imprez masowych w Krakowie prognozujący godziny szczytów i skoków mnożników stawek. | `radar_screen.dart`, pobieranie `krakow_events.json` z GitHub z godzinnym buforowaniem pamięci RAM, etykiety względne (Dziś/Jutro). |
| **Integracja z Przyciskami na Kierownicy** | Rejestracja zleceń za pomocą bezprzewodowego pilota multimedialnego Bluetooth na kierownicy bez odrywania rąk. | `MediaKeyAccessibilityService.kt`: długie przytrzymanie >800 ms; ACK nakładki 1200 ms + `recordPendingTap`; `drainPendingTaps` odejmuje (nie czyści); `_drainPendingTaps` dopiero po `await _loadAndCheckReset()`. |
| **Raporty PDF do Księgowości** | Generowanie miesięcznych lub rocznych zestawień przychodów i kosztów z podziałem ryczałtowym gotowych do przekazania księgowej. | `earnings_pdf_export.dart`, formatowanie `pdf`, czcionki DM Sans ładowane lokalnie z assetów. |
| **Sprawdzanie i instalacja aktualizacji (OTA)** | Sprawdzenie przy starcie (nieblokujące) + ręczny kafel **Sprawdź aktualizacje** w stopce ustawień. Pobieranie APK w aplikacji (~21 MB), pasek postępu, uruchomienie natywnego instalatora Androida; przeglądarka tylko jako zapas. | `lib/services/update_service.dart`, `lib/update_dialog.dart`, manifest Gist (`Env.gistUrl`) + zapas GitHub Releases API, `FileProvider`, `REQUEST_INSTALL_PACKAGES`, omijanie cache CDN Gist (`?_=` timestamp). |

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
3. **Synchronizacja stanów bez blokowania wątku:** Liczniki bieżącej zmiany zapisywane są do lekkiego pliku `shift_counters.json` (`ShiftCounterStore`), a dziennik kliknięć do dopisywanego pliku `tap_history.jsonl` (`TapHistoryStore`, max 500 wpisów). Komunikacja między izolatami przesyła wartości bezpośrednio w ładunku wiadomości IPC — eliminuje to kosztowne przeładowania pliku SharedPreferences XML (`prefs.reload()`) przy każdym tapnięciu. `prefs.reload()` wyłącznie przy starcie izolatu nakładki.
4. **Slop przeciągania 20 dp (nie 20 px):** Na S24 Ultra (~3×) 20 pikseli fizycznych ≈ 7 dp i kradnie tapnięcia. Po przekroczeniu progu natywny `onTouch` wysyła do Fluttera `ACTION_CANCEL`, potem konsumuje MOVE/UP. Silnik nakładki jest niszczony w `OverlayService.onDestroy` (prawdziwy restart izolatu).

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
| **Złoto sygnatury KK4181R** | Szary chip 11 px | `AppColors.designerGold` | `0xFFD4AF37` (plakietka metaliczna, `ShaderMask`, halo) |
| **Błękit interakcji i akcji** | Złoto / Morski | `AppColors.actionAccent` | `0xFF38BDF8` (Dodawanie paragonów, przyciski akcji) |

### Zasady typografii i ikonografii
- **Monospace wyłącznie do tabel walutowych i plakietki KK4181R:** Czcionka `JetBrains Mono` jest zarezerwowana **wyłącznie** dla wyrównanych w kolumnach kwot walutowych PLN oraz złotej sygnatury projektanta (`KK4181R`) na stopce ekranu głównego.
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

### Tabele progowe najmu (Solo vs. Paired)

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

### Rozdział kursów: driverTripCount vs. carTripCount
W modelu danych [`WeekEarning`](lib/earnings_models.dart) występuje ścisły rozdział odpowiedzialności liczników:
- `driverTripCount` — **wyłącznie osobiste kursy danego kierowcy**. To ta wartość jest bezwzględnie sumowana do długoterminowego licznika przebiegu (odometru) monitorującego próg darmowego tygodnia najmu (2000 kursów).
- `carTripCountOverride` — opcjonalna, łączna liczba kursów wykonanych autem przez obu kierowców w trybie współdzielonym. Właściwość pomocnicza `carTripCount` przyjmuje tę wartość wyłącznie do ustalenia progu najmu w tabeli `RENTAL_TIERS_PAIRED`. Kursy partnera **nigdy nie zanieczyszczają osobistego kamienia milowego**.
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

- **Lokalna piaskownica (Zero Cloud):** Księgowość i historia w `SharedPreferences`, pliki binarne i JSON w dedykowanym katalogu aplikacji. Wyłączona kopia zapasowa w chmurze (`android:allowBackup="false"`).
- **Zaciemnianie sekretów w kodzie:** Adres URL manifestu aktualizacji Gist oraz oczekiwana sygnatura certyfikatu APK są zaciemniane w procesie kompilacji za pomocą biblioteki `envied` (tablice XOR zamiast jawnego tekstu).
- **Samoweryfikacja sygnatury APK (Signature Self-Verification):** Przy starcie w trybie release aplikacja odczytuje hash certyfikatu za pomocą `package_info_plus` i porównuje go ze skrótem weryfikacyjnym. W razie wykrycia modyfikacji lub przepakowania APK przez osoby trzecie wyświetlane jest ostrzeżenie o naruszeniu integralności.
- **Ścisłe wymuszenie TLS (Global TLS Hardening):** Klasa `StrictSecurityHttpOverrides` globalnie odrzuca nieprawidłowe certyfikaty, połączenia nieszyfrowane oraz próby ataków typu Man-in-the-Middle na wszystkich żądaniach `HttpClient`.
- **Odporność na błędy formatowania:** Filtry `LengthLimitingTextInputFormatter(7)` oraz rygorystyczna obsługa separatorów dziesiętnych zapobiegają błędom przepełnienia bufora i błędnemu parsowaniu kwot.

---

## 7. Model dystrybucji (Brak Play Store)

Aplikacja **nie jest i nie będzie publikowana w sklepie Google Play**. Dystrybucja odbywa się w modelu bezpośrednim (**Sideloaded APK**):

1. **Ryzyko weryfikacji uprawnień nakładki:** Google Play nakłada drastyczne ograniczenia na uprawnienie `SYSTEM_ALERT_WINDOW` (rysowanie na wierzchu) oraz usługi ułatwień dostępu (`AccessibilityService`), regularnie odrzucając aplikacje narzędziowe stworzone dla kierowców.
2. **Zero zależności od zewnętrznych serwerów:** Aplikacja w 100% działa lokalnie. Publikacja wydań binarnych na GitHub Releases w połączeniu ze sprawdzaniem pliku manifestu w GitHub Gist zapewnia pełną niezależność, bezpłatną infrastrukturę i natychmiastowe wdrażanie poprawek bez oczekiwania na review Google.
3. **Optymalizacja pod architekturę kierowców:** Budowanie paczek `split-per-abi` zmniejsza rozmiar pobieranego pliku APK z ~60 MB do zaledwie ~21 MB dla urządzeń `arm64-v8a` (np. Samsung Galaxy S24 Ultra).

### Przepływ OTA (v5)

```
Cold start / ręczne „Sprawdź aktualizacje”
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

**Wyrównanie wersji (obowiązkowe przy każdym release):** `pubspec.yaml`, pole Gist `"latest"`, pole Gist `"build"` (numer z pubspec, **nie** versionCode z offsetem ABI), tag GitHub Release oraz plik asset muszą opisywać **tę samą** wersję binarną wskazaną przez `apk_url`. Szablon manifestu: [`release/update.json`](release/update.json). Notatki wydania PL: [`release/RELEASE_NOTES_v5_PL.md`](release/RELEASE_NOTES_v5_PL.md).

**Offset versionCode przy `--split-per-abi`:** arm64 build `6` → `versionCode` **2006** (`2×1000+6`). `UpdateService.pubspecBuildNumber()` redukuje `% 1000` przed porównaniem z polem `"build"` w manifeście.

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
├── main.dart                  # Wstępna konfiguracja, StrictSecurityHttpOverrides, inicjalizacja wątków
├── home_screen.dart           # Główny kokpit, liczniki ValueNotifier, Baloncuk Yönü, plakietka KK4181R
├── update_dialog.dart         # Dialog aktualizacji OTA + kafel „Sprawdź aktualizacje”
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
├── secure_http.dart           # Rygorystyczny certyfikat TLS (StrictSecurityHttpOverrides)
├── crash_logger.dart          # Lokalny bufor dziennika awarii i błędów (crash.log)
├── models/
│   ├── event_model.dart       # Struktura danych wydarzenia masowego (Radar)
│   └── weekly_archive_entry.dart # Model archiwalny podsumowań tygodniowych (v2 JSON)
└── services/
    ├── event_service.dart     # Pobieranie i buforowanie danych krakow_events.json
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

> **RateHelper v5** — Bezkompromisowe narzędzie stworzone z perspektywy fotela kierowcy. Realna kontrola zysków na krakowskich drogach.
