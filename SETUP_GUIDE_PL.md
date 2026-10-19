# RateHelper — Przewodnik instalacji i obsługi

Ten przewodnik krok po kroku wyjaśnia, **jakie uprawnienia Androida** trzeba włączyć oraz **jak korzystać z aplikacji** na co dzień.

> **Docelowe urządzenie:** Android (zoptymalizowane pod flagowce typu Samsung Galaxy S24 Ultra)  
> **Szacowany czas konfiguracji:** 2–3 minuty  
> **Wersja turecka:** [`SETUP_GUIDE_TR.md`](SETUP_GUIDE_TR.md)

> **Przewodnik konfiguracji w aplikacji** (**Ustawienia** → ikona **koła zębatego**) otwiera ponownie **pięcioetapowy kreator**: powitanie, uprawnienie nakładki, niezawodność baterii, funkcje opcjonalne i podsumowanie. Ten plik to **pełna instrukcja obsługi**.

---

## 1) Zainstaluj APK

1. Skopiuj otrzymany plik APK na telefon (WhatsApp, USB, e-mail — bez różnicy).  
   Nazwa pliku to zwykle `app-arm64-v8a-release.apk` lub `ratehelper.apk`.
2. Dotknij pliku. Jeśli telefon poprosi o **„Instalację z nieznanych źródeł”** → **Zezwól** → wróć do APK → **Zainstaluj**.
3. Przy pierwszym uruchomieniu aplikacja otworzy **pięcioetapowy kreator konfiguracji**: powitanie, uprawnienie nakładki, niezawodność baterii, funkcje opcjonalne i podsumowanie. Język (turecki / polski / angielski) wybiera się już na pierwszym ekranie.
4. Po konfiguracji (albo po pierwszej aktualizacji do tej wersji) może najpierw pojawić się **jednorazowa, krótka ankieta**, a dopiero potem **raz** pytanie o GitHuba: automatyczne aktualizacje i wydarzenia w Krakowie. **Nie** = brak sieci przy starcie; dane jazdy zostają w telefonie — włączysz później w **Ustawieniach**.

> Instrukcję ponownie: ekran główny → **koło zębate (Ustawienia)** → **Przewodnik konfiguracji**.

---

## 2) Pierwsza konfiguracja — dwa wymagane uprawnienia (część pięcioetapowego kreatora)

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

Ikona **koła zębatego** u góry otwiera **Ustawienia** (tryb jazdy, dymek, język, GitHub, aktualizacja, dziennik awarii). Na ekranie głównym zostają: cel tygodniowy, liczniki, **RESETUJ TYDZIEŃ**, odznaka **KK383CT** i wersja.

Na ekranie głównym są cztery duże liczniki:

| Licznik | Znaczenie |
| --- | --- |
| **Zaakceptowane** | Zlecenia, które zaakceptowałeś |
| **Odrzucone** | Zlecenia, które odrzuciłeś |
| **Ukończone** | Zakończone przejazdy |
| **Anulowane** | Anulowane przejazdy |

**Wskaźnik akceptacji** i **wskaźnik anulowań** liczą się automatycznie.

### Kolorowe ostrzeżenia (3 stany)

Kolor karty akceptacji zależy od wybranego **Tygodniowego Celu Przejazdów**:

| Kolor | Znaczenie |
| --- | --- |
| **Zielony** | Jesteś powyżej wymaganego progu |
| **Bursztynowy** | Bezpiecznie, ale blisko — seria odrzuceń może obniżyć próg poniżej wymogu |
| **Czerwony** | Poniżej celu — ekran pokazuje, **ile akceptacji z rzędu** potrzebujesz |

### Tygodniowy cel przejazdów

Dotknij chipu celu u góry → wybierz **Tygodniowy Cel Przejazdów**. Każdy próg odpowiada minimalnej liczbie przejazdów i akceptacji wymaganej przez ERES do zniżki czynszu (np. 100–149 przejazdów, min. 80% akceptacji). Opcja **Brak Wymag.** służy tylko do liczenia.

> Progi zależą od trybu **Jeden / Dwóch / Trzech kierowców** (**Ustawienia → Tryb jazdy**).

### Karta budżetu anulowań

Gdy cel jest wybrany (oprócz Brak Wymag.), ekran pokazuje, ile anulowań możesz jeszcze wykonać w ramach limitu **5%**. Po przekroczeniu — czerwone ostrzeżenie.

### Cofnij (undo)

Ikona **↩ cofnij** w lewym górnym rogu cofa **jedną** ostatnią zmianę licznika.

### Edycja licznika

Pomyłka w liczbie? **Dotknij** lub **przytrzymaj** wartość licznika → wpisz poprawną liczbę → **ZAPISZ**.

### Automatyczne ukończenie

W **Ustawienia → Automatyczne ukończenie** — przy każdym **+1** na akceptacji licznik ukończonych przejazdów też rośnie.

### Reset tygodnia

Po zakończeniu tygodnia naciśnij **RESETUJ TYDZIEŃ**. Podsumowanie tygodnia trafi do archiwum, zanim liczniki wrócą do zera.

> Automatyczna granica tygodnia: **poniedziałek 04:00** (czas warszawski). Strefa czasowa telefonu nie ma znaczenia — aplikacja używa `Europe/Warsaw`.

---

## 3b) Ekran ustawień (koło zębate)

Ekran główny → **koło zębate** u góry. Sekcje:

| Sekcja | Zawartość |
| --- | --- |
| **Jazda i liczniki** | **Tryb jazdy** (1 / 2 / 3 kierowców), **Automatyczne ukończenie**, **Licznik z kierownicy (Beta)**, **Utrzymuj ekran włączony** |
| **Dymek** | **Kierunek dymka** (poziomy / pionowy), **Przycisk anulowania na dymku** (opcjonalnie), **Sterowanie z powiadomienia** (opcjonalnie), **Ukryj pigułkę** (przy włączonym sterowaniu z powiadomienia) |
| **Preferencje** | **Język**, **Automatyczne sprawdzanie aktualizacji**, **Automatyczne pobieranie wydarzeń** |
| **Paliwo** | **Ceny paliw ORLEN** — 30 stacji, PB95/LPG, sortowanie najtańsze/najbliższe, nawigacja |
| **Dane** | **Kopia zapasowa danych**, **Przywróć z kopii** |
| **System i wsparcie** | **Sprawdź aktualizacje** (czas ostatniego sprawdzenia + wersja), **Przewodnik konfiguracji**, **Dziennik awarii**, **Zgłoś problem**, **Kontakt z deweloperem** |

> Język można też zmienić ikoną 🌐 w dolnym menu — to ten sam wybór.

---

## 3c) Centrum paliw ORLEN

Przycisk **Paliwo** na ekranie głównym (albo Ustawienia → **Ceny paliw ORLEN**) otwiera centrum z dwiema zakładkami:

### Stacje

- Lista **30 zweryfikowanych stacji ORLEN** w granicach Krakowa.
- Przełącznik u góry sortuje po **najtańszej** lub **najbliższej** stacji. **Najbliższa** liczy odległość tylko po przyznaniu dostępu do lokalizacji; bez zgody lista zostaje w poprzedniej kolejności.
- Każda karta pokazuje cenę PB95 i (jeśli jest) LPG, czas aktualizacji oraz przycisk **nawigacji**. Nawigacja otwiera Google Maps albo Waze.
- Ceny pochodzą ze zgłoszeń kierowców zatwierdzonych przez maintainera. W buildzie bez `ORLEN_API_URL` stacje, sortowanie, nawigacja i paragony działają; wyłączone są tylko zdalne ceny i zgłaszanie.

### Zgłaszanie ceny

1. Wybierz stację → **Zaktualizuj cenę**.
2. Wybierz paliwo (PB95 / LPG) i wpisz cenę.
3. Wyślij; zgłoszenie trafia najpierw do zatwierdzenia. Po akceptacji widać je dla wszystkich.

> Nie każda stacja musi fizycznie oferować LPG. Cena LPG jest pokazywana tylko tam, gdzie model danych to obsługuje; brak ceny nie oznacza automatycznie braku tego paliwa.

### Paragony paliwowe

W drugiej zakładce (**Dodaj paliwo**) zapiszesz kwotę tankowania, szybkie kwoty albo podział między współkierowców. Paragony trafiają do tygodniowego rozliczenia zarobków.

---

## 3d) Kopia zapasowa i przywracanie

- **Eksport:** Ustawienia → **Kopia zapasowa danych**. Aplikacja zapisuje ustawienia, liczniki zmiany, archiwum tygodni i zarobki do jednego pliku JSON. Trzymaj go w bezpiecznym miejscu.
- **Przywracanie:** Ustawienia → **Przywróć z kopii**. Przed potwierdzeniem zobaczysz **podgląd** (wersja, tydzień liczników, liczba wpisów). Możesz anulować.
- **Bezpieczeństwo:** Kopia **nie jest zaszyfrowana** — każdy, kto ma plik, może odczytać jego zawartość. Nie wysyłaj jej publicznymi kanałami ani nie wrzucaj bez namysłu do chmury.
- **Odzyskiwanie:** Jeśli aplikacja zostanie zamknięta w trakcie przywracania, następne uruchomienie dokończy operację z dziennika; nie zostanie połowicznie zapisany stan.
- Ukończenie ankiety nie jest częścią kopii — przywrócenie **nie pokaże ankiety ponownie**.

---

## 3e) Zgłaszanie problemu, dziennik awarii i jednorazowa ankieta

### Zgłoś problem

Ustawienia → **Zgłoś problem**:

1. Wybierz kategorię (np. dymek, liczniki, zarobki/paliwo, kierownica/powiadomienia, inne) i opisz problem.
2. Przed wysłaniem otwiera się **podgląd**; dane wrażliwe są w miarę możliwości czyszczone.
3. Opcjonalnie dołącz **zrzut ekranu**, **diagnostykę urządzenia** i **dziennik błędów**. Dziennik jest domyślnie **wyłączony**.
4. **Wyślij** — raport trafia do developera przez backend Cloudflare.

> Zrzut ekranu lub opis mogą zawierać dane osobowe; dołączaj je świadomie i przeczytaj podgląd przed wysłaniem.

### Dziennik awarii

Ustawienia → **Dziennik awarii** → **KOPIUJ**. Dzienniki są w wewnętrznej pamięci aplikacji (sandbox); nie ma do nich dostępu z menedżera plików — można je tylko skopiować i wysłać.

### Jednorazowa ankieta cenowa

- Pokazuje się **raz**: po aktualizacji (istniejąca instalacja) albo po pięcioetapowym kreatorze (nowa instalacja).
- Ma trzy pytania; **nie ma** przycisku Pomiń / Później / Nie pokazuj ponownie i nie da się jej zamknąć przyciskiem Wstecz.
- Odpowiedzi są anonimowe; nie zawierają imienia, telefonu, e-maila, GPS, przejazdów ani zarobków. Wysyłany jest tylko losowy identyfikator instalacji, wersja ankiety i trzy odpowiedzi.
- Bez internetu odpowiedź zostaje zapisana lokalnie i wysyła się przy następnym uruchomieniu / powrocie aplikacji na pierwszy plan.
- **Aplikacja pozostaje darmowa; ankieta nie uruchamia subskrypcji ani płatności.** Celem jest zrozumienie, jak dalej rozwijać projekt.

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
| **% na środku** | Aktualny wskaźnik akceptacji. **Dotknij** → widget zwija się do małego dymka **R** |
| **Dymek R** | **Dotknij** → widget rozwija się z powrotem |

Widget możesz **przeciągać** w dowolne miejsce ekranu. Poziomo ok. **276×80 dp**; pionowo: **Ustawienia → Kierunek dymka → Pionowy** (~74×194 dp).

Dotknij **%**, by zwolnić miejsce: dymek **R** (48 dp); dotknięcia obok trafiają do Ubera. Dotknij **R**, by wrócić do pełnego dymka. Dymek też można przeciągać. +/−, zapis i kierownica działają w stanie zwiniętym. Stan jest zapamiętywany.

**Ustawienia → Przycisk anulowania na dymku** — opcjonalny pomarańczowy przycisk obok czerwonego **−**.

Liczniki na ekranie głównym **od razu** odzwierciedlają zmiany z dymka (bez minimalizowania aplikacji).

### Sterowanie z powiadomienia (opcjonalnie)

Gdy **Ustawienia → Sterowanie z powiadomienia** jest włączone, a dymek otwarty, rozwiń panel powiadomień: po lewej jest duży przycisk **−** (Odrzuć +1), po prawej **+** (Akceptuj +1), a pośrodku bieżący wskaźnik akceptacji. Każde dotknięcie daje wibrację: jedną przy akceptacji, podwójną przy odrzuceniu. Możesz liczyć bez niczego na ekranie — np. zwiń dymek do **R** i używaj tylko panelu.

Jeśli nie chcesz niczego na ekranie, włącz zaraz pod spodem **Ukryj pływającą pigułkę (Tylko pasek powiadomień)**: po uruchomieniu dymek jest niewidoczny, a licznik działa tylko z panelu powiadomień (i z kierownicy). Wyłączenie sterowania z powiadomienia albo cofnięcie uprawnienia do powiadomień automatycznie przywraca dymek.

- Przy pierwszym włączeniu aplikacja poprosi o zgodę na powiadomienia. Bez zgody ustawienie zostaje wyłączone; zezwól w **Ustawienia → Aplikacje → RateHelper → Powiadomienia** i włącz je ponownie.
- Powiadomienie pokazuje tylko wskaźnik akceptacji i liczby zaakceptowanych/odrzuconych — bez zarobków. Nie pojawia się na ekranie blokady.
- Każde dotknięcie daje krótką wibrację. Wskaźnik odświeża się najwyżej raz na sekundę.

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

Przy każdym **RESETUJ TYDZIEŃ** podsumowanie trafia tutaj jako **karta**. Stuknij kartę → szczegóły (ukończone / zaakceptowane / odrzucone, cel tygodnia). Widać **Cel osiągnięty** lub **Cel nieosiągnięty** względem progów akceptacji i anulowań z tamtego tygodnia. Drugi reset w tym samym tygodniu scala liczniki w jedną kartę.

---

## 7) Śledzenie zarobków (💰)

Ekran **Zarobki** liczy tygodniowy przychód z Ubera, paliwo, czynsz, podatki i zysk netto. Większość danych jazdy i rozliczeń **zostaje w telefonie**. Do sieci wychodzą tylko funkcje uruchamiane świadomie: zgłoszenie ceny paliwa, raport błędu i jednorazowa ankieta (backend Cloudflare). Szczegóły w sekcjach 3e i 11.

### Pierwsze uruchomienie

1. Wybierz **Jeden / Dwóch / Trzech kierowców** (**Ustawienia → Tryb jazdy** lub pierwsza konfiguracja w Zarobkach) — tabele czynszu zależą od tego.
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

- Automatyczne pobieranie jest na starcie **wyłączone**. Przy wyłączonym przełączniku lista nie schodzi sama.
- Jeśli jest zapisana kopia, wydarzenia widać razem z **wiekiem tej kopii**. Gdy kopii nie ma, jest przycisk **Wczytaj wydarzenia**.
- Przycisk odświeżania u góry albo pociągnięcie w dół pobiera listę z GitHuba.
- Wychodzi tylko adres IP i zwykłe nagłówki żądania. Przejazdy i zarobki nie wychodzą.
- Adres: `raw.githubusercontent.com` (publiczna lista wydarzeń w Krakowie).

---

## 9) Licznik z kierownicy (opcjonalnie, Beta)

Jeśli chcesz liczyć bez odrywania rąk od kierownicy:

1. **Ustawienia → Licznik z kierownicy (Beta)** — włącz.
2. Gdy poprosi o **uprawnienie dostępności** → **OTWÓRZ USTAWIENIA** → włącz usługę RateHelper.
3. Obsługa:
   - **Przytrzymaj 800 ms** przycisk **następnego utworu / play-pause** → +1 zaakceptowane
   - **Przytrzymaj 800 ms** przycisk **poprzedniego utworu** → +1 odrzucone
   - **Krótkie naciśnięcie** → Spotify / YouTube Music działają normalnie

> Funkcja korzysta z usługi **Ułatwienia dostępu** Androida. Nie musisz jej włączać — reszta aplikacji działa bez niej.

---

## 10) Zmiana trybu kierowcy

Auto na zmiany w dwie lub trzy osoby?

Ekran główny → **koło zębate (Ustawienia)** → **Tryb jazdy** → **Jeden kierowca**, **Dwóch kierowców (Dzielony)** lub **Trzech kierowców (Dzielony)**.

> Tryb zapisany w starych tygodniach **się nie zmienia** — nowy tryb dotyczy tylko nowych wpisów. Przy 2–3 kierowcach **łączna liczba przejazdów auta** może wpływać na próg czynszu (formularz Zarobków).

---

## 11) Rozwiązywanie problemów

### Aplikacja się zamyka lub widget znika

1. **Ustawienia → Przewodnik konfiguracji** — sprawdź nakładkę i optymalizację baterii.
2. **Zatrzymaj** widget → **Uruchom** ponownie.
3. Na Samsungu **zablokuj** kartę RateHelper w ostatnich aplikacjach.

### Zgłoś problem (z aplikacji)

1. **Ustawienia → Zgłoś problem**
2. Wybierz kategorię, opisz problem i sprawdź podgląd.
3. Opcjonalnie dołącz zrzut ekranu / diagnostykę (dziennik błędów jest domyślnie wyłączony).
4. **Wyślij** — raport trafia do developera. Jeśli wysyłka się nie uda, możesz spróbować ponownie.

> Raport idzie przez backend Cloudflare; opis i zrzut ekranu mogą zawierać dane osobowe.

### Wysyłanie dziennika awarii

1. **Ustawienia → Dziennik awarii**
2. Naciśnij **KOPIUJ**
3. Wklej i wyślij przez WhatsApp do developera (albo użyj bezpośrednio **Zgłoś problem**)

> Dzienniki są w **wewnętrznej** pamięci aplikacji (sandbox). Nie ma do nich dostępu z menedżera plików — używaj tylko **KOPIUJ** w aplikacji.

### Aktualizacja (OTA)

Przy pierwszym uruchomieniu (i raz po aktualizacji do tej wersji) aplikacja pyta, czy sama sprawdzać GitHuba pod kątem aktualizacji i wydarzeń. **Zezwól** włącza oba przełączniki. **Nie, tylko gdy poproszę** zostawia oba wyłączone. Przełączniki da się zmienić w ustawieniach w każdej chwili.

Przy wyłączonych nic nie wychodzi w sieć przy starcie. **Ustawienia → Sprawdź aktualizacje** (na tym samym wierszu: ostatnie sprawdzenie i wersja). APK schodzi dopiero po stuknięciu aktualizacji w dialogu — samo sprawdzenie go nie pobiera. Pakiet przechodzi kontrolę podpisu i wersji; wymagany **ten sam podpis** co przy poprzedniej instalacji. Przełączniki auto-aktualizacji i wydarzeń są w sekcji **Preferencje** w Ustawieniach.

W tych żądaniach wychodzi adres IP i standardowe nagłówki. Twoje dane nie wychodzą.

- `gist.githubusercontent.com` — manifest wersji
- `api.github.com` — zapas, gdy manifest się nie wczyta
- `github.com` — APK (dopiero gdy stukniesz aktualizację)
- `raw.githubusercontent.com` — lista wydarzeń

---

## 12) Notatki dla developera (tylko maintainer)

Build produkcyjny:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=symbols/ --dart-define-from-file=dart_defines.json
```

- `--obfuscate` → usuwa symbole Dart AOT.
- `--split-debug-info` → symbole poza projektem (zachowaj do debugowania).
- `--split-per-abi` → APK ~8 MB na architekturę.
- `--dart-define-from-file` → dodaje lokalną konfigurację ignorowaną przez Git; nie wyświetlaj zawartości pliku ani nie dodawaj go do repozytorium. Musi zawierać **`ORLEN_API_URL`**; bez niego ceny paliw i zgłaszanie cen są wyłączone w buildzie release. `CONTACT_WHATSAPP` jest opcjonalny — bez niego „Kontakt z deweloperem” prowadzi do strony zgłoszeń GitHub.

`backend/orlen-worker/` to źródło Workera Cloudflare. Produkcyjny Worker aktualizuje się **ręcznie przez Cloudflare Dashboard**: wklej `dashboard-worker.js`; zachowaj binding `ORLEN_KV` oraz sekrety `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ADMIN_CHAT_ID`, `TELEGRAM_WEBHOOK_SECRET` i nowy `SURVEY_ADMIN_TOKEN` (tylko nazwy; nigdy nie wypisuj wartości). Webhook Telegrama musi być ustawiony z `allowed_updates=["callback_query","message"]`, aby komenda `/surveysummary` w czacie administratora działała. Pełna kolejność: [`release/YAYIN_TR.md`](release/YAYIN_TR.md).

`key.properties` musi leżeć w katalogu głównym projektu (nie w `android/`) i być czytelny. Brak albo błąd odczytu **przerywa build release** (`GradleException`) — klucz debug nie jest używany. Build debug działa bez tego pliku. Każda wersja tym samym keystore.

Architektura: [`README.md`](README.md) · Notatki agenta: [`agent-learnings.md`](agent-learnings.md) · Przewodnik turecki: [`SETUP_GUIDE_TR.md`](SETUP_GUIDE_TR.md)

---

> **RateHelper** — Napisany z perspektywy fotela kierowcy, dla Twojego realnego zarobku na krakowskich drogach.
