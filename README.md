# RateHelper 🚖

RateHelper to otwartoźródłowy, lokalny asystent kierowcy zbudowany w technologii Flutter. Aplikacja pomaga kierowcom rideshare (Uber/Bolt) śledzić w czasie rzeczywistym wskaźniki akceptacji i anulowań oraz — dzięki wbudowanemu modułowi zarobków — obliczać **rzeczywisty zysk godzinowy w PLN** po odliczeniu kosztów wynajmu, prowizji, paliwa i podatku.

Wszystko działa **wyłącznie lokalnie** na urządzeniu. Brak kont, chmury i telemetrii.

---

## Spis treści

- [Główne funkcje](#-główne-funkcje)
- [Przepływ aplikacji](#-przepływ-aplikacji)
- [Ekran główny — liczniki statystyk](#ekran-główny--liczniki-statystyk)
- [Nakładka na żywo](#nakładka-na-żywo)
- [Zarobki — śledzenie zysku](#zarobki--śledzenie-zysku)
- [Optymalizacje wydajności i bezpieczeństwa](#-optymalizacje-wydajności-i-bezpieczeństwa)
- [Bezpieczeństwo i prywatność](#-bezpieczeństwo-i-polityka-prywatności)
- [Języki interfejsu](#-języki-interfejsu)
- [Wymagania](#-wymagania)
- [Budowanie ze źródeł](#-budowanie-ze-źródeł)
- [Struktura projektu](#-struktura-projektu)
- [Licencja i kontakt](#-licencja-i-kontakt)

---

## 🔥 Główne funkcje

| Moduł | Opis |
|---|---|
| **Nakładka na żywo** | Pływający widżet (`SYSTEM_ALERT_WINDOW`) nad aplikacjami Uber/Bolt — pokazuje aktualny wskaźnik akceptacji i pozwala szybko zliczać kursy bez przełączania okien |
| **Liczniki statystyk** | Zaakceptowane / Odrzucone / Ukończone / Anulowane — duże przyciski, jedno dotknięcie, tryb jazdy |
| **Zarobki i Analiza** | Tygodniowy kalkulator zysku w PLN (VAT, prowizja, paliwo, wynajem, idari). Wykresy i agregacja z widokiem tygodniowym, miesięcznym i rocznym |
| **Wskaźnik Rentowności** | Obliczanie na żywo *punktu break-even* w oparciu o koszty stałe i zmienne z uwzględnieniem nieliniowej prowizji partnera i 11,5% VAT |
| **Eksport do PDF** | Generowanie profesjonalnego zestawienia finansowego za dowolny wybrany miesiąc z opcją personalizacji danych kierowcy i automatyczną sanityzacją znaków |
| **Lokalne Przypomnienia** | Cykliczne powiadomienia systemowe (Android Alarm) w poniedziałki rano przypominające o zapisaniu statystyk z minionego tygodnia |
| **Tygodniowy reset** | Automatyczny reset liczników w poniedziałek o 04:00 (strefa `Europe/Warsaw`) z zachowaniem archiwu |
| **Wskazówka odzysku** | Wyliczanie liczby kolejnych akceptacji potrzebnych do podniesienia wskaźnika AR powyżej 80% |
| **Aktualizacje OTA** | Weryfikacja nowej wersji bezpośrednio przez bezpieczny manifest na GitHub Gist i instalacja sprawdzonych pakietów APK |

---

## 📱 Przepływ aplikacji

```
Pierwsze uruchomienie
        │
        ▼
┌───────────────────┐
│  Konfiguracja     │  1) Uprawnienie „Wyświetlanie nad innymi aplikacjami”
│  początkowa       │  2) Wyłączenie optymalizacji baterii (instrukcje
└─────────┬─────────┘     dla producenta: Samsung, Xiaomi, Huawei…)
          │
          ▼
┌───────────────────┐
│  Ekran główny     │  Karty wskaźnika akceptacji i anulowań
│                   │  Liczniki + cofnij + reset tygodnia
└─────────┬─────────┘  Dolny pasek: Nakładka · Historia · Zarobki · Język
          │
    ┌─────┴─────┬──────────────┐
    ▼           ▼              ▼
 Nakładka    Historia       Zarobki
 (pływająca) (archiwum)    (zysk PLN, PDF, Break-even)
```

### Konfiguracja początkowa

Przy pierwszym uruchomieniu aplikacja prowadzi kierowcę przez dwa wymagane uprawnienia Android:

1. **Wyświetlanie nad innymi aplikacjami** — bez tego nakładka nie pojawi się nad Uber Driver.
2. **Wyłączenie optymalizacji baterii** — instrukcje dostosowane do marki telefonu (Samsung, Xiaomi, Huawei, OnePlus, inne).

Po zakończeniu konfiguracja nie pojawia się ponownie (flaga `onboardingComplete` w SharedPreferences).

### Ekran główny — liczniki statystyk

- **Wskaźnik akceptacji (AR)** — `zaakceptowane / (zaakceptowane + odrzucone) × 100`; domyślnie 100% przy braku danych.
- **Wskaźnik anulowań (CR)** — `anulowane / (ukończone + anulowane) × 100`.
- Przyciski **[+]** / **[-]** z wibracją haptyczną (lekką / średnią).
- **Automatyczne ukończenie** — automatyczne zwiększanie licznika ukończonych po zarejestrowaniu akceptacji (opcjonalne).
- **Cofnij** — natychmiastowe cofnięcie ostatniego kroku (zapobieganie pomyłkom).
- **Reset tygodnia** — automatyczny (poniedziałek 04:00, strefa `Europe/Warsaw`) lub ręczny. Statystyki trafiają do archiwum.
- **Historia** — chronologiczna lista archiwalnych tygodni ze wskaźnikami.
- **Logi dotknięć** — lokalny dziennik interakcji z nakładką (przydatny przy audycie).

### Nakładka na żywo

Kompaktowa pigułka o rozmiarze **276×80 dp** unosząca się nad innymi aplikacjami:

- **−** (czerwony) → odrzucenie zlecenia (zwiększa licznik odrzuconych).
- **+** (zielony) → akceptacja zlecenia (zwiększa licznik zaakceptowanych).
- Środek → aktualny wskaźnik akceptacji sformatowany zgodnie z językiem systemu.
- Przeciąganie natywne (Android `WindowManager`) — bezpieczna, zoptymalizowana interakcja bez blokowania reszty ekranu.
- Synchronizacja w tle z główną aplikacją za pomocą `SharedPreferences` oraz dwukierunkowej komunikacji isolate IPC (`overlayListener`).

---

## 💰 Zarobki — śledzenie zysku

Ekran Zarobków (dostępny z dolnego paska) pozwala na precyzyjne rozliczanie przychodów z aplikacji:

**Wpisywane ręcznie (pola formularza):**

| Pole | Źródło w Uber Driver |
|---|---|
| **Dochód netto** | Kwota brutto partnera przed potrąceniem prowizji i VAT (główna suma u góry) |
| **Zapłacono na stacji** | Faktyczny koszt zatankowanego paliwa (PLN) |
| **Otrzymana gotówka** | Gotówka pobrana bezpośrednio od klientów |
| **Czas online** | Czas spędzony w aplikacji (godziny + minuty) |
| **Liczba przejazdów** | Całkowita liczba ukończonych zleceń w danym tygodniu |
| **Zniżka na wynajem** | Przełącznik aktywujący stawkę progresywną w zależności od liczby kursów |

**Obliczane automatycznie:**

| Składnik | Reguła |
|---|---|
| **VAT (11,5%)** | Podatek od przychodów Uber/Bolt odprowadzany przez partnera: `dochód netto × 0,115` |
| **Prowizja partnera** | Progresywna prowizja rozliczeniowa partnera (0–999 PLN → 50 PLN + 1% VAT, ..., 3000+ PLN → 0 PLN) |
| **Koszt paliwa** | Uwzględnia automatyczny 10% rabat z kart paliwowych: `zapłacono na stacji × 0,90` |
| **Koszt administracyjny** | Stała opłata partnerska wynosząca **40 PLN** |
| **Wynajem auta** | Naliczany zawsze. Przy zniżce zależy od liczby kursów (850 / 650 / 450 / 250 PLN). Bez zniżki stawka płaska **850 PLN** |
| **Zysk netto** | Ostateczny zysk kierowcy na czysto: `dochód netto − wszystkie powyższe koszty` |
| **Stawka godzinowa** | Średnia stawka za godzinę pracy: `zysk netto ÷ godziny online` |
| **Na konto** | Kwota przelewu od partnera po potrąceniach gotówki: `zysk netto − otrzymana gotówka` |

---

## ⚡ Optymalizacje wydajności i bezpieczeństwa

Najnowsze usprawnienia techniczne wdrożone w celu zapewnienia maksymalnej płynności i niezawodności:

* **Optymalizacja renderowania nakładki (`RepaintBoundary`)**: Przyciski sterujące nakładki (`_CircleBtn`) zostały wydzielone do osobnych warstw renderowania. Zapobiega to ponownemu przerysowywaniu ikon wektorowych i efektów rozbłysków (InkWell) przy każdej zmianie tekstu wskaźnika akceptacji na żywo.
* **Ochrona przed paste-bombingiem**: Wprowadzono sztywne limity długości wpisywanych znaków (`LengthLimitingTextInputFormatter(7)`) oraz walidację maksymalnych wartości (do `999 999.0`). Chroni to aplikację przed wpisaniem uszkodzonych danych, które zniekształcają średnie historyczne i psują skalowanie wykresów.
* **Keep-Alive dla widoków (`AutomaticKeepAliveClientMixin`)**: Widoki kart wykresów na ekranie głównym są utrzymywane w pamięci. Przełączanie zakładek nie powoduje resetowania ani ponownego odtwarzania animacji wejściowych wykresów od zera.
* **Bezpieczny eksport PDF**: Generator dokumentów automatycznie filtruje znaki specjalne oraz emotikony w imieniu kierowcy za pomocą wyrażeń regularnych, chroniąc przed błędami biblioteki PDF (`PdfException`).
* **Synchroniczne zapobieganie race-condition**: Metoda zapisu danych synchronizuje aktualny stan liczników poprzez uprzednie przeładowanie pamięci dyskowej (`await prefs.reload()`), co chroni przed nadpisywaniem zmian dokonanych z poziomu nakładki na żywo.

---

## 🔒 Bezpieczeństwo i polityka prywatności

* **W 100% lokalnie** — brak chmury, zewnętrznych serwerów i telemetrii. Całość danych spoczywa w bezpiecznym piaskowym katalogu aplikacji.
* **Kopia zapasowa wyłączona** — `allowBackup=false` uniemożliwia wyodrębnienie historii transakcji i zarobków za pomocą zewnętrznych programów kopii zapasowej.
* **Bezpieczne pliki tymczasowe** — wygenerowane PDF są zapisywane w izolowanym folderze cache i usuwane natychmiast po udostępnieniu.
* **Aktualizacje podpisane cyfrowo** — mechanizm OTA weryfikuje sumę kontrolną APK za pomocą podpisu zapisanego w `.env` i pobiera pliki wyłącznie z oficjalnego repozytorium GitHub releases.

---

## 🌍 Języki interfejsu

Aplikacja w pełni obsługuje języki: **polski**, **angielski** oraz **turecki** (domyślny). Działa automatyczna lokalizacja formatów procentowych (np. `100%` w PL/EN oraz `%100` w TR).

---

## 📋 Wymagania

| Parametr | Specyfikacja |
|---|---|
| **Platforma** | Android 8.0+ (docelowo arm64-v8a) |
| **Flutter SDK** | 3.x lub nowszy |
| **Kompilacja** | Java JDK + Android SDK |

---

## 🛠️ Budowanie ze źródeł

### 1. Klonowanie repozytorium
```bash
git clone https://github.com/emiroys/ratehelper.git
cd ratehelper
```

### 2. Plik środowiskowy (`.env`)
Skopiuj plik szablonu i wprowadź własne zmienne:
```bash
cp .env.example .env
```
Wypełnij `.env`:
```env
APP_SIGNATURE=1234567890ABCDEF
GIST_URL=https://gist.githubusercontent.com/twoj-profil/update.json
```

### 3. Instalacja zależności i generowanie kodu
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 4. Uruchamianie testów
```bash
flutter test
```

### 5. Kompilacja APK produkcyjnego
```bash
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/
```
Plik wynikowy dla systemów 64-bitowych znajdziesz w: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

---

## 📂 Struktura projektu

```
lib/
├── main.dart                # Inicjalizacja aplikacji, konfiguracja izolatu nakładki
├── home_screen.dart         # Główny ekran liczników statystyk, weryfikacja OTA, synchronizacja
├── earnings_models.dart     # Logika kalkulatora, tabele prowizji, matematyka break-even
├── earnings_screen.dart     # Interfejs zarobków (wykresy, formularze, walidacja i limity)
├── earnings_pdf_export.dart # Generowanie i sanityzacja raportów PDF
├── earnings_reminders.dart  # Zarządca alarmów i powiadomień poniedziałkowych
├── overlay_widget.dart      # Widżet pływający z optymalizacją RepaintBoundary
├── onboarding_screen.dart   # Ekran powitalny i przyznawanie uprawnień systemowych
├── l10n.dart                # Klasy lokalizacji językowej
├── secure_http.dart         # Zabezpieczenia certyfikatów i protokołu TLS
└── crash_logger.dart        # Dziennik awarii i błędów krytycznych
```

---

## 📄 Licencja i kontakt

Projekt open-source udostępniany na zasadach wolnego oprogramowania.
Dedykowana instrukcja konfiguracji dla kierowców bez znajomości programowania dostępna jest pod adresem: [`SETUP_GUIDE_TR.md`](SETUP_GUIDE_TR.md).

<p align="center">
  <sub>RateHelper — stworzony przez kierowców dla kierowców, którzy chcą znać swój realny zysk.</sub>
</p>
