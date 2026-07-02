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
- [Bezpieczeństwo i prywatność](#-bezpieczeństwo-i-polityka-prywatności)
- [Języki interfejsu](#-języki-interfejsu)
- [Wymagania](#-wymagania)
- [Budowanie ze źródeł](#-budowanie-ze-źródeł)
- [Licencja i kontakt](#-licencja-i-kontakt)

---

## 🔥 Główne funkcje

| Moduł | Opis |
|---|---|
| **Nakładka na żywo** | Pływający widżet (`SYSTEM_ALERT_WINDOW`) nad aplikacjami Uber/Bolt — pokazuje aktualny wskaźnik akceptacji i pozwala szybko zliczać kursy bez przełączania okien |
| **Liczniki statystyk** | Zaakceptowane / Odrzucone / Ukończone / Anulowane — duże przyciski, jedno dotknięcie, tryb jazdy |
| **Zarobki i Analiza** | Tygodniowy kalkulator zysku w PLN (VAT, prowizja, paliwo, wynajem, idari). Wykresy i agregacja z widokiem tygodniowym, miesięcznym i rocznym |
| **Wskaźnik Rentowności** | Obliczanie na żywo *punktu break-even* w oparciu o bieżące koszty (paliwo, wynajem) z wykorzystaniem odwrotnej kalkulacji podatkowej |
| **Eksport do PDF** | Generowanie profesjonalnego zestawienia księgowego (ryczałt) z wyborem konkretnego miesiąca. Możliwość personalizacji imienia i nazwiska |
| **Lokalne Przypomnienia** | Automatyczne powiadomienia (Android Alarm) w każdy poniedziałek rano o dodaniu wyników z zeszłego tygodnia |
| **Tygodniowy reset** | Automatyczny reset w poniedziałek o 04:00 (strefa Europe/Warsaw) z archiwum poprzedniego tygodnia |
| **Wskazówka odzysku** | Informacja, ile kolejnych akceptacji potrzeba, aby wrócić powyżej 80% |
| **Aktualizacje OTA** | Sprawdzanie nowej wersji z GitHub Gist (tylko podpisane APK z oficjalnych wydań) |

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

- **Wskaźnik akceptacji** — `zaakceptowane / (zaakceptowane + odrzucone) × 100`; domyślnie 100% przy zerowych danych
- **Wskaźnik anulowań** — `anulowane / (ukończone + anulowane) × 100`
- Przyciski **[+]** / **[-]** z wibracją haptyczną (lekką / średnią)
- **Automatyczne ukończenie** — opcjonalne automatyczne zwiększanie licznika ukończonych po akceptacji
- **Cofnij** — jeden krok wstecz (ostatnia zmiana liczników)
- **Reset tygodnia** — ręczny lub automatyczny (poniedziałek 04:00, strefa Europe/Warsaw); poprzedni tydzień trafia do archiwum
- **Historia** — lista zarchiwizowanych tygodni z procentami
- **Logi** — dziennik dotknięć nakładki (debug / audyt)

### Nakładka na żywo

Kompaktowa pigułka **276×80 dp** unosząca się nad innymi aplikacjami:

- **−** (czerwony) → odrzucone zlecenie
- **+** (zielony) → zaakceptowane zlecenie
- Środek → aktualny **wskaźnik akceptacji** w dużej czcionce DM Sans
- Przeciąganie natywne (Android `WindowManager`) — nie blokuje dotknięć poza pigułką
- Synchronizacja z ekranem głównym przez SharedPreferences i `OverlaySync`

Włączanie i wyłączanie z dolnego paska ekranu głównego.

### Zarobki — śledzenie zysku

Osobny ekran (przycisk 💰 **Zarobki** w dolnym pasku) oblicza **rzeczywisty zysk netto** na podstawie danych z ekranu Uber Driver:

**Wpisywane ręcznie (pola formularza):**

| Pole | Źródło w Uber |
|---|---|
| Dochód netto | Duża liczba u góry ekranu Zarobki |
| Zapłacono na stacji | Kwota zapłacona na stacji paliw |
| Otrzymana gotówka | Gotówka odebrana od pasażerów |
| Czas online | Godziny + minuty online |
| Liczba przejazdów | Liczba kursów w tygodniu |
| Zniżka na wynajem | Przełącznik — czy obowiązuje obniżona stawka wynajmu |

**Nowe funkcje Zarobków:**
* **Wskaźnik Rentowności (Break-even):** Aplikacja na żywo wylicza minimalny dochód netto potrzebny do pokrycia kosztów stałych (uwzględniając nieliniowe prowizje partnera i 11,5% VAT).
* **Eksport PDF:** Generowanie gotowych do druku raportów finansowych za "Wybrany miesiąc", "Ten miesiąc" lub "Ten rok". Obejmuje nagłówek z edytowalnym imieniem kierowcy.
* **Cotygodniowe przypomnienie:** Systemowe powiadomienie Android (bez internetu), przypominające o wpisaniu wyników z poprzedniego tygodnia.

**Obliczane automatycznie:**

| Składnik | Reguła |
|---|---|
| VAT (11,5%) | `dochód netto × 0,115` |
| Prowizja | Tabela progów obrotu (0–999 → 50 PLN + 1%, …, 3000+ → 0) |
| Paliwo (10% rabatu) | `zapłacono na stacji × 0,90` |
| Koszt administracyjny | Stałe **40 PLN** |
| Wynajem | **Zawsze pobierany.** Zniżka włączona → próg wg liczby kursów (850/650/450/250 PLN); wyłączona → płaska stawka **850 PLN** |
| Zysk netto | Dochód netto − wszystkie powyższe składniki |
| Stawka godzinowa | Zysk netto ÷ godziny online |
| Na konto | Zysk netto − otrzymana gotówka |

**Widoki:**

- **Tygodniowo** — wykres trendu (ostatnie 12 tygodni), selektor tygodnia, karta ze stawką godzinową, rozbicie kosztów, historia
- **Miesięcznie** — podsumowanie miesiąca, wykres średniej stawki, karta 🏆 najlepszego tygodnia w wybranym miesiącu
- **Rocznie** — podsumowanie roku, wykres roczny, lista miesięcy

Dane przechowywane lokalnie (`earnings_history`, maks. 104 tygodnie = 2 lata).

---

## 🔒 Bezpieczeństwo i polityka prywatności

Prywatność kierowcy jest priorytetem:

- **100% lokalnie** — aplikacja nie łączy się z zewnętrznymi serwerami (poza opcjonalnym sprawdzeniem aktualizacji z GitHub Gist)
- **Zero danych osobowych** — brak GPS, numeru telefonu, danych logowania Uber/Bolt
- **SharedPreferences** — wszystkie statystyki i historia zarobków tylko na urządzeniu
- **Kopia zapasowa wyłączona** — `allowBackup=false` zapobiega przypadkowemu wyciekowi przez kopię zapasową Android
- **Bezpieczny Eksport PDF** — Tymczasowe pliki PDF są trzymane wyłącznie w izolowanym katalogu `cache` i automatycznie czyszczone po zakończeniu udostępniania (brak wycieków dokumentów finansowych).
- **Zoptymalizowane powiadomienia** — Użyto `inexactAllowWhileIdle` dla alarmów, by oszczędzać baterię bez nadmiernych uprawnień systemowych.
- **Weryfikacja podpisu APK** — w wersji produkcyjnej porównanie z `APP_SIGNATURE` z pliku `.env` (obfuskowane przez `envied`)
- **Zabezpieczone aktualizacje OTA** — manifest tylko z `gist.githubusercontent.com`; APK tylko z `github.com/emiroys/ratehelper/releases/latest/download/app-arm64-v8a-release.apk`

---

## 🌍 Języki interfejsu

Interfejs użytkownika: **turecki** (domyślny), **angielski**, **polski**.

Język wykrywany automatycznie przy pierwszym uruchomieniu; można zmienić z dolnego paska (przycisk **Język**).

---

## 📋 Wymagania

| | |
|---|---|
| Platforma | Android (docelowo Samsung Galaxy S24 Ultra, arm64) |
| Flutter SDK | 3.x lub nowszy |
| Android Studio | z Java JDK |
| Architektura APK | `arm64-v8a` (kompilacja split-per-abi) |
