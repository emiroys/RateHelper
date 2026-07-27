# RateHelper — Przewodnik instalacji i obsługi

Ten przewodnik krok po kroku wyjaśnia, **jakie uprawnienia Androida** trzeba włączyć oraz **jak korzystać z aplikacji** na co dzień.

> **Docelowe urządzenie:** Android (zoptymalizowane pod flagowce typu Samsung Galaxy S24 Ultra)  
> **Szacowany czas konfiguracji:** 2–3 minuty

---

## 1) Zainstaluj APK

1. Skopiuj otrzymany plik APK na telefon (WhatsApp, USB, e-mail — bez różnicy).  
   Nazwa pliku to zwykle `app-arm64-v8a-release.apk` lub `ratehelper.apk`.
2. Dotknij pliku. Jeśli telefon poprosi o **„Instalację z nieznanych źródeł”** → **Zezwól** → wróć do APK → **Zainstaluj**.
3. Przy pierwszym uruchomieniu aplikacja automatycznie otworzy ekran **Konfiguracja RateHelper**.

> Aby ponownie przeczytać instrukcję: ekran główny → menu **⋮** (prawy górny róg) → **Przewodnik konfiguracji**.

---

## 2) Pierwsza konfiguracja — dwa wymagane uprawnienia

RateHelper potrzebuje **dwóch uprawnień Androida**, aby działać nad aplikacją Uber Driver i nie być zabijany w tle podczas zmiany.

### Krok 1 — Nakładka nad innymi aplikacjami

Na ekranie konfiguracji naciśnij **„NADAJ UPRAWNIENIE”**. Otworzą się ustawienia systemu.

1. Znajdź na liście aplikację **RateHelper**.
2. Włącz przełącznik (**WŁ.**).
3. Wróć do RateHelper przyciskiem Wstecz.

Jeśli na karcie kroku widzisz zielone **NADANO** — gotowe.

### Krok 2 — Wyłącz optymalizację baterii

Wybierz markę telefonu na ekranie konfiguracji, a następnie naciśnij **„OTWÓRZ USTAWIENIA”**.

#### Samsung (One UI)

`Ustawienia` → `Konserwacja urządzenia` → `Bateria` → `Limity użycia w tle` → `Aplikacje, które nigdy nie usypiają` → **+** → dodaj **RateHelper**.

#### Xiaomi / Redmi / POCO (MIUI / HyperOS)

Zrób obie rzeczy:

1. `Ustawienia` → `Aplikacje` → `RateHelper` → `Oszczędzanie baterii` → **Brak ograniczeń**
2. Na tej samej stronie: `Autostart` → **WŁ.**

#### Huawei / Honor (EMUI)

`Ustawienia` → `Aplikacje` → `RateHelper` → `Bateria` → `Uruchamianie aplikacji` → **Wyłącz** „Zarządzaj automatycznie” → włącz **wszystkie trzy** przełączniki (`Autostart`, `Uruchomienie pośrednie`, `Działanie w tle`).

#### OnePlus / Oppo / Realme (OxygenOS / ColorOS)

`Ustawienia` → `Bateria` → `Optymalizacja baterii` → **RateHelper** → **Nie optymalizuj**.

**Dodatkowo:** W ekranie ostatnich aplikacji (Recents) dotknij ikony **kłódki** na karcie RateHelper — nie zostanie usunięty przy czyszczeniu.

#### Inne marki

W `Ustawienia` → `Bateria` lub `Aplikacje` znajdź **RateHelper** i wyłącz optymalizację baterii albo ustaw **„Bez ograniczeń”**.

### Zakończ konfigurację

Gdy oba kroki są gotowe, naciśnij **ZAKOŃCZ** na dole ekranu. Przejdziesz do ekranu głównego.

---

## 3) Ekran główny — liczniki

Na ekranie głównym są cztery duże liczniki:

| Licznik | Znaczenie |
| --- | --- |
| **Zaakceptowane** | Zlecenia, które zaakceptowałeś |
| **Odrzucone** | Zlecenia, które odrzuciłeś |
| **Ukończone** | Zakończone przejazdy |
| **Anulowane** | Anulowane przejazdy |

**Wskaźnik akceptacji** i **wskaźnik anulowań** liczą się automatycznie. Gdy spadniesz poniżej celu, zobaczysz pomarańczowe/czerwone ostrzeżenie i informację, **ile akceptacji z rzędu** potrzebujesz.

### Edycja licznika

Pomyłka w liczbie? **Dotknij** lub **przytrzymaj** wartość licznika → wpisz poprawną liczbę → **ZAPISZ**.

### Automatyczne ukończenie

Włącz przełącznik **„Automatyczne ukończenie”** — przy każdym **+1** na akceptacji licznik ukończonych przejazdów też rośnie.

### Reset tygodnia

Po zakończeniu tygodnia naciśnij **RESETUJ TYDZIEŃ**. Podsumowanie tygodnia trafi do archiwum, zanim liczniki wrócą do zera.

---

## 4) Pływający widget (licznik nad Uberem)

Podczas zmiany możesz liczyć zlecenia bez zamykania Ubera — mała **pływająca pigułka** na ekranie.

### Włącz / wyłącz widget

W dolnym menu naciśnij duży środkowy przycisk:

- **▶ Uruchom** → widget pojawia się nad Uberem
- **⏹ Zatrzymaj** → widget znika

### Obsługa widgetu

| Przycisk | Funkcja |
| --- | --- |
| **Zielony ➕** | Zaakceptowane zlecenie (+1) |
| **Czerwony ➖** | Odrzucone zlecenie (+1) |
| **% na środku** | Aktualny wskaźnik akceptacji |

Widget możesz **przeciągać** w dowolne miejsce ekranu. Jest mały (276×80 dp), żeby nie zasłaniać dotyku w Uberze.

> Gdy widget jest wyłączony, wróć na ekran główny i używaj dużych przycisków **+ / −**.

---

## 5) Dolne menu (5 przycisków)

| Ikona | Nazwa | Do czego służy |
| --- | --- | --- |
| 🌐 | **Język** | Wybór: turecki / angielski / polski |
| ▶/⏹ | **Uruchom / Zatrzymaj** | Włącza lub wyłącza pływający widget |
| 📋 | **Logi** | Historia dotknięć + archiwum tygodniowe |
| 📡 | **Radar** | Nadchodzące wydarzenia w Krakowie (nasilenie popytu) |
| 💰 | **Zarobki** | Tygodniowy dochód, koszty i zysk netto |

---

## 6) Ekran logów

Po naciśnięciu **Logi** otwiera się panel z **dwoma zakładkami**:

### Historia dotknięć

Lista każdego naciśnięcia **+ / −** z godziną. Filtr **Dziś** / **Wszystko**. Wyczyść ikoną kosza w prawym górnym rogu.

### Archiwum tygodniowe

Przy każdym **RESETUJ TYDZIEŃ** zapisywane są wskaźniki akceptacji i anulowań z tego tygodnia. Starsze wpisy też można przeglądać.

---

## 7) Śledzenie zarobków (💰)

Ekran **Zarobki** liczy tygodniowy przychód z Ubera, paliwo, czynsz, podatki i zysk netto. **Wszystkie dane zostają w telefonie** — nic nie trafia do chmury.

### Pierwsze uruchomienie

1. Wybierz **Jeden kierowca** albo **Dwóch kierowców (Dzielony)** — tabele czynszu zależą od tego wyboru.
2. Wypełnij formularz tygodniowy: **Dochód netto**, **Otrzymana gotówka**, **Czas online**, **Liczba przejazdów**, paragony za paliwo itd.

### Widoki

U góry przełącznik **Tygodniowy / Miesięczny / Roczny**. W widoku miesięcznym widać kartę najlepszego tygodnia i wykresy.

### Eksport PDF

Ikona udostępniania u góry → **Eksportuj do PDF** → wybierz zakres dat → wyślij do księgowej lub zachowaj u siebie.

### Licznik darmowego tygodnia czynszu

Po **2000 przejazdach** zdobywasz prawo do zniżki czynszu. Ten licznik **nigdy nie maleje** — nawet gdy stare tygodnie są usuwane z historii.

---

## 8) Radar wydarzeń (📡)

Lista koncertów, meczów i dużych imprez w **Krakowie**. Pomaga przewidzieć dni ze wzmożonym popytem (surge).

- Lista **aktualizuje się z internetu** (tylko publiczne dane o wydarzeniach — bez wysyłania Twoich finansów).
- Pociągnij w dół, aby **Odświeżyć**.
- Dane są w pamięci podręcznej przez 1 godzinę.

---

## 9) Licznik z kierownicy (opcjonalnie, Beta)

Jeśli chcesz liczyć bez odrywania rąk od kierownicy:

1. Na ekranie głównym włącz **„Licznik z kierownicy (Beta)”**.
2. Gdy poprosi o **uprawnienie dostępności** → **OTWÓRZ USTAWIENIA** → włącz usługę RateHelper.
3. Obsługa:
   - **Przytrzymaj 800 ms** przycisk **następnego utworu / play-pause** → +1 zaakceptowane
   - **Przytrzymaj 800 ms** przycisk **poprzedniego utworu** → +1 odrzucone
   - **Krótkie naciśnięcie** → Spotify / YouTube Music działają normalnie

> Funkcja korzysta z usługi **Ułatwienia dostępu** Androida. Nie musisz jej włączać — reszta aplikacji działa bez niej.

---

## 10) Zmiana trybu kierowcy

Jeździsz autem na zmiany z drugą osobą?

Menu **⋮** (prawy górny róg) → wybierz **Jeden kierowca** lub **Dwóch kierowców (Dzielony)**.

> Tryb zapisany w starych tygodniach **się nie zmienia** — nowy tryb dotyczy tylko nowych wpisów.

---

## 11) Rozwiązywanie problemów

### Aplikacja się zamyka lub widget znika

1. Przeczytaj ponownie **Przewodnik konfiguracji** (menu **⋮**) — sprawdź nakładkę i optymalizację baterii.
2. **Zatrzymaj** widget → **Uruchom** ponownie.
3. Na Samsungu **zablokuj** kartę RateHelper w ostatnich aplikacjach.

### Wysyłanie dziennika awarii

1. Menu **⋮** → **Dziennik awarii**
2. Naciśnij **KOPIUJ**
3. Wklej i wyślij przez WhatsApp do developera

> Dzienniki są w **wewnętrznej** pamięci aplikacji (sandbox). Nie ma do nich dostępu z menedżera plików — używaj tylko **KOPIUJ** w aplikacji.

### Aktualizacja (OTA)

Gdy pojawi się nowa wersja, na dole ekranu zobaczysz powiadomienie. **Pobierz** instaluje APK z GitHuba. Musi być ta sama sygnatura co poprzednia instalacja — nie używaj nieoficjalnych źródeł.

---

## 12) Notatki dla developera (tylko maintainer)

Build produkcyjny:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/
```

- `--obfuscate` → usuwa symbole Dart AOT.
- `--split-debug-info` → symbole poza projektem (zachowaj do debugowania).
- `--split-per-abi` → APK ~8 MB na architekturę.

Jeśli istnieje `android/key.properties`, podpisywanie jest automatyczne. Bez niego używany jest klucz debug — użytkownik **nie zaktualizuje** aplikacji (niezgodność podpisu). Używaj tego samego keystore w każdej wersji.

Architektura: [`README.md`](README.md) · Notatki agenta: [`agent-learnings.md`](agent-learnings.md)

---

> **RateHelper** — Napisany z perspektywy fotela kierowcy, dla Twojego realnego zarobku na krakowskich drogach.
