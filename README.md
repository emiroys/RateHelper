# Anti-Eres (ubertakip) 🚖

Anti-Eres to otwartoźródłowy, lokalny asystent kierowcy zbudowany w technologii Flutter. Aplikacja pomaga kierowcom rideshare (Uber/Bolt) śledzić w czasie rzeczywistym statystyki akceptacji, odrzuceń, anulowań oraz ukończonych kursów — za pomocą pływającego wskaźnika Live Overlay (`SYSTEM_ALERT_WINDOW`), który działa nad innymi aplikacjami bez konieczności zamykania głównych programów do pracy.

## 🔥 Główne Funkcje

- **Wskaźnik procentowy na żywo (Live Overlay):** pływający widżet nad aplikacjami Uber/Bolt pokazuje aktualny wskaźnik akceptacji w procentach.
- **Szybkie zliczanie jednym dotknięciem:** wygodne liczniki na ekranie pozwalają aktualizować statystyki podczas jazdy bez rozpraszania uwagi.
- **Zaawansowane ręczne wprowadzanie z klawiatury:** długie przytrzymanie dowolnej metryki na ekranie głównym otwiera szybkie wpisywanie wartości z klawiatury.
- **Tygodniowy reset statystyk:** automatyczne lub ręczne zerowanie wyników w cyklu tygodniowym.
- **Tryb Wakelock:** utrzymuje ekran włączony podczas pracy, zapobiegając jego wygaszaniu i blokowaniu.

## 🔒 Bezpieczeństwo i Polityka Prywatności

Prywatność kierowcy jest priorytetem — aplikacja została zaprojektowana tak, aby dane nigdy nie opuszczały urządzenia:

- **Działanie w 100% lokalnie (Local-Only):** aplikacja **nie nawiązuje** połączeń z zewnętrznymi serwerami. Nie korzysta z Firebase, analityki ani telemetrii.
- **Zero zbierania danych osobowych:** aplikacja nie odczytuje, nie zapisuje ani nie przekazuje imienia, numeru telefonu, lokalizacji GPS ani danych logowania do kont Uber/Bolt.
- **Bezpieczne przechowywanie lokalne:** wszystkie statystyki są zapisywane wyłącznie na urządzeniu użytkownika (SharedPreferences). Kopia zapasowa w chmurze jest wyłączona (`allowBackup=false`), aby zapobiec niezamierzonemu wyciekowi danych.
- **Zasada minimalnych uprawnień:** aplikacja żąda wyłącznie uprawnień niezbędnych do działania — wyświetlania nad innymi aplikacjami (overlay) oraz uruchamiania usługi w tle.

## 🛠️ Jak samodzielnie zbudować aplikację

Poniżej znajduje się instrukcja krok po kroku dla deweloperów, którzy chcą skompilować aplikację ze źródeł.

### 1. Wymagania wstępne

- Flutter SDK (3.x lub nowszy)
- Android Studio i Java JDK

### 2. Pobieranie kodu

```bash
git clone https://github.com/emiroys/anti-eres.git
cd anti-eres
```

### 3. Konfiguracja pliku środowiskowego (`.env`)

W katalogu głównym projektu utwórz plik `.env` na podstawie szablonu `.env.example`. Wypełnij go własnymi wartościami:

```env
APP_SIGNATURE=1234567890ABCDEF
GIST_URL=https://gist.githubusercontent.com/twoj-profil/update.json
```

### 4. Pobieranie zależności i generowanie kodu

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### 5. Kompilacja pliku APK

```bash
flutter build apk --release --split-per-abi
```

Gotowy plik produkcyjny APK znajdziesz w katalogu `build/app/outputs/flutter-apk/`.
