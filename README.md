# RateHelper 🚖

RateHelper to otwartoźródłowy, lokalny asystent kierowcy zbudowany w technologii Flutter. Aplikacja pomaga kierowcom rideshare (Uber/Bolt) śledzić w czasie rzeczywistym wskaźniki akceptacji i anulowań oraz — dzięki wbudowanemu modułowi kazanç — obliczać **rzeczywisty zysk godzinowy w PLN** po odliczeniu kosztów wynajmu, prowizji, paliwa i podatku.

Wszystko działa **wyłącznie lokalnie** na urządzeniu. Brak kont, chmury i telemetrii.

---

## Spis treści

- [Główne funkcje](#-główne-funkcje)
- [Przepływ aplikacji](#-przepływ-aplikacji)
- [Ekran główny — liczniki](#ekran-główny--liczniki-statystyk)
- [Live Overlay](#live-overlay)
- [Kazanç Takibi — zysk tygodniowy](#kazanç-takibi--śledzenie-zysku)
- [Bezpieczeństwo i prywatność](#-bezpieczeństwo-i-polityka-prywatności)
- [Języki](#-języki)
- [Wymagania](#-wymagania)
- [Budowanie ze źródeł](#-budowanie-ze-źródeł)
- [Licencja i kontakt](#-licencja-i-kontakt)

---

## 🔥 Główne funkcje

| Moduł | Opis |
|---|---|
| **Live Overlay** | Pływający widżet (`SYSTEM_ALERT_WINDOW`) nad aplikacjami Uber/Bolt — pokazuje aktualny wskaźnik akceptacji i pozwala szybko zliczać kursy bez przełączania okien |
| **Liczniki statystyk** | Kabul / Red / Tamamlanan / İptal — duże przyciski, jedno dotknięcie, tryb jazdy |
| **Ręczne wpisywanie** | Dotknij lub przytrzymaj wartość licznika, aby wpisać liczbę z klawiatury (przywracanie po reinstalacji) |
| **Kazanç Takibi** | Tygodniowy kalkulator zysku w PLN — VAT, prowizja, paliwo, wynajem i opłata administracyjna obliczane automatycznie |
| **Wykresy i agregacja** | Widok tygodniowy, miesięczny i roczny ze średnią stawką godzinową |
| **Tygodniowy reset** | Automatyczny reset w poniedziałek o 04:00 (Europe/Warsaw) z archiwum poprzedniego tygodnia |
| **Wskazówka odzysku** | Informacja, ile kolejnych akceptacji potrzeba, aby wrócić powyżej 80% |
| **Aktualizacje OTA** | Sprawdzanie nowej wersji z GitHub Gist (tylko podpisane APK z oficjalnych Releases) |
| **Wakelock** | Ekran pozostaje włączony podczas pracy — bez przypadkowego blokowania |

---

## 📱 Przepływ aplikacji

```
Pierwsze uruchomienie
        │
        ▼
┌───────────────────┐
│  Onboarding       │  1) Uprawnienie „Rysuj nad innymi aplikacjami”
│  (Kurulum)        │  2) Wyłączenie optymalizacji baterii (instrukcje
└─────────┬─────────┘     per producent: Samsung, Xiaomi, Huawei…)
          │
          ▼
┌───────────────────┐
│  Ekran główny     │  Karty KABUL ORANI / İPTAL ORANI
│  (HomeScreen)     │  Liczniki + undo + reset tygodnia
└─────────┬─────────┘  Dolny pasek: Overlay · Geçmiş · Kazanç · Dil
          │
    ┌─────┴─────┬──────────────┐
    ▼           ▼              ▼
 Overlay    Historia      Kazanç Takibi
 (pływający) (archiwum)   (zysk PLN)
```

### Onboarding

Przy pierwszym uruchomieniu aplikacja prowadzi kierowcę przez dwa wymagane uprawnienia Android:

1. **Display over other apps** — bez tego overlay nie pojawi się nad Uber Driver.
2. **Battery optimization off** — instrukcje dostosowane do marki telefonu (Samsung, Xiaomi, Huawei, OnePlus, inne).

Po zakończeniu onboarding nie pojawia się ponownie (`onboardingComplete` w SharedPreferences).

### Ekran główny — liczniki statystyk

- **Kabul Oranı** — `accepted / (accepted + rejected) × 100`; domyślnie 100% przy zerowych danych
- **İptal Oranı** — `cancelled / (completed + cancelled) × 100`
- Przyciski **[+]** / **[-]** z haptyką (light / medium impact)
- **Auto-complete** — opcjonalne automatyczne zwiększanie licznika ukończonych po akceptacji
- **Undo** — jeden krok wstecz (ostatnia zmiana liczników)
- **Reset tygodnia** — ręczny lub automatyczny (poniedziałek 04:00 Europe/Warsaw); poprzedni tydzień trafia do archiwum
- **Geçmiş** — lista zarchiwizowanych tygodni z procentami
- **Kayıtlar** — dziennik dotknięć overlay (debug/audit)

### Live Overlay

Kompaktowa pigułka **276×80 dp** unosząca się nad innymi aplikacjami:

- **−** (czerwony) → odrzucone żądanie
- **+** (zielony) → zaakceptowane żądanie
- Środek → aktualny **Kabul Oranı** w dużej czcionce DM Sans
- Przeciąganie natywne (Android `WindowManager`) — nie blokuje dotknięć poza pigułką
- Synchronizacja z ekranem głównym przez SharedPreferences + `OverlaySync`

Włącz/wyłącz z dolnego paska ekranu głównego.

### Kazanç Takibi — śledzenie zysku

Nowy ekran (przycisk 💰 **Kazanç** w dolnym pasku) oblicza **rzeczywisty zysk netto** na podstawie danych z ekranu Uber Driver:

**Wpisywane ręcznie (pola formularza):**

| Pole | Źródło w Uber |
|---|---|
| Net Gelir | Duża liczba u góry ekranu Kazançlar |
| Pompada Ödenen | Kwota zapłacona na stacji |
| Alınan Nakit | Gotówka odebrana od pasażerów |
| Çevrimiçi Süre | Godziny + minuty online |
| Yolculuk Sayısı | Liczba kursów w tygodniu |
| Kira İndirimi | Przełącznik — czy obowiązuje zniżka na wynajem |

**Obliczane automatycznie:**

| Składnik | Reguła |
|---|---|
| VAT (11,5%) | `netIncome × 0,115` |
| Komisyon | Tabela progów obrotu (0–999 → 50+1%, …, 3000+ → 0) |
| Yakıt (10% rabatu) | `pompada × 0,90` |
| İdari Gider | Stałe **40 PLN** |
| Kira | **Zawsze pobierana.** Zniżka ON → próg wg liczby kursów (850/650/450/250 PLN); OFF → płaska stawka **850 PLN** |
| Net Kâr | Net Gelir − wszystkie powyższe |
| Saatlik Kazanç | Net Kâr ÷ godziny online |
| Hesaba Yatacak | Net Kâr − Alınan Nakit |

**Widoki:**

- **Haftalık** — wykres trendu (ostatnie 12 tygodni), selektor tygodnia, karta bohatera ze stawką godzinową, rozbicie kosztów, historia
- **Aylık** — podsumowanie miesiąca, wykres średniej stawki, karta 🏆 najlepszego tygodnia w wybranym miesiącu
- **Yıllık** — podsumowanie roku, wykres roczny, lista miesięcy

Dane przechowywane lokalnie (`earnings_history`, max 104 tygodnie = 2 lata).

---

## 🔒 Bezpieczeństwo i polityka prywatności

Prywatność kierowcy jest priorytetem:

- **100% lokalnie** — aplikacja nie łączy się z zewnętrznymi serwerami (poza opcjonalnym sprawdzeniem aktualizacji z GitHub Gist)
- **Zero danych osobowych** — brak GPS, numeru telefonu, danych logowania Uber/Bolt
- **SharedPreferences** — wszystkie statystyki i historia kazanç tylko na urządzeniu
- **Backup wyłączony** — `allowBackup=false` zapobiega przypadkowemu wyciekowi przez kopię zapasową Android
- **Minimalne uprawnienia** — overlay, foreground service, wakelock, wibracja
- **Weryfikacja podpisu APK** — w wersji release porównanie z `APP_SIGNATURE` z `.env` (obfuskowane przez `envied`)
- **Hardened OTA** — manifest tylko z `gist.githubusercontent.com`; APK tylko z `github.com/emiroys/ratehelper/releases/latest/download/app-arm64-v8a-release.apk`

---

## 🌍 Języki

Interfejs użytkownika: **Turecki** (domyślny), **Angielski**, **Polski**.

Język wykrywany automatycznie przy pierwszym uruchomieniu; można zmienić z dolnego paska (przycisk **Dil**).

---

## 📋 Wymagania

| | |
|---|---|
| Platforma | Android (docelowo Samsung Galaxy S24 Ultra, arm64) |
| Flutter SDK | 3.x+ |
| Android Studio | z Java JDK |
| Architektura APK | `arm64-v8a` (split-per-abi) |

---
