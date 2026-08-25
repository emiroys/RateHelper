# RateHelper v1.0 — Podręcznik Architektury i Dokumentacja Operacyjna

> **Identyfikator aplikacji:** `com.ratehelper.app`  
> **Platforma docelowa:** Android (arm64-v8a, zoptymalizowane pod flagowce typu Samsung Galaxy S24 Ultra)  
> **Framework:** Flutter (Dart) + Natywny Kotlin/Java (Android OS Layer)  
> **Wersja:** `1.0.2+2`

---

## Spis treści

1. [Tożsamość i cel aplikacji](#1-tożsamość-i-cel-aplikacji)
2. [Główne funkcje (Zaktualizowana matryca v1.0)](#2-główne-funkcje-zaktualizowana-matryca-v10)
3. [Architektura systemu i wielowątkowość (Isolates)](#3-architektura-systemu-i-wielowątkowość-isolates)
4. [Szczegółowa specyfikacja modułów](#4-szczegółowa-specyfikacja-modułów)
   - [Moduł I: Pulpit Wskaźników i Kalkulator Odzysku](#moduł-i-pulpit-wskaźników-i-kalkulator-odzysku)
   - [Moduł II: Natywna Nakładka na Żywo (Pill Overlay)](#moduł-ii-natywna-nakładka-na-żywo-pill-overlay)
   - [Moduł III: Zaawansowany Silnik Księgowy (Kary/Zyski)](#moduł-iii-zaawansowany-silnik-księgowy-karyzyski)
   - [Moduł IV: Tryb Solo vs. Paired (Podział Kosztów)](#moduł-iv-tryb-solo-vs-paired-podział-kosztów)
   - [Moduł V: Radar Wydarzeń (Kraków)](#moduł-v-radar-wydarzeń-kraków)
   - [Moduł VI: Integracja Sprzętowa (Bluetooth Media Keys)](#moduł-vi-integracja-sprzętowa-bluetooth-media-keys)
5. [Bezpieczeństwo, Prywatność i Integralność Danych](#5-bezpieczeństwo-prywatność-i-integralność-danych)
6. [Budowanie ze źródeł i pokrycie testowe](#6-budowanie-ze-źródeł-i-pokrycie-testowe)
7. [Mapa plików projektu](#7-mapa-plików-projektu)
8. [Dokumentacja dla kierowców i agentów](#8-dokumentacja-dla-kierowców-i-agentów)

---

## 1. Tożsamość i cel aplikacji

**RateHelper** to zaawansowany, całkowicie lokalny asystent narzędziowy stworzony dla kierowców rideshare (Uber/Bolt) operujących w **Krakowie**. Aplikacja rozwiązuje kluczowe problemy operacyjne kierowców zawodowych, łącząc w jednym interfejsie bezdyskusyjną matematykę zysków, predykcję stref podwyższonego popytu (surge) oraz automatyzację rejestracji zleceń bez odrywania rąk od kierownicy.

### Główne zasady projektowe

- **100% Local Finance:** Wszystkie dane finansowe i statystyki pozostają na urządzeniu. Ustawienia, archiwum i księgowość — `SharedPreferences`; liczniki zmiany — `shift_counters.json`; dziennik tapnięć — `tap_history.jsonl`. Brak zewnętrznej telemetrii i kont użytkowników. Jedyny ruch sieciowy: aktualizacje APK, publiczny radar wydarzeń Kraków.
- **Driving-First UI:** Ekstremalny ciemny motyw (True Dark), gigantyczne punkty dotykowe (XL Targets) oraz haptyka zwrotna dostosowana do obsługi urządzenia w uchwycie samochodowym.
- **Trójjęzyczność:** Pełna lokalizacja interfejsu w językach: Tureckim (domyślny), Polskim oraz Angielskim.

---

## 2. Główne funkcje (Zaktualizowana matryca v1.0)

| Moduł | Opis Funkcjonalny | Mechanizm Implementacji |
| --- | --- | --- |
| **Pływająca Nakładka** | Widget 276×80 dp wiszący bezpośrednio nad aplikacją Uber/Bolt Driver, pozwalający na rejestrację kliknięć bez opuszczania nawigacji. | Osobny izolat Flutter z **chudym** silnikiem (bez url_launcher/share_plus/wakelock); natywny `WindowManager`; drag **konsumuje** gest po 20 px slop (brak phantom tapów). |
| **Ekran zawsze włączony** | Opcjonalny wakelock na uchwycie deski rozdzielczej (domyślnie wyłączony). | Pref `keepScreenOn` + `WakelockPlus`; timeout 10 min bez interakcji. |
| **3-Stanowy Alert AR** | Inteligentne monitorowanie wskaźnika akceptacji (AR) z dynamicznym systemem wczesnego ostrzegania (Zielony/Żółty/Czerwony). | Algorytm sprawdzający bufor bezpieczeństwa `AMBER_BUFFER = 2.0%` wokół progu wybranego celu. |
| **Silnik Księgowy** | Precyzyjny kalkulator rentowności tygodniowej z automatycznym odliczaniem podatków, prowizji rozliczeniowej i paliwa. | Mapowanie VAT ryczałtowego (12%), opłaty rozliczeniowej partnera (3%) oraz progów najmu zależnych od liczby kursów. |
| **Tryby Jazdy (1 vs 2)** | Elastyczne przełączanie profilu kosztów w zależności od tego, czy kierowca jeździ sam, czy dzieli auto na zmiany. | Dynamiczne tabele progowe `RENTAL_TIERS` i `RENTAL_TIERS_PAIRED` działające w sposób odporny na modyfikacje wsteczne. |
| **Surge Radar** | Kalendarz masowych imprez w Krakowie (Tauron Arena, mecze Wisły/Cracovii) przewidujący skoki mnożników. | Pobieranie publicznego `krakow_events.json` z GitHub; cache RAM 1 h; top 5 nadchodzących wydarzeń. |
| **Obsługa Bluetooth** | Logowanie zleceń (Akceptacja/Odrzucenie) za pomocą fabrycznych przycisków multimedialnych na kierownicy pojazdu. | Natywna usługa `AccessibilityService` przechwytująca zdarzenia `KeyEvent` w tle systemu Android. |
| **Niezależny Drogomierz** | Niezatracalny licznik podróży całkowitych monitorujący postęp do darmowego tygodnia najmu (próg 2000 kursów). | Zdecouple'owany licznik oparty na przyrostach różnicowych (delta), odporny na dwuletnie czyszczenie historii (FIFO). |
| **Eksport PDF** | Miesięczne/roczne zestawienia zarobków do księgowej (ryczałt). | `earnings_pdf_export.dart` — `pdf` + `share_plus`; czcionki DM Sans z bundla (TR/PL). |
| **Archiwum tygodniowe v2** | Historia resetów tygodnia z pełnymi licznikami i wskaźnikami. | JSON `v2` w `weekly_archive_entry.dart`; kompatybilność wsteczna ze starymi wpisami tekstowymi. |
| **Czcionki bundlowane** | Zero pobierania fontów w runtime (cold install bez internetu). | `fonts.dart` + `app_text_styles.dart`; pakiet `google_fonts` usunięty. |
| **Aktualizacja OTA (APK)** | Powiadomienie o nowej wersji + pobieranie APK z GitHub Releases. | Manifest Gist (`update.json`) + semver; arm64 split APK. |

---

## 3. Architektura systemu i wielowątkowość (Isolates)

Aplikacja opiera się na **dwóch całkowicie niezależnych izolatach Flutter**, które współdzielą zasoby sprzętowe i synchronizują dane poprzez dedykowany mechanizm IPC:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Android OS Layer                            │
│   ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐ │
│   │   MainActivity   │  │  OverlayService  │  │  MediaKey A11y   │ │
│   │   (Kotlin)       │  │  (Java, forked)  │  │  (Kotlin)        │ │
│   │  MethodChannel   │  │  Natywne drag +  │  │  Przechwytywanie │ │
│   │  BroadcastRcv    │  │  FloatingWindow  │  │  KeyEvent (A11y) │ │
│   └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘ │
└────────────┼────────────────────┼────────────────────┼─────────────┘
             │ Flutter Engine     │ Overlay Isolate    │ IPC Broadcast
┌────────────┼────────────────────┼────────────────────┼─────────────┐
│            ▼                    ▼                    ▼             │
│   ┌──────────────────┐  ┌──────────────────┐                      │
│   │   HomeScreen      │  │  OverlayWidget   │ ◄─ OverlaySync payload │
│   │   (główny izolat) │  │  (izolat okna)   │    + pliki liczników   │
│   └────────┬──────────┘  └──────────────────┘                      │
│            │                                                       │
│   ┌────────┼──────────┬─────────────────┬─────────────┐           │
│   ▼        ▼          ▼                 ▼             ▼           │
│ Zarobki  Radar     Onboarding      Eksport PDF   Przypomnienia    │
└───────────────────────────────────────────────────────────────────┘
```

### Protokół synchronizacji stanów

Zapis liczników w dowolnym izolacie: **jeden** plik `shift_counters.json` + `OverlaySync.notifyCountersChanged(accepted, rejected, completed)`. Odbiorca stosuje liczby z komunikatu — **bez** `prefs.reload()` na ścieżce tapnięcia. Dziennik tapnięć to dopisywany `tap_history.jsonl` (max 500). Ustawienia (język, cel, przełączniki) zostają w SharedPreferences. Po `resumed` główny izolat scala ewentualny debounce i czyta plik liczników; pełny reload XML prefs nie jest częścią hot path.

---

## 4. Szczegółowa specyfikacja modułów

### Moduł I: Pulpit Wskaźników i Kalkulator Odzysku

Główny pulpit zarządza czterema krytycznymi licznikami: **Zaakceptowane**, **Odrzucone**, **Ukończone** oraz **Anulowane**.

- **Wskaźnik Akceptacji (AR):** Wzór: $\text{AR} = \frac{\text{zaakceptowane}}{\text{zaakceptowane} + \text{odrzucone}} \times 100$.
- **Tygodniowy cel przejazdów (`TripGoal`):** Chip u góry ekranu; progi powiązane z tabelami ERES (solo vs paired). Pref: `trip_goal_tier`.

| Tier | Solo (min. kursów) | Paired (min. kursów) | Min. AR% |
| --- | --- | --- | --- |
| tier0 | 0 | 0 | — |
| tier1 | 100 | 120 | 80 |
| tier2 | 150 | 170 | 70 |
| tier3 | 200 | 220 | 60 |
| tier4 | 250 | 270 | 50 |

- **3-Stanowy system wizualny:** Bufor `AMBER_BUFFER = 2.0%` wokół progu celu — zielony / bursztynowy (`S.safeButClose`) / karmazynowy. Poniżej progu wyliczana jest liczba ($X$) kolejnych akceptacji:

$$X = \max\left(1,\ \left\lfloor \frac{r \cdot \text{rejected} - (1-r) \cdot \text{accepted}}{1-r} \right\rfloor + 1\right)$$

- **Budżet anulowań:** Przy celu ≠ tier0 — karta pokazuje, ile anulowań mieści się w limicie **5%** (`maxAdditionalCancellations`).
- **Reset tygodnia:** Ręczny (`RESETUJ TYDZIEŃ`) lub automatyczny w **poniedziałek 04:00** (`Europe/Warsaw`). Archiwum zapisuje wpis JSON v2 przed zerowaniem liczników.
- **Nawigacja dolna (5 przycisków):** Język · Widget (Uruchom/Zatrzymaj) · Logi · Radar · Zarobki.
- **Cofnij (undo):** Jednokrokowe cofnięcie ostatniej zmiany licznika (ikona ↩ w AppBar).
- **Liczniki:** widget `_CounterRow` + `ValueNotifier` — tap +/- nie przebudowuje całego ekranu.
- **Ekran włączony:** przełącznik `S.keepScreenOn` (opt-in; 10 min bezczynności gasi wakelock).

### Moduł II: Natywna Nakładka na Żywo (Pill Overlay)

Pływająca pigułka o wymiarach 276×80 dp operuje na natywnym wątku renderowania Androida poprzez `WindowManager.updateViewLayout()`. Margines błędu dotyku: 20 px (`dx²+dy² < 400`). Po przekroczeniu slop zdarzenie jest **konsumowane** (`onTouch` → `true`), żeby wolny drag nie wpadł w 18 px slop Fluttera jako fałszywe tapnięcie (psuje AR). Silnik overlay: `setAutomaticallyRegisterPlugins(false)` — tylko IPC okna, SharedPreferences i JNI/`path_provider`. Widget używa `RepaintBoundary` oraz `T.rateFor()` (const TextStyle).

### Moduł III: Zaawansowany Silnik Księgowy (Kary/Zyski)

Kalkulator zysku netto operuje na architekturze ciągłego przeliczania wartości w czasie rzeczywistym. Formuła finansowa została zdefiniowana następująco:

```
Zysk Netto = Przychód Netto Uber
            − Paliwo po Rabacie Partnerskim (Suma Rachunków × 0.90)
            − Podatek VAT Ryczałtowy (Przychód Netto × 0.12)
            − Opłata Rozliczeniowa Partnera (Przychód Netto × 0.03)
            − Indywidualny Koszt Wynajmu (rentalFee wyliczone z tabel progowych)
```

#### Próg rentowności (Break-Even)

Aplikacja dynamicznie wskazuje kwotę obrotu, od której kierowca zaczyna zarabiać na czysto (koszty stałe = paliwo po rabacie + najem bieżącego tygodnia):

$$\text{Break-Even} = \frac{\text{Paliwo po Rabacie} + \text{Najem}}{\text{1} - \text{FLAT\_VAT\_RATE (0.12)} - \text{SETTLEMENT\_FEE\_RATE (0.03)}} = \frac{\text{Koszty Stałe}}{\text{0.85}}$$

Dodatkowo, formularz paliwowy pozwala na **wielokrotne wprowadzanie rachunków (Multi-Receipt Logging)** w ciągu jednego tygodnia (FIFO, max **100** paragonów / `kMaxFuelReceipts`; lista `ListView.builder`). Każdy paragon otrzymuje unikalne ID generowane ze znacznika czasu i sumy kontrolnej kwoty, co eliminuje błędy duplikacji danych.

### Moduł IV: Tryb Solo vs. Paired (Podział Kosztów)

RateHelper wspiera zaawansowany podział progów najmu pojazdu, dopasowany do realiów krakowskich kierowców jeżdżących w pojedynkę lub dzielących auto w systemie dwuzmianowym (12-godzinnym).

- **Tryb Solo (1 Kierowca):** Całkowity koszt auta i rygorystyczne progi spoczywają na jednej osobie.
- **Tryb Paired (2 Kierowców):** Koszt najmu dzielony jest na pół, a progi liczby przejazdów zostają przesunięte w celu odzwierciedlenia skróconego czasu pracy pojedynczego kierowcy.

```
RENTAL_TIERS (Solo) — aplikacja wylicza opłatę wyłącznie z liczby kursów:
┌─────────────┬────────────────┐
│ Liczba Kursów│ Koszt Kierowcy │
├─────────────┼────────────────┤
│ 0 – 99      │ 900 PLN        │
│ 100 – 149   │ 700 PLN        │
│ 150 – 199   │ 500 PLN        │
│ 200 – 249   │ 300 PLN        │
│ 250+        │ 100 PLN        │
└─────────────┴────────────────┘
(Wyłączony rabat najmu: stała opłata 900 PLN)

RENTAL_TIERS_PAIRED (Tryb Współdzielony):
┌─────────────┬────────────────┬───────────────┐
│ Liczba Kursów│ Koszt Kierowcy │ Koszt Pojazdu │
├─────────────┼────────────────┼───────────────┤
│ 0 – 119     │ 450 PLN        │ 900 PLN       │
│ 120 – 169   │ 350 PLN        │ 700 PLN       │
│ 170 – 219   │ 250 PLN        │ 500 PLN       │
│ 220 – 269   │ 150 PLN        │ 300 PLN       │
│ 270+        │ 50 PLN         │ 100 PLN       │
└─────────────┴────────────────┴───────────────┘
(Wyłączony rabat najmu: 450 PLN na kierowcę)
```

**Reguła Nienaruszalności Historii (Fix #1):** Wybrany tryb jazdy (`driverMode`) jest zapisywany w strukturze JSON trwale w momencie zamknięcia tygodnia. Zmiana globalnego przełącznika w ustawieniach aplikacji nigdy nie rekalkuluje wstecznie zysków z poprzednich miesięcy.

### Moduł V: Radar Wydarzeń (Kraków)

W celu maksymalizacji stawek godzinowych, aplikacja została wyposażona w asynchroniczny moduł pobierania danych o imprezach masowych w Krakowie. Dane pobierane są bezpośrednio z surowego pliku JSON hostowanego w repozytorium GitHub (`krakow_events.json`).

- **Pamięć podręczna (TTL):** Wyniki są cache'owane w pamięci RAM przez 1 godzinę, co zapobiega niepotrzebnemu zużyciu pakietu danych kierowcy.
- **Strefy Surge:** Wydarzenia kategoryzowane są według stopni zagrożenia popytem: `High` (powyżej 10 tys. uczestników — Karmazynowy), `Medium` (Żółty) oraz `Low` (Zielony).

### Moduł VI: Integracja Sprzętowa (Bluetooth Media Keys)

Natywna usługa systemowa `MediaKeyAccessibilityService.kt` pozwala na bezwzrokowe zliczanie zleceń. Wykorzystuje ona bezprzewodowe piloty Bluetooth montowane na koło kierownicy.

- **Filtracja zdarzeń:** Najpierw tani test `keycode` (volume/power itd. nie czytają prefs). Potem flaga reiniekcji, potem `@Volatile steeringWheelEnabled` (cache z `onServiceConnected`). Krótkie kliknięcie (<800 ms) `MEDIA_NEXT` / `MEDIA_PREVIOUS` jest przepuszczane do systemu — Spotify czy YouTube Music działają bez zakłóceń.
- **Przechwytywanie (Long Press):** Przytrzymanie przycisku powyżej 800 ms wywołuje krótką wibrację haptyczną (150 ms), blokuje zmianę utworu w odtwarzaczu muzycznym i inkrementuje licznik zaakceptowanych (przycisk w przód) lub odrzuconych (przycisk w tył) zleceń.

> **Uwaga konfiguracyjna (Kompilacja):** W pliku konfiguracyjnym usługi `accessibility_service_config.xml` parametr `android:accessibilityEventTypes` został całkowicie usunięty, a flagą nadrzędną sterującą nasłuchem jest wyłącznie `android:canRequestFilterKeyEvents="true"`. Rozwiązuje to krytyczny błąd kompilacji zasobów AAPT (Resource Linking Failed) na nowych wersjach SDK.

---

## 5. Bezpieczeństwo, Prywatność i Integralność Danych

| Zagrożenie | Zastosowana Architektura Obronna |
| --- | --- |
| **Wyciek danych finansowych** | Brak synchronizacji finansów w chmurze — księgowość w `SharedPreferences`, liczniki zmiany i dziennik tapnięć w plikach piaskownicy. Jedyny ruch sieciowy: publiczny manifest OTA, radar wydarzeń (`krakow_events.json`) i pobieranie APK. |
| **Inżynieria wsteczna bazy** | Flaga `android:allowBackup=false` w manifestu uniemożliwia pobranie struktury SharedPreferences poprzez debugowanie ADB lub lokalne backupy systemowe. |
| **Ataki typu MITM (OTA)** | Klasa `StrictSecurityHttpOverrides` wymusza rygorystyczną weryfikację łańcucha certyfikatów TLS podczas sprawdzania aktualizacji i pobierania radaru wydarzeń. |
| **Paste-Bombing & Crash** | Filtry tekstowe `LengthLimitingTextInputFormatter(7)` oraz walidacja matematyczna do wartości maksymalnej 999 999,00 PLN zabezpieczają przed wprowadzeniem błędnych struktur niszczących wykresy. |
| **Utrata danych kamieni milowych** | Licznik przebiegu całkowitego (`lifetime_trips_total`) działa w trybie dopisywania różnicowego. Czyszczenie bazy z wpisów starszych niż 2 lata (limit FIFO: 104 tygodnie) nie powoduje cofania licznika postępu do darmowego najmu. |

---

## 6. Budowanie ze źródeł i pokrycie testowe

### Wymagania systemowe

- Flutter SDK >= `3.x`
- Android SDK (API Level 26+)
- Zainstalowane narzędzie `build_runner` dla generowania kodu zaciemniającego sekrety

### Procedura produkcyjna (Release Build)

1. **Klonowanie repozytorium:**

```bash
git clone https://github.com/emiroys/ratehelper.git
cd ratehelper
```

2. **Plik środowiskowy (`.env`):**

```bash
cp .env.example .env
```

Wypełnij `.env`:

```env
APP_SIGNATURE=1234567890ABCDEF
GIST_URL=https://gist.githubusercontent.com/twoj-profil/update.json
```

3. **Instalacja pakietów:**

```bash
flutter pub get
```

4. **Generowanie kodu generatora Envied (Zaciemnianie kluczy API):**

```bash
dart run build_runner build --delete-conflicting-outputs
```

5. **Uruchomienie pakietu testów regresyjnych (198 testów):**

```bash
flutter test
```

| Plik testowy | Zakres |
| --- | --- |
| `test/earnings_test.dart` | 94 — finanse, progi, JSON, FIFO paragonów, solo/paired |
| `test/logic_test.dart` | 44 — AR, semver, reset tygodnia |
| `test/layout_overflow_test.dart` | 40 — TR/EN/PL × 320/384 dp |
| `test/weekly_archive_test.dart` | 5 — archiwum v2 + legacy |
| `test/tap_history_store_test.dart` | 4 — NDJSON tap log |
| `test/shift_counter_store_test.dart` | 4 — plik liczników |
| `test/widget_test.dart` | 3 — overlay, earnings form |
| `test/overlay_sync_test.dart` | 2 — payload bez reload prefs |
| `test/crash_logger_test.dart` | 1 |
| `test/event_model_test.dart` | 1 — lokalizacja fallback |

6. **Kompilacja bezpiecznej wersji APK ze stripowaniem symboli debugowania i obfuskacją kodu Dart:**

```bash
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/ --no-tree-shake-icons
```

Plik wynikowy dla systemów 64-bitowych: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

---

## 7. Mapa plików projektu

Finansowa i strukturalna architektura kodu RateHelper rozkłada się na następujące moduły kluczowe:

```
lib/
├── main.dart                  # Inicjalizacja wątków, konfiguracja izolatu nakładki
├── home_screen.dart           # Kokpit, _CounterRow + ValueNotifier, OTA, wakelock opt-in
├── earnings_models.dart       # Silnik matematyczny, struktury JSON, progi Solo/Paired
├── earnings_screen.dart       # Formularze, ListView.builder paragonów, wykresy
├── earnings_pdf_export.dart   # Generator zestawień miesięcznych PDF (pdf + share_plus)
├── radar_screen.dart          # Interfejs graficzny Radaru Wydarzeń Kraków
├── overlay_widget.dart        # UI nakładki (izolat) — T.rateFor, ShiftCounterStore
├── overlay_sync.dart          # IPC z payloadem liczników (bez prefs.reload)
├── tap_history_store.dart     # Append-only tap_history.jsonl (max 500)
├── shift_counter_store.dart   # Jeden zapis shift_counters.json
├── onboarding_screen.dart     # Menadżer uprawnień systemowych (Overlay / Battery)
├── fonts.dart                 # Stałe nazw rodzin czcionek (DM Sans, JetBrains Mono)
├── app_text_styles.dart       # T.* static const TextStyle — bez google_fonts
├── app_colors.dart            # Jedyna paleta semantyczna
├── app_widgets.dart           # AppEmptyState, kMinTouchTarget
├── l10n.dart                  # Słownik tłumaczeń (TR/EN/PL) i lokalne formatowanie walut
├── secure_http.dart           # Zabezpieczenia certyfikatów i protokołu TLS
├── crash_logger.dart          # Dziennik awarii i błędów krytycznych
├── models/
│   ├── event_model.dart       # Model wydarzenia masowego (Radar OTA)
│   └── weekly_archive_entry.dart  # Archiwum tygodniowe v2 JSON + parser legacy
└── services/
    └── event_service.dart     # Pobieranie i cache manifestu krakow_events.json

android/app/src/main/kotlin/com/ratehelper/app/
├── MainActivity.kt            # MethodChannel, obsługa zdarzeń MediaKey
└── MediaKeyAccessibilityService.kt  # Keycode-first, @Volatile steeringWheelEnabled

test/
├── earnings_test.dart
├── logic_test.dart
├── layout_overflow_test.dart
├── weekly_archive_test.dart
├── tap_history_store_test.dart
├── shift_counter_store_test.dart
├── overlay_sync_test.dart
├── crash_logger_test.dart
├── event_model_test.dart
└── widget_test.dart
```

---

## 8. Dokumentacja dla kierowców i agentów

| Dokument | Odbiorca | Zawartość |
| --- | --- | --- |
| [`SETUP_GUIDE_PL.md`](SETUP_GUIDE_PL.md) | Kierowca (PL) | Pełna instrukcja: instalacja, widget, zarobki, radar, kierownica, troubleshooting |
| [`SETUP_GUIDE_TR.md`](SETUP_GUIDE_TR.md) | Kierowca (TR) | Ta sama struktura po turecku |
| [`agent-learnings.md`](agent-learnings.md) | Agent / maintainer | Kanoniczna wiedza o kodzie, pułapki, changelog |

> **Przewodnik w aplikacji** (menu ⋮ → Przewodnik konfiguracji) pokazuje **tylko dwa kroki uprawnień** (nakładka + bateria). Pełna obsługa jest w plikach markdown powyżej.

---

## Licencja i kontakt

Projekt open-source udostępniany na zasadach wolnego oprogramowania.

**Kierowcy:** [`SETUP_GUIDE_PL.md`](SETUP_GUIDE_PL.md) · [`SETUP_GUIDE_TR.md`](SETUP_GUIDE_TR.md)  
**Developerzy:** [`agent-learnings.md`](agent-learnings.md)

---

> **RateHelper v1.0** — Tworzony z perspektywy fotela kierowcy. Dbamy o Twój realny zysk na krakowskich drogach.
