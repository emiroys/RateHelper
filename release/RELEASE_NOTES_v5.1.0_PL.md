# RateHelper v5.1.0

*(20 października 2026)*

## Najważniejsze zmiany

- **Centrum paliw ORLEN:** nowa zakładka z **30 stacjami ORLEN w Krakowie**, cenami **PB95 i LPG**, zgłaszaniem cen przez kierowców, nawigacją **Google Maps / Waze** oraz paragonami paliwowymi. Listę można sortować po **najtańszej** lub **najbliższej** stacji.
- **Sterowanie z powiadomień:** opcjonalne przyciski **Odrzuć +1** i **Akceptuj +1** w powiadomieniu nakładki, z bieżącym wskaźnikiem akceptacji. Można też włączyć **tryb tylko-powiadomienia** („Yüzen baloncuğu gizle”), który ukrywa dymek, a licznik działa dalej z panelu i z kierownicy.
- **Kopia zapasowa i przywracanie:** pełny, lokalny eksport ustawień, liczników, archiwum tygodni i zarobków do pliku JSON, z podglądem przed przywróceniem, kontrolą integralności SHA-256 i dziennikiem odtwarzania po nagłym zamknięciu aplikacji. **Plik kopii nie jest zaszyfrowany** — traktuj go jak dane wrażliwe.
- **Nowy kreator pierwszego uruchomienia:** pięć kroków — powitanie, uprawnienie nakładki, niezawodność baterii, funkcje opcjonalne i podsumowanie. Wybór języka **turecki / polski / angielski** jest dostępny od pierwszego ekranu.
- **Zgłaszanie błędów z aplikacji:** ekran „Zgłoś problem” pozwala opisać problem i dołączyć — opcjonalnie — zrzut ekranu, diagnostykę urządzenia oraz dziennik błędów. Opis jest czyszczony z danych wrażliwych; dziennik jest domyślnie wyłączony.
- **Jednorazowa ankieta cenowa:** po aktualizacji (lub po kreatorze na nowej instalacji) aplikacja prosi o odpowiedź na trzy krótkie pytania o przyszłość RateHelper. Odpowiedzi są anonimowe i wysyłane tylko raz; jeśli telefon jest offline, zapisują się lokalnie i wysyłają później. **Aplikacja pozostaje darmowa — ankieta nie uruchamia subskrypcji ani płatności.**
- **Niezawodność:** poprawki synchronizacji liczników między dymkiem a ekranem głównym, trwalszego zapisu zmian, archiwum tygodni (cel i progi zapisane w danych tygodnia, scalanie podwójnego resetu), obliczeń zarobków i odzyskiwania danych po restarcie.
- **Ustawienia:** pogrupowane karty (jazda i liczniki, dymek, preferencje, system i pomoc), wiersz **Kontakt z deweloperem** oraz przeniesione tam **Sprawdź aktualizacje** i **Kreator konfiguracji**.

## Paliwa ORLEN w szczegółach

Dymek „Paliwo” na ekranie głównym otwiera centrum paliw:

- **Stacje:** 30 potwierdzonych stacji ORLEN w granicach Krakowa. Odległość liczona jest tylko wtedy, gdy wybierzesz sortowanie **Najbliższe** i wyrazisz zgodę na dostęp do lokalizacji.
- **Ceny:** własne ceny PB95/LPG pochodzą z zatwierdzonych zgłoszeń kierowców i są pobierane z lekkiego backendu Cloudflare. Bez skonfigurowanego `ORLEN_API_URL` stacje, sortowanie, nawigacja i paragony nadal działają — wyłączone są tylko zdalne ceny i zgłaszanie.
- **Zgłaszanie ceny:** wybierz stację i paliwo, wpisz cenę; trafia ona do zatwierdzenia przez maintainera, a dopiero po akceptacji jest widoczna dla wszystkich.
- **Nawigacja:** przycisk kierunków otwiera Google Maps albo Waze.
- **Paragony:** druga zakładka centrum paliw pozwala zapisać kwotę zatankowania, z podziałem na współkierowców; paragony pojawiają się w tygodniowym rozliczeniu zarobków.

> Nie każda stacja musi fizycznie oferować LPG. Model danych obsługuje cenę LPG tam, gdzie stacja ją sprzedaje; brak ceny nie oznacza automatycznie braku tego paliwa na stacji.

## Kopia zapasowa — jak o nią dbać

- **Eksport:** Ustawienia → **Kopia zapasowa danych**. Zapisz plik JSON w bezpiecznym miejscu.
- **Przywracanie:** Ustawienia → **Przywróć z kopii**. Zobaczysz podgląd (wersja, tydzień liczników, liczba wpisów) przed potwierdzeniem.
- **Nie jest zaszyfrowana:** każdy, kto ma plik, może odczytać zapisane dane. Nie wysyłaj go publicznymi kanałami.
- **Odzyskiwanie:** jeśli aplikacja zostanie zamknięta w trakcie przywracania, przy następnym uruchomieniu dokończy operację z dziennika odtwarzania.

## Ankieta i prywatność

- Ankieta zawiera **trzy pytania** i nie da się jej pominąć; pokazuje się **raz na instalację**.
- Odpowiedzi nie zawierają imienia, telefonu, e-maila, GPS, przejazdów ani zarobków. Zawierają wyłącznie identyfikator instalacji (losowy), wersję ankiety i trzy wybrane odpowiedzi.
- Jeśli nie ma internetu, odpowiedź zostaje zapisana na urządzeniu i wysłana przy następnym uruchomieniu aplikacji na pierwszym planie.
- Większość danych jazdy i rozliczeń zostaje na telefonie. Do backendu Cloudflare trafiają tylko **zgłoszenia cen paliwa**, **raporty błędów** i **odpowiedzi ankiety** — i tylko wtedy, gdy korzystasz z tych funkcji. Zrzut ekranu lub opis w raporcie błędu mogą zawierać dane osobowe; dołączaj je świadomie.
- Aplikacja nie zakłada konta, nie używa reklamowych identyfikatorów ani zewnętrznych narzędzi analitycznych.

## Bez zmian (to nie są nowości)

Działają jak dotąd: pływający dymek, podstawowe liczniki i procent akceptacji, licznik 2000 przejazdów, cele i archiwum tygodniowe, Radar wydarzeń, eksport PDF, trzy języki interfejsu (z wykrywaniem języka urządzenia przy pierwszym uruchomieniu) oraz mechanizm aktualizacji przez GitHub.
