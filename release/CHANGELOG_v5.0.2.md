# RateHelper v5.0.2 — teknik değişiklik özeti

**Sürüm:** `5.0.2+7` (arm64 `versionCode` 2007)  
**Kaynak:** Health Check denetimi + polish turu (Eylül 2026)

---

## Baloncuk ↔ ana ekran (kritik)

- **Sorun:** Ana ekranda otomatik tamamlama, dil veya hedef değişince açık baloncuk eski ayarlarla kalıyordu; `+` bazen `completed` artırmıyordu.
- **Çözüm:** `OverlaySync.notifySettingsChanged()` + `settings_changed` mesajı (`overlay_sync.dart`). Overlay tarafında `_applyRemoteSettings()` — prefs cache’e güvenilmez (isolate başına bir kez `reload()`).
- **Dosyalar:** `home_screen.dart` (`_notifyOverlaySettings`), `overlay_widget.dart`, `overlay_sync.dart`.

## İptal bütçesi

- `maxAdditionalCancellations`: `completedTrips == 0` → `null` (boş hafta ≠ “0 iptal hakkı”).
- `home_screen.dart`, `test/logic_test.dart`.

## Soğuk açılış

- `main.dart`: `timezone/data/latest_10y.dart` (tek bölge: `Europe/Warsaw`).
- `test/timezone_data_test.dart`.

## Kazanç — yakıt tutarı

- `parsePlnAmount()` + paylaşımlı `showFuelAmountDialog()`; `PolishCurrencyInputFormatter` yapıştırma (`1.234,56`).
- `earnings_screen.dart`, `test/earnings_test.dart`.

## Haptik / direksiyon

- Baloncuk: kabul tek, red çift `HapticFeedback`; değer `_TapPop`.
- Direksiyon: `MediaKeyAccessibilityService.kt` — `createWaveform` accept/reject.
- Steering-wheel olayı overlay’de ikinci buzz yok (`haptic: false`).

## Ana ekran deneyimi

- `_initialLoadDone`: rate kartları + sayaçlar `AppShimmer` / `_RateCardSkeleton`; yükleme bitene kadar ± kapalı.
- `_init` / `_reloadAndSync` / `_checkForUpdate`: aşama bazlı `try/catch` + `loge`.

## Wakelock

- `main.dart` kök `Listener` → `HomeScreen.reportUserInteraction()` (Kazanç/Radar dahil).

## Kazanç UI

- `_HeroCard` / `_SummaryCard`: `_heroGlowDecoration` (home rate glow tarifi).
- Grafik / count-up: `_revealed` + `animateEntrance` — görünüm değişince animasyon tekrar oynamaz.

## Testler

- `flutter test` → 257+ (overlay sync, timezone, parsePlnAmount, widget shimmer).

## Yayın hizalaması

`pubspec.yaml` · `release/update.json` · GitHub `v5.0.2` · Gist — [`YAYIN_TR.md`](YAYIN_TR.md).
