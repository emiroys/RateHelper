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
   - [Moduł V: Radar Wydarzeń (OTA Surge Radar)](#moduł-v-radar-wydarzeń-ota-surge-radar)
   - [Moduł VI: Integracja Sprzętowa (Bluetooth Media Keys)](#moduł-vi-integracja-sprzętowa-bluetooth-media-keys)
5. [Bezpieczeństwo, Prywatność i Integralność Danych](#5-bezpieczeństwo-prywatność-i-integralność-danych)
6. [Budowanie ze źródeł i pokrycie testowe](#6-budowanie-ze-źródeł-i-pokrycie-testowe)
7. [Mapa plików projektu](#7-mapa-plików-projektu)

---

## 1. Tożsamość i cel aplikacji

**RateHelper** to zaawansowany, całkowicie lokalny asystent narzędziowy stworzony dla kierowców rideshare (Uber/Bolt) operujących w **Krakowie**. Aplikacja rozwiązuje kluczowe problemy operacyjne kierowców zawodowych, łącząc w jednym interfejsie bezdyskusyjną matematykę zysków, predykcję stref podwyższonego popytu (surge) oraz automatyzację rejestracji zleceń bez odrywania rąk od kierownicy.

### Główne zasady projektowe

- **100% Local, Zero Cloud:** Wszystkie dane finansowe i statystyki przechowywane są wyłącznie w piaskownicy Androida (`SharedPreferences`). Brak zewnętrznej telemetrii i kont użytkowników.
- **Driving-First UI:** Ekstremalny ciemny motyw (True Dark), gigantyczne punkty dotykowe (XL Targets) oraz haptyka zwrotna dostosowana do obsługi urządzenia w uchwycie samochodowym.
- **Trójjęzyczność:** Pełna lokalizacja interfejsu w językach: Tureckim (domyślny), Polskim oraz Angielskim.

---

## 2. Główne funkcje (Zaktualizowana matryca v1.0)

| Moduł | Opis Funkcjonalny | Mechanizm Implementacji |
| --- | --- | --- |
| **Pływająca Nakładka** | Widget 276×80 dp wiszący bezpośrednio nad aplikacją Uber/Bolt Driver, pozwalający na rejestrację kliknięć bez opuszczania nawigacji. | Osobny izolat Flutter (`OverlayIsolate`) sprzężony z natywnym `WindowManager` w Javie. |
| **3-Stanowy Alert AR** | Inteligentne monitorowanie wskaźnika akceptacji (AR) z dynamicznym systemem wczesnego ostrzegania (Zielony/Żółty/Czerwony). | Algorytm sprawdzający bufor bezpieczeństwa `AMBER_BUFFER = 2.0%` wokół progu wybranego celu. |
| **Silnik Księgowy** | Precyzyjny kalkulator rentowności tygodniowej z automatycznym odliczaniem podatków, prowizji, paliwa i amortyzacji. | Pełne mapowanie podatku ryczałtowego/VAT (12%), prowizji partnera (3%) oraz stałych kosztów administracyjnych (40 PLN). |
| **Tryby Jazdy (1 vs 2)** | Elastyczne przełączanie profilu kosztów w zależności od tego, czy kierowca jeździ sam, czy dzieli auto na zmiany. | Dynamiczne tabele progowe `RENTAL_TIERS` i `RENTAL_TIERS_PAIRED` działające w sposób odporny na modyfikacje wsteczne. |
| **Surge Radar (OTA)** | Kalendarz masowych imprez w Krakowie (Tauron Arena, mecze Wisły/Cracovii) przewidujący skoki mnożników. | Bezpieczne pobieranie pliku manifestu z repozytorium GitHub bez konieczności aktualizacji całej aplikacji (Zero-Update OTA). |
| **Obsługa Bluetooth** | Logowanie zleceń (Akceptacja/Odrzucenie) za pomocą fabrycznych przycisków multimedialnych na kierownicy pojazdu. | Natywna usługa `AccessibilityService` przechwytująca zdarzenia `KeyEvent` w tle systemu Android. |
| **Niezależny Drogomierz** | Niezatracalny licznik podróży całkowitych monitorujący postęp do darmowego tygodnia najmu (próg 2000 kursów). | Zdecouple'owany licznik oparty na przyrostach różnicowych (delta), odporny na dwuletnie czyszczenie historii (FIFO). |

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
│   │   HomeScreen      │  │  OverlayWidget   │ ◄─ SharedPreferences│
│   │   (główny izolat) │  │  (izolat okna)   │    2-way sync       │
│   └────────┬──────────┘  └──────────────────┘                      │
│            │                                                       │
│   ┌────────┼──────────┬─────────────────┬─────────────┐           │
│   ▼        ▼          ▼                 ▼             ▼           │
│ Zarobki  Radar     Onboarding      Eksport PDF   Przypomnienia    │
└───────────────────────────────────────────────────────────────────┘
```

### Protokół synchronizacji stanów

Wszelkie operacje zapisu w głównym izolacie wywołują natychmiastowe powiadomienie `OverlaySync.notifyCountersChanged()`. Po powrocie do aplikacji głównej (`resumed`), interfejs wykonuje `prefs.reload()`, zapewniając całkowitą spójność danych i eliminując zjawisko wyścigu (race conditions).

---

## 4. Szczegółowa specyfikacja modułów

### Moduł I: Pulpit Wskaźników i Kalkulator Odzysku

Główny pulpit zarządza czterema krytycznymi licznikami: **Zaakceptowane**, **Odrzucone**, **Ukończone** oraz **Anulowane**.

- **Wskaźnik Akceptacji (AR):** Wzór: $\text{AR} = \frac{\text{zaakceptowane}}{\text{zaakceptowane} + \text{odrzucone}} \times 100$.
- **3-Stanowy system wizualny:** Jeśli wskaźnik zbliża się do krytycznego progu, karta zmienia kolor na bursztynowy (`AMBER_BUFFER = 2.0%`), dając kierowcy przestrzeń na odrzucenie kilku gorszych zleceń bez natychmiastowego wypadnięcia z progu zniżkowego. Gdy spada poniżej celu, system aktywuje kolor karmazynowy i wylicza dokładną liczbę ($X$) kolejnych koniecznych akceptacji pod rząd według wzoru matematycznego:

$$X = \max\left(1,\ \left\lfloor \frac{r \cdot \text{rejected} - (1-r) \cdot \text{accepted}}{1-r} \right\rfloor + 1\right)$$

### Moduł II: Natywna Nakładka na Żywo (Pill Overlay)

Pływająca pigułka o wymiarach 276×80 dp operuje na natywnym wątku renderowania Androida poprzez `WindowManager.updateViewLayout()`. Zastosowano margines błędu dotyku (20px slop) dopasowany do digitizera serii Samsung Galaxy Ultra, dzięki czemu fizyczne przeciąganie nakładki nie koliduje z panelami dotykowymi aplikacji Uber/Bolt Driver. Widget używa komponentu `RepaintBoundary` w celu odizolowania renderowania dynamicznego tekstu od statycznych ikon wektorowych.

### Moduł III: Zaawansowany Silnik Księgowy (Kary/Zyski)

Kalkulator zysku netto operuje na architekturze ciągłego przeliczania wartości w czasie rzeczywistym. Formuła finansowa została zdefiniowana następująco:

```
Zysk Netto = Przychód Netto Uber
            − Stała Opłata Administracyjna (40.00 PLN)
            − Paliwo po Rabacie Partnerskim (Suma Rachunków × 0.90)
            − Podatek VAT Ryczałtowy (Przychód Netto × 0.12)
            − Prowizja Rozliczeniowa Partnera (Przychód Netto × 0.03)
            − Indywidualny Koszt Wynajmu (rentalFee wyliczone z tabel progowych)
```

#### Próg rentowności (Break-Even)

Aplikacja dynamicznie wskazuje kwotę obrotu, od której kierowca zaczyna zarabiać na czysto:

$$\text{Break-Even} = \frac{\text{Koszty Stałe (Najem + Admin + Paliwo)}}{\text{1} - \text{FLAT\_VAT\_RATE (0.12)} - \text{SETTLEMENT\_FEE\_RATE (0.03)}} = \frac{\text{Koszty Stałe}}{\text{0.85}}$$

Dodatkowo, formularz paliwowy pozwala na **wielokrotne wprowadzanie rachunków (Multi-Receipt Logging)** w ciągu jednego tygodnia. Każdy paragon otrzymuje unikalne ID generowane ze znacznika czasu i sumy kontrolnej kwoty, co eliminuje błędy duplikacji danych.

### Moduł IV: Tryb Solo vs. Paired (Podział Kosztów)

RateHelper wspiera zaawansowany podział progów najmu pojazdu, dopasowany do realiów krakowskich kierowców jeżdżących w pojedynkę lub dzielących auto w systemie dwuzmianowym (12-godzinnym).

- **Tryb Solo (1 Kierowca):** Całkowity koszt auta i rygorystyczne progi spoczywają na jednej osobie.
- **Tryb Paired (2 Kierowców):** Koszt najmu dzielony jest na pół, a progi liczby przejazdów zostają przesunięte w celu odzwierciedlenia skróconego czasu pracy pojedynczego kierowcy.

```
RENTAL_TIERS (Solo):
┌─────────────┬────────────────┬─────────┬──────────────┐
│ Liczba Kursów│ Koszt Kierowcy │ Min. AR%│ Maks. Anul.% │
├─────────────┼────────────────┼─────────┼──────────────┤
│ 0 – 99      │ 900 PLN        │ —       │ —            │
│ 100 – 149   │ 700 PLN        │ 80%     │ 5%           │
│ 150 – 199   │ 500 PLN        │ 70%     │ 5%           │
│ 200 – 249   │ 300 PLN        │ 60%     │ 5%           │
│ 250+        │ 100 PLN        │ 50%     │ 5%           │
└─────────────┴────────────────┴─────────┴──────────────┘

RENTAL_TIERS_PAIRED (Tryb Współdzielony):
┌─────────────┬────────────────┬───────────────┬─────────┬──────────────┐
│ Liczba Kursów│ Koszt Kierowcy │ Koszt Pojazdu │ Min. AR%│ Maks. Anul.% │
├─────────────┼────────────────┼───────────────┼─────────┼──────────────┤
│ 0 – 119     │ 450 PLN        │ 900 PLN       │ —       │ —            │
│ 120 – 169   │ 350 PLN        │ 700 PLN       │ 80%     │ 5%           │
│ 170 – 219   │ 250 PLN        │ 500 PLN       │ 70%     │ 5%           │
│ 220 – 269   │ 150 PLN        │ 300 PLN       │ 60%     │ 5%           │
│ 270+        │ 50 PLN         │ 100 PLN       │ 50%     │ 5%           │
└─────────────┴────────────────┴───────────────┴─────────┴──────────────┘
```

**Reguła Nienaruszalności Historii (Fix #1):** Wybrany tryb jazdy (`driverMode`) jest zapisywany w strukturze JSON trwale w momencie zamknięcia tygodnia. Zmiana globalnego przełącznika w ustawieniach aplikacji nigdy nie rekalkuluje wstecznie zysków z poprzednich miesięcy.

### Moduł V: Radar Wydarzeń (Surge Radar OTA)

W celu maksymalizacji stawek godzinowych, aplikacja została wyposażona w asynchroniczny moduł pobierania danych o imprezach masowych w Krakowie. Dane pobierane są bezpośrednio z surowego pliku JSON hostowanego w repozytorium GitHub (`krakow_events.json`).

- **Pamięć podręczna (TTL):** Wyniki są cache'owane w pamięci RAM przez 1 godzinę, co zapobiega niepotrzebnemu zużyciu pakietu danych kierowcy.
- **Strefy Surge:** Wydarzenia kategoryzowane są według stopni zagrożenia popytem: `High` (powyżej 10 tys. uczestników — Karmazynowy), `Medium` (Żółty) oraz `Low` (Zielony).

### Moduł VI: Integracja Sprzętowa (Bluetooth Media Keys)

Natywna usługa systemowa `MediaKeyAccessibilityService.kt` pozwala na bezwzrokowe zliczanie zleceń. Wykorzystuje ona bezprzewodowe piloty Bluetooth montowane na koło kierownicy.

- **Filtracja zdarzeń:** Krótkie kliknięcie (<800 ms) przycisków zmiany utworu (`MEDIA_NEXT` / `MEDIA_PREVIOUS`) jest przepuszczane do systemu — Spotify czy YouTube Music działają bez zakłóceń.
- **Przechwytywanie (Long Press):** Przytrzymanie przycisku powyżej 800 ms wywołuje krótką wibrację haptyczną (150 ms), blokuje zmianę utworu w odtwarzaczu muzycznym i inkrementuje licznik zaakceptowanych (przycisk w przód) lub odrzuconych (przycisk w tył) zleceń.

> **Uwaga konfiguracyjna (Kompilacja):** W pliku konfiguracyjnym usługi `accessibility_service_config.xml` parametr `android:accessibilityEventTypes` został całkowicie usunięty, a flagą nadrzędną sterującą nasłuchem jest wyłącznie `android:canRequestFilterKeyEvents="true"`. Rozwiązuje to krytyczny błąd kompilacji zasobów AAPT (Resource Linking Failed) na nowych wersjach SDK.

---

## 5. Bezpieczeństwo, Prywatność i Integralność Danych

| Zagrożenie | Zastosowana Architektura Obronna |
| --- | --- |
| **Wyciek danych finansowych** | Całkowity brak modułów sieciowych odpowiedzialnych za analitykę, reklamy czy synchronizację w chmurze. Dane nigdy nie opuszczają urządzenia. |
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

5. **Uruchomienie pakietu testów regresyjnych (Finanse, Progi, Zaokrąglenia, Daty):**

```bash
flutter test test/earnings_test.dart test/logic_test.dart
```

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
├── home_screen.dart           # Kokpit wskaźników, licznik odzysku, mechanizm aktualizacji OTA
├── earnings_models.dart       # Silnik matematyczny, struktury JSON, progi Solo/Paired
├── earnings_screen.dart       # Formularze księgowe, izolowane odświeżanie list, wykresy i drogomierz
├── earnings_pdf_export.dart   # Generator zestawień miesięcznych PDF ze stripowaniem emotikonów
├── earnings_reminders.dart    # Harmonogram powiadomień push (Poniedziałek 09:00)
├── radar_screen.dart          # Interfejs graficzny Radaru Wydarzeń Kraków
├── overlay_widget.dart        # Kod UI nakładki (Izolat okna) z optymalizacją RepaintBoundary
├── overlay_sync.dart          # Komunikacja międzyizolatowa i wymuszanie przeładowania pamięci
├── onboarding_screen.dart     # Menadżer uprawnień systemowych (Overlay / Battery)
├── l10n.dart                  # Słownik tłumaczeń (TR/EN/PL) i lokalne formatowanie walut
├── secure_http.dart           # Zabezpieczenia certyfikatów i protokołu TLS
├── crash_logger.dart          # Dziennik awarii i błędów krytycznych
├── models/
│   └── event_model.dart       # Model wydarzenia masowego (Radar OTA)
└── services/
    └── event_service.dart     # Pobieranie i cache manifestu krakow_events.json

android/app/src/main/kotlin/com/ratehelper/app/
├── MainActivity.kt            # MethodChannel, obsługa zdarzeń MediaKey
└── MediaKeyAccessibilityService.kt  # Przechwytywanie przycisków Bluetooth (long press 800 ms)
```

---

## Licencja i kontakt

Projekt open-source udostępniany na zasadach wolnego oprogramowania.  
Dedykowana instrukcja konfiguracji dla kierowców bez znajomości programowania: [`SETUP_GUIDE_TR.md`](SETUP_GUIDE_TR.md).

---

> **RateHelper v1.0** — Tworzony z perspektywy fotela kierowcy. Dbamy o Twój realny zysk na krakowskich drogach.
