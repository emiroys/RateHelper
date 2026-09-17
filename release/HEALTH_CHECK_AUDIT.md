# RateHelper Health Check — Read-Only Audit

No files were modified. `flutter analyze` is clean (0 issues), so everything below is behavioral rather than static-analysis findings.

**Scope:** 27 Dart files (~12.1k lines in `lib/`), 2 Kotlin files, the vendored `flutter_overlay_window` plugin, manifest and pubspec. Verified against `git log` for the five areas flagged as recently changed.

**Headline:** the engineering underneath this app is genuinely strong — the write queues, the two-isolate split, the native drag hand-off and the FIFO caps are all correct and I found no regressions in them. The real gap is a cluster of **four cross-isolate settings-propagation bugs** where a change on the home screen never reaches the running overlay, plus the fact that the app's *felt* quality lags its *built* quality at the two moments the driver experiences most: cold start and an overlay tap.

---

## PART 1 — BUGS & REGRESSIONS

### 1.1 Overlay gesture handling — clean, and better than I expected

There is **no gesture-arena ambiguity**, because there is no Flutter pan recognizer at all. The pill wraps its content in a bare `Listener` (`overlay_widget.dart:433-438`), which never enters the arena, and dragging is handled entirely natively by `OverlayService.onTouch` (`OverlayService.java:500-563`). The hand-off is done properly:

- `ACTION_DOWN` returns `false`, so Flutter still sees the press and a stationary tap can win (`:505-513`).
- Under a 20 dp slop the stream stays with Flutter; past slop, native synthesizes an `ACTION_CANCEL` through `view.onTouchEvent` *before* taking over, so `GestureBinding` releases the pointer instead of waiting for an UP that native is about to eat (`:486-498`, `:514-528`).
- `ACTION_UP` is consumed only when a drag actually happened (`finishTouch`, `:565-581`), so a tap after a micro-jitter still registers.
- The slop comment explicitly records why 20 dp beats the old 20-*physical*-pixel value (`:77-81`). That fix is real and still in place.

Orientation support didn't break this: the toggle closes and reopens the window rather than calling the unreliable `resizeOverlay` (`home_screen.dart:1043-1057`, `_reopenOverlayPreservingPosition:1065-1091`), and position is preserved across the cycle.

**One leftover:** `_trackedPointer`, `_pointerDownPos` and `_pointerIsDrag` (`overlay_widget.dart:110-112`) are computed by four handlers (`:350-388`) but feed nothing except `logd`. They're dead in release (`log.dart:12-15`). Not a bug, but they imply Flutter-side drag detection that doesn't exist, which will mislead the next person who touches this file.

**Missing:** zero `HapticFeedback` calls in the entire overlay file. See §5.1.

### 1.2 Future/async chain integrity

**The write queues are correct.** Both `ShiftCounterStore._enqueue` (`shift_counter_store.dart:107-118`) and `TapHistoryStore._enqueue` (`tap_history_store.dart:62-73`) re-point `_queue` at a `catchError`-wrapped future while returning the raw one to the caller. A thrown job is logged and cannot poison later links — this is the right pattern and it's applied consistently. `CrashLogger._chain` (`crash_logger.dart:115`) is the one exception: it chains without `catchError`, but every link's body is itself wrapped in `try/catch (_)` (`:170-183`), so it can't throw.

**The problem is on the UI side.** `_HomeScreenState._init` (`home_screen.dart:265-303`) is one long unguarded await chain:

```265:303:lib/home_screen.dart
  Future<void> _init() async {
    final prefsFuture = _getPrefs();
    final infoFuture = PackageInfo.fromPlatform();
    final prefs = await prefsFuture;
    // ...
    final info = await infoFuture;          // no try/catch
    // ...
    await _loadAndCheckReset();             // no catch, only try/finally inside
    unawaited(_drainPendingTaps());
    unawaited(_syncSteeringWheelState());
    unawaited(_refreshOverlayState());
  }
```

`PackageInfo.fromPlatform()` throwing — or any throw inside `_loadAndCheckReset` (`:547-626`, which has `try/finally` but no `catch`) — aborts everything after it. That means **the counters never load, the wakelock policy never applies, pending steering-wheel taps are never drained, and the overlay-active dot stays grey**, all because one unrelated platform call failed. The shift appears to have been wiped. This is precisely the "one failure kills all subsequent operations" pattern you asked me to look for, and it survives at the top of the call graph even though the storage layer below it is bulletproof.

Same shape, lower stakes: `_refreshOverlayState` (`:507-511`) and `_reloadAndSync` (`:474-489`) are fired via `unawaited` with unguarded `await FlutterOverlayWindow.isActive()` / `_kSysChannel.invokeMethod` inside, so a channel error becomes an unhandled zone error rather than a logged one.

### 1.3 State consistency across screens — four real bugs, one severe

This is where the audit found the most. `OverlaySync.notifyCountersChanged` is called with **full counter payloads** at four sites (`home_screen.dart:615`, `:636`, `:685`, `:765`) and with **no arguments** at exactly one (`:1059`, on overlay open). On the receiving end:

```147:160:lib/overlay_widget.dart
      _syncSub = FlutterOverlayWindow.overlayListener.listen((event) {
        if (OverlaySync.shouldReloadCounters(event)) {
          final counters = OverlaySync.countersFromEvent(event);
          if (counters != null) {
            _applyRemoteCounters(counters);   // counters ONLY
          } else {
            unawaited(_loadCounts());         // counters + settings
          }
        }
```

`_applyRemoteCounters` (`:226-239`) writes three ints and — critically — **early-returns when they're unchanged**. Only `_loadCounts` re-reads language, goal tier, auto-complete and orientation. So any home-screen setting change that sends a full payload, or sends nothing at all, leaves the running overlay stale:

| Changed on home | Site | Overlay effect |
|---|---|---|
| Auto-complete trips | `:833-837` (no notify at all) | **Overlay `+` stops bumping `completed`.** Trips silently uncounted for the rest of the shift. |
| Trip goal tier | `:628-642` (notifies with full counters → early-returns) | Accept-rate threshold colour keeps using the old tier; red/amber/green is wrong. |
| Language | `:932-940` (no notify at all) | Pill keeps `%100` (TR) vs `100%` (EN/PL) formatting from the previous language. |

All three clear only when the overlay is closed and reopened — i.e. "only on next full app restart", exactly the failure mode you described. Auto-complete is the severe one because it loses financial data rather than just looking wrong. The fix is small and uniform: either send `notifyCountersChanged()` with no arguments (which already routes to `_loadCounts`) after a settings write, or add a distinct `settings_changed` action.

**Fourth, smaller one:** `driverModeNotifier` (`earnings_models.dart:39-44`) is a global `ValueNotifier` that **nothing listens to** — there is no `ValueListenableBuilder` on it anywhere. Cross-screen driver-mode propagation is instead done by hand through `onModeChanged` callbacks calling `setState` (`home_screen.dart:1407-1412`, `earnings_screen.dart:1382-1388`) plus a re-read on resume. It works today, but the reactive plumbing exists and is unwired, which is how the next such change gets missed.

**Verified working:** counter taps propagate home→overlay via the debounced `_saveDataNow` (`:731-771`); overlay→home via the same channel plus `_applyStoredCounters` fallback (`:454-462`); fuel added from the home bottom bar is picked up by `EarningsScreen._load`'s `prefs.reload()` (`earnings_screen.dart:371-372`); and `_openEarnings` refreshes home on pop (`:1782-1785`).

**Minor:** the history sheet receives an immutable snapshot (`home_screen.dart:1098-1119`), so taps landing while it's open don't appear. And overlay taps arrive through `_applyOverlayCounters`, which doesn't call `_snapshotUndo` (`:436-452`), so an accidental overlay tap can't be undone from home even though the undo button is right there.

### 1.4 Locale-dependent numeric input — three of six parse sites are wrong

The main earnings form is correct. `PolishCurrencyInputFormatter` (`earnings_screen.dart:183-255`) normalizes `.` → `,` and groups thousands with **spaces**, and both readers strip spaces before swapping the comma:

```3666:3674:lib/earnings_screen.dart
  double _parse(TextEditingController c) {
    final t = c.text
        .trim()
        .replaceAll(' ', '')
        .replaceAll(',', '.');
```

`_validateField` (`:4428-4432`) and the JSON fallbacks (`earnings_models.dart:376`, `:659`) match. `home_screen.dart`'s quick-fuel dialog also strips spaces (`:1840`, `:1869`).

**But the three fuel-amount dialogs in `earnings_screen.dart` do not.** `_quickAddFuel` (`:829`, `:854`) and `_addReceiptInline` (`:3984`, `:4009`) both do only `.replaceAll(',', '.')`, and — worse — those `TextField`s have **no `inputFormatters` at all**. So:

- `4,5` → parses fine.
- `1 234,50` → becomes `1 234.50` → `tryParse` returns null → **the Add button does nothing, with no error shown.** The dialog just sits there.
- `abc` or an empty field → same silent no-op.

A Polish driver entering a four-figure tank on a shared car hits this. The three sites should reuse `_parse`'s normalization (and ideally `PolishCurrencyInputFormatter`, which is already in the same file).

**Related, lower severity:** `PolishCurrencyInputFormatter` replaces `.` with `,` *before* locating the decimal separator (`:195-198`), so a pasted `1.234,56` is read as `1,23`. Only reachable via paste.

### 1.5 Regression re-check on the four recently-changed areas

**Driver/car trip split — clean.** `driverTripCount` is the persisted field with `tripCount` kept as a read-only alias (`earnings_models.dart:434-438`); `carTripCount` derives correctly and collapses to the driver count in solo mode (`:448-451`); `copyWith` uses an `Object _sentinel` so an explicit `null` can clear the override (`:380`, `:506`, `:520-522`); and `fromJson` migrates legacy `tripCount` with the paired-mode limitation documented rather than silently wrong (`:618-628`). Lifetime trips use `driverTripCount` exclusively (`:794-800`).

**Settlement fee 4.3125% — clean and single-sourced.** `SETTLEMENT_FEE_RATE` (`:13`) is referenced in exactly three places: `settlementFee` (`:533`), `calculateBreakEven`'s denominator (`:147`), and the PDF column (`earnings_pdf_export.dart:230`). No duplicated literal anywhere in `lib/`. Both rates are pinned by tests (`test/earnings_test.dart:46-61`). `netProfit` composes from already-rounded parts so the breakdown card always sums exactly (`:538-544`).

**Design token migration — no state lost.** I checked every stateful widget that was restructured. `_HistorySheetState` still holds `_todayOnly`, `_tabController`, `_lastTabIndex` and pre-parsed taps, and its tab views are still wrapped in `_KeepAliveTabView` with `AutomaticKeepAliveClientMixin` (`home_screen.dart:2841-2878`, `:3477-3496`). `_EarningsScreenState` still holds `_viewMode`, `_selectedMonth`, `_selectedYear`, `_historyFilterMonth` and `_weekOffset`. Selected tabs and expanded cards survive.

**One genuine logic bug surfaced in the cancellation-budget calculator:**

```80:93:lib/home_screen.dart
int? maxAdditionalCancellations({
  required int completedTrips,
  required int currentCancellations,
  double ceiling = 5.0,
}) {
  if (completedTrips == 0) return 0;
```

With zero trips this returns `0`, and the caller renders that as the amber "you can afford 0 more cancellations" warning card (`:1557-1592`). So **every Monday at 04:00 Warsaw, right after the automatic reset, the driver opens a fresh week and is greeted by an amber warning that they have no cancellation budget left** — when in fact they have no data at all. `null` (which the caller already handles as "render nothing") is the correct return for an empty week.

**Also cosmetic but against your own spec:** the overlay rounds the accept rate to one decimal (`overlay_widget.dart:130-139`) while home shows two (`:1511-1513`). The same metric reads `%84,6` on the pill and `%84,62` on the card.

---

## PART 2 — BATTERY

### 2.1 Wakelock — all exit paths release, but the idle timer has a hole

Release is covered on `dispose` (`home_screen.dart:383`), `AppLifecycleState.paused` (`:403-404`), toggle-off (`:839-844`) and the 10-minute idle timer (`:426-428`). `detached`/`hidden` aren't handled, but `paused` always precedes them on Android. The recent overlay/gesture work didn't disturb any of this.

**The hole:** the idle timer is only reset by `_onUserInteraction`, which is wired to a `Listener` that wraps **the home screen's Scaffold only** (`:1309-1310`, `:431-434`). Push `EarningsScreen` or `RadarScreen` and nothing feeds the timer. So a driver filling in the weekly earnings form, or reading the radar at a rank, has the screen go dark after 10 minutes *of active use* with "keep screen on" enabled. The timer needs to be fed from a shared root `Listener` (or the sub-screens need to ping it on interaction).

### 2.2 Overlay isolate at rest — genuinely zero-cost

Verified idle. No `AnimationController`, no `Timer.periodic`, no `Ticker` anywhere in `overlay_widget.dart`. The only timer is the 300 ms post-tap persist debounce (`:321-326`). Both leaf widgets are `RepaintBoundary`-wrapped stateless (`:493`, `:537`), the shadow is a static `Material(elevation: 8)` (`:440-442`), and the ripple factory only animates on touch. A stationary pill with no interaction produces no frames. **Don't touch this.**

### 2.3 No new timers or polling from the recent features

- **Orientation toggle:** close + reopen, no timer (`:1043-1091`).
- **Cancellation budget:** a bounded pure loop (`:88-92`).
- **Driver-mode dialog:** plain `showDialog`, no listeners retained.
- **Native tray-snap `Timer`** in `OverlayService.TrayAnimationTimerTask` (`:595-638`) is dead code for this app, because `finishTouch` gates it on `positionGravity != "none"` (`:570`) and the app passes `PositionGravity.none` (`home_screen.dart:1054`). Correct call — that timer fires every 25 ms during a snap.
- `EventService` has no polling; it's a 1-hour in-memory cache with in-flight de-duplication (`event_service.dart:16-42`).

One item to be aware of rather than fix for battery: `_ChartBar.initState` schedules an uncancellable `Future.delayed(30 × index)` per bar (`earnings_screen.dart:2366-2369`), so up to 12 pending timers per chart build. Battery impact is negligible; the animation-replay consequence is in §4.2.

### 2.4 `MediaKeyAccessibilityService` — still purely event-driven

Re-confirmed after the freeze-bug fix. `onAccessibilityEvent` is an empty body (`MediaKeyAccessibilityService.kt:88`). `onKeyEvent` does a **cheap int comparison first** and returns before touching prefs or any other work for the volume/power events that dominate the stream (`:98-103`) — that ordering matters and it's right. Prefs are read once on `onServiceConnected` on a background thread and kept fresh by a change listener rather than re-read per event (`:69-77`), with `steeringWheelEnabled` marked `@Volatile`. Only two `postDelayed` handlers exist (800 ms long-press arm, 1200 ms overlay-ack fallback) and both are removed on their resolution paths (`:124`, `:186`, `:191`). `onDestroy` clears all callbacks and unregisters the listener (`:79-85`).

The engine-liveness check added alongside the freeze fix is the right fix, not a workaround: `liveOverlayChannel()` refuses to hand back an engine whose `dartExecutor.isExecutingDart` is false, because `OverlayService` flips `isRunning` and destroys the engine in separate steps (`:197-219`). Combined with the `AtomicBoolean` exactly-once settle in `handleLongPress` (`:176-195`), a tap is never double-counted and never lost. **Don't touch this either.**

---

## PART 3 — RAM

### 3.1 Full disposal audit — clean across all five screens

I checked every controller, subscription and timer in the app. There are **no `FocusNode`s anywhere**, and everything else is disposed:

| File | Resource | Disposal |
|---|---|---|
| `home_screen.dart` | `_overlayListenerSub`, `_saveDebounce`, `_wakelockIdleTimer`, observer, static channel handler | `dispose():376-387` — including `setMethodCallHandler(null)`, which is the easy one to miss |
| `home_screen.dart` | `_showEditCounterDialog` controller | both paths (`:923`, `:927`) |
| `home_screen.dart` | `_quickAddFuelReceipt` ctrl | `finally:1889` |
| `home_screen.dart` | `_HistorySheetState._tabController` | `:2882` |
| `earnings_screen.dart` | `_scrollController` | `:347` |
| `earnings_screen.dart` | 6 form controllers + `_fuelReceiptsNotifier` + 2 listeners | `:3683-3693` — listeners removed before disposal |
| `earnings_screen.dart` | 4 dialog controllers | `finally` at `:651`, `:873`, `:1174`, `:4028` |
| `radar_screen.dart` | `_ShimmerSkeletonCardState._controller` (a repeating one) | `:429` |
| `overlay_widget.dart` | `_syncSub`, `_persistTimer` | `:215-224`, with a final flush of pending taps first |
| `onboarding_screen.dart` | observer | `:128-131` (no controllers in this file) |

The `finally`-based dialog-controller disposal is the correct pattern and it's applied uniformly.

### 3.2 New `AppWidgets` — no leaks

`AppTapTarget`, `AppEmptyState`, `AppPrimaryButton`, `AppSecondaryButton`, `AppIconActionButton` and `AppDangerButton` (`app_widgets.dart:13-378`) are **all `StatelessWidget`**. None constructs an `AnimationController`, `Ticker` or `ValueNotifier`. The only implicit animation controllers are inside the framework's own `InkWell` and `ElevatedButton`, whose states manage their own lifecycles. No stateless-looking wrapper hiding a controller. Clean.

### 3.3 FIFO caps — all still enforced, and structurally immune to the schema change

This is worth spelling out because your concern was specifically that a field rename could break a cap check. None of the four caps pattern-matches a field name:

- **Earnings 104 weeks:** `encodeEarnings` sorts by `weekStart` and takes the trailing slice (`earnings_models.dart:782-787`). Keyed on a date, not a changed field.
- **Fuel receipts 100/week:** `capFuelReceipts` is called **inside the `WeekEarning` constructor's initializer list** (`:405-409`), so *every* construction path — including every `copyWith` — re-caps. This is the strongest of the four.
- **Tap history 500:** `_compactIfNeeded` trims the file past `500 + 100` slack, and `_readAllNow` trims the returned window to 500 regardless (`tap_history_store.dart:110-112`, `:188-195`). Readers can never see more than the cap even mid-slack.
- **Weekly archive 104:** trimmed on append in `_performReset` (`home_screen.dart:666-669`).

One related detail that's handled correctly: the lifetime-trip odometer is a separate monotonic prefs int (`kLifetimeTripsKey`) that FIFO eviction never decrements (`earnings_models.dart:690-693`), so the free-week milestone can't regress when a 2-year-old week is dropped.

`_rowKeys` (the `GlobalKey` map for scroll-to-row) is also pruned against live IDs on every data change (`earnings_screen.dart:441-443`) rather than growing forever.

### 3.4 Two-isolate resource loading — deliberately minimal, one avoidable cost

`registerOverlayPlugins` (`OverlayService.java:407-423`) whitelists exactly four plugins, with a comment explaining why `automaticallyRegisterPlugins=false` was necessary. `url_launcher`, `share_plus`, `pdf`, `wakelock_plus` and `package_info_plus` never load into the overlay isolate. That's the right call and it's the biggest win available here.

Fonts are per-isolate `FontCollection`s, but they fault in lazily, and the overlay renders exactly one DM Sans weight (w900, via `T.rateFor` → `T.rateEmerald`/`rateCrimson`/`rateAmber`) plus MaterialIcons for the two `Icons.*_rounded` glyphs. Of the 10 declared font files (`pubspec.yaml:82-106`), the overlay touches one. `assets/logo.png` is only referenced from home (`home_screen.dart:1341`), and it's loaded with `cacheWidth`/`cacheHeight` scaled to the device pixel ratio (`:1307-1346`) — good.

**The one avoidable cost:** `overlayMain` runs `CrashLogger.install()` (`main.dart:76`), which does a `getApplicationDocumentsDirectory()` platform call, and then `_loadCountsOnStartup` does `SharedPreferences.getInstance()` **plus `prefs.reload()`** (`overlay_widget.dart:183-189`). That reload parses the whole ~47 KB prefs XML into the overlay isolate on every pill open, purely to read four scalars (language, goal tier, auto-complete, orientation). Since `ShiftCounterStore` already exists precisely to keep counters out of prefs, the same treatment for those four settings would remove prefs from the overlay isolate entirely.

---

## PART 4 — PERFORMANCE / SMOOTHNESS

### 4.1 Rebuild scope post-migration — the tokens did **not** widen anything

I specifically looked for the failure mode you described. `AppColors`, `AppSpacing`, `AppRadius` and `AppTextStyles` are all `abstract final class` holders of compile-time `const`s (`app_colors.dart:8`, `app_spacing.dart:6`/`:32`, `app_text_styles.dart:16`). The two shared non-const objects — `_cardBorder` and `_cardRadius` — are plain top-level/static `final`s (`earnings_screen.dart:25-26`, `home_screen.dart:132-136`), not `InheritedWidget`s, not `Theme` extensions. No token participates in the element tree, so none can trigger a dependency-driven rebuild. The migration is clean on this axis.

The rebuild problems that do exist are pre-existing `setState` breadth:

- **Home:** the counters are correctly isolated behind four `ValueNotifier`s merged into `_ratesListenable` (`:143-154`), with each `_CounterRow` wrapped in a `RepaintBoundary` + `ValueListenableBuilder` (`:2601-2616`). That part is well done. But `setState` for `_autoCompleteTrips`, `_keepScreenOn`, `_pillOrientation`, `_overlayToggleBusy` or a driver-mode change rebuilds the entire ~700-line `build` including all four counter rows, the footer, `UpdateCheckTile` and the bottom bar. Only the settings block actually changed.
- **Earnings:** every `setState` re-runs `_buildSlivers()` from scratch (`:1364-1454`), rebuilding `_FreeWeekProgressCard`, `_DriverNameRow`, `_ViewToggle`, the chart and the whole history list. `_selectWeek` (`:354-368`) and every chart-bar tap pay this. Weekly history rows are `RepaintBoundary`-wrapped (`:1620`); the monthly and yearly lists are not (`:1713-1724`, `:1783-1795`).
- **History sheet:** `_filteredTaps` re-filters up to 500 entries on every build of the tap-log tab (`:2886-2895`), and `_tapTimeLabel` calls `DateTime.now()` once per row per build (`:2897-2911`). Taps of the Today/All chips pay both.

### 4.2 Entrance animations **do** re-fire on view-mode switches — confirmed

Both animated hero elements are keyed to widget state that is destroyed and recreated when `_viewMode` changes:

```2360:2377:lib/earnings_screen.dart
class _ChartBarState extends State<_ChartBar> {
  double _target = 0;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 30 * widget.index), () {
      if (mounted) setState(() => _target = widget.heightFactor);
    });
  }
```

Switching weekly → monthly → weekly replays the full staggered bar cascade from zero height, and `_CountUp` (`:2043-2058`) replays its 0 → value roll, **every time**, including when returning to a view the driver has already seen seconds earlier. On the monthly/yearly charts with 12 bars that's a 360 ms cascade per toggle.

(Note that `_CountUp` behaves *correctly* for genuine data changes — `TweenAnimationBuilder` rewrites `tween.begin` to the current animated value on update, so changing `_weekOffset` lerps from the previous number rather than from zero. The bug is purely fresh-state construction.)

The fix is to move the "has this already animated" decision up to `_EarningsScreenState` — e.g. a `Set<String>` of animated bar keys, or a single screen-owned `AnimationController` driving the cascade — so the entrance is tied to data identity rather than to element lifetime.

### 4.3 Frame-timing on the three critical paths

**Overlay drag — the best-executed path in the app.** The window moves via `windowManager.updateViewLayout` on the native UI thread (`OverlayService.java:530-542`); Flutter produces **no frames at all** during a drag because its pointer was cancelled at drag-start. You cannot do better than this for the app's most-used interaction. Don't touch it.

**Earnings form typing — correctly scoped.** One merged `_previewListenable` (`:3638-3647`) drives only three preview widgets (`_breakEvenReference`, `_computedRentalDisplay`, the warnings block), and the comment records that typing used to rebuild the whole form. The error-flag listener is separate and targeted (`_maybeClearTimeError:3654-3661`). The per-keystroke throwaway `WeekEarning` construction (`:3845-3862`) allocates a list and runs `capFuelReceipts`, which is trivial at ≤100 receipts.

**Chart interaction** costs a full sliver-list rebuild plus `Scrollable.ensureVisible` — acceptable at this data volume, and it'd improve for free if §4.1's earnings rebuild scope were narrowed.

### 4.4 Cold start — one large, easy win left

```10:31:lib/main.dart
import 'package:timezone/data/latest_all.dart' as tz;
// ...
  await Future.wait<void>([
    Future<void>(() => tz.initializeTimeZones()).catchError((Object e) {}),
    CrashLogger.install().catchError((Object e) {}),
  ]);

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
```

Two things:

1. **`data/latest_all.dart` is the complete IANA tz database** — every zone, all historical transitions — parsed synchronously before `runApp`. The app resolves exactly one zone, `Europe/Warsaw` (`home_screen.dart:118-125`), and only to compute the Monday-04:00 reset boundary. Switching to `timezone/data/latest_10y.dart`, or deferring initialization until the first `_nowWarsaw()` call, removes the single largest blocking item from boot.
2. `SharedPreferences.getInstance()` is awaited **after** the `Future.wait` even though it's independent of both members. It belongs inside the same `Future.wait`.

The parallelization that *is* there is done right: `_init` kicks off `_getPrefs()` and `PackageInfo.fromPlatform()` together before awaiting either (`:266-268`). `overlayMain` has nothing deferrable left — it needs prefs and path_provider immediately to render correct counters.

---

## PART 5 — PREMIUM POLISH GAPS

### 5.1 Micro-interactions — where the app still feels instant rather than alive

**1. The overlay counter change — the single biggest gap in the app.** Tap `+` and the percentage swaps to a new string. No scale pop, no colour pulse, and **no haptic whatsoever**: there are zero `HapticFeedback` calls in `overlay_widget.dart`, while home's `_CounterRow` has four (`home_screen.dart:2629-2675`). The most-repeated interaction of a 10-hour shift is the only one in the app with no tactile or motion confirmation. A driver glancing away cannot tell whether the tap landed.

**2. Home's two rate cards.** `_buildRateCard` (`:2147-2198`) snaps from one percentage to the next on every tap. These are the hero numbers of the main screen, and a count-up/roll is the highest-value animation available — made trivial by the fact that `_CountUp` already exists in `earnings_screen.dart:2043` and just needs hoisting into a shared file.

**3. The free-week achievement.** Crossing 2000 lifetime trips makes the gold badge simply *appear* (`_FreeWeekProgressCard:4659-4689`) and the `LinearProgressIndicator` jump to its new `value` (`:4650-4658`). This is the app's one genuine reward moment and it has no celebration — an animated bar fill plus a badge scale-in would cost very little.

**4. Threshold crossings.** When the accept rate drops under the goal, the card's colour and glow just change (`:2158-2172`). A one-shot pulse on the crimson transition specifically would make the warning register peripherally.

**5. Weekly reset.** `_performReset` (`:647-687`) drops four hero numbers to zero with no transition at all — it reads as a glitch rather than as a deliberate fresh start.

**6. Undo availability.** The app-bar icon flips opacity instantly via `ValueListenableBuilder` (`:1317-1326`); a short fade/scale would read as intentional.

### 5.2 Empty / loading / error states

**Radar is the gold standard and should be the template.** It has a real shimmer skeleton with a repeating fade (`radar_screen.dart:363-372`, `:403-490`), a proper `AppEmptyState` with a retry action (`:375-386`), and a *separate* error state with crimson accent and reload (`:388-400`). This is finished work.

**Earnings is good on empties, weak on loading.** `_EmptyWeekCard` (`:2923`), `_EmptyPanel` (`:2975`), `_TrendPlaceholder` for <2 weeks (`:3006`), and a full empty state with a CTA inside the receipts section (`:4110-4127`) — all solid. But the load state is a bare centred spinner (`:1063-1064`), inconsistent with the skeleton radar already has for the same situation.

**Home has no loading state at all — this is the most visible unfinished moment in the app.** On every cold start, `build` runs before `_loadAndCheckReset` resolves, so the driver sees four counters reading `0` and both rate cards reading `%100,00`, which then snap to the real values. The very first thing seen at the start of every shift looks momentarily like the week's data was lost. A skeleton, or holding the hero numbers dimmed until the first load completes, fixes the app's worst first impression.

Everything else is covered: both history tabs (`:3167-3172`, `:3241-3248`), the crash log (`:1163-1169`), and PDF-export-with-no-data (`:1267-1273`).

### 5.3 Depth and hierarchy — the app isn't too flat, it's *inconsistently* deep

This is worth reframing. A selective-elevation vocabulary already exists and is well-judged wherever it's applied:

- Accept-rate card: coloured 1.2 px border + 20 px coloured shadow via `hasGlow` (`:2158-2172`)
- `_RecordsCard`: gold shadow with negative spread (`earnings_screen.dart:2754-2762`)
- `_ViewToggle` selected segment: emerald glow with offset (`:2500-2509`)
- Bottom action bar: `elevation: 12` (`home_screen.dart:1712-1716`)
- Radar header: diagonal two-tone gradient (`radar_screen.dart:139-147`)
- Overlay pill: `elevation: 8`

So the recipe you're asking about is already written. It simply isn't applied to the two most important numbers in the app: **`_HeroCard`** (the PLN/h hourly rate — the entire point of the earnings screen, `earnings_screen.dart:2060-2127`) and **`_SummaryCard`** (total net profit, `:2605-2703`) are both plain flat cards. Applying the existing `hasGlow` treatment to exactly those two — one hero per screen, using the same colour the number is already signalling with — adds the depth you're after without inventing a new language or diluting the flat discipline elsewhere.

Worth a deliberate decision too: the cancellation-rate card sits flat immediately beside the glowing accept-rate card (`:1509-1528`). If that asymmetry is intentional hierarchy, fine; right now it reads as an oversight.

### 5.4 Screen and sheet transitions — 100% default, nothing branded

Every navigation in the app uses stock Flutter animations. Six `MaterialPageRoute` pushes (`home_screen.dart:1399-1403`, `:1772-1775`, `earnings_screen.dart:694-702`), six default `showModalBottomSheet` calls (`home_screen.dart:943`, `:1106`, `:1138`, `:2067`, `earnings_screen.dart:1181`, `:1305`), and every dialog on the default fade-scale.

The two highest-leverage places to spend a custom transition:

- **home → earnings**, the most-travelled route in the app. A Material shared-axis (horizontal) or fade-through would immediately read as crafted.
- **the earnings form push** (`earnings_screen.dart:694-702`). It's a modal data-entry route currently arriving as a lateral page slide; a bottom-up slide would match its actual nature and reinforce that the week list stays underneath.

### 5.5 The overlay pill at rest — functional prototype, not finished product

It's clean and legible — 276×80 dp stadium, `#E6161616`, `elevation: 8`, two 68 dp buttons and a 48 px w900 percentage — but at rest it reads as a debug HUD. Concretely:

1. **No drag affordance.** Nothing indicates the pill can be moved, and native slop is 20 dp so a tentative nudge does nothing. Two or three 2 px dots, or a 12×3 grip bar on the stadium cap, would teach it silently.
2. **`%100` at 0/0 is ambiguous.** `_formatAcceptRate` returns a hard-coded `100` when there are no requests yet (`:130-133`), which is indistinguishable from a genuinely perfect rate. A dimmed state, an em dash, or a distinct "no data" treatment would remove the doubt.
3. **No reference to the active goal.** Colour is the only signal, so the driver can see *that* they're in trouble but not *how far* from the threshold. An 11 px eyebrow (`80%` target) or a 2 px progress hairline along the bottom of the stadium would carry that without adding height.
4. **A flat uniform hairline border** (`#33FFFFFF`, `:445`). A top-lit gradient stroke — brighter at the top edge, fading to near-nothing at the bottom — is the single change that would most make this read as glass rather than as a grey rounded rectangle.
5. **No idle state.** After a few minutes without interaction the pill could ease to ~70% opacity and restore on touch. It looks intentional, and on an S24 Ultra AMOLED that sits in the same screen position for a 10-hour shift it also mitigates burn-in.
6. **Buttons look identical at rest and under the finger** apart from the ink ripple. A subtle border-brightness shift on press would make the 68 dp targets feel mechanical.

### 5.6 Sound / haptic refinement — the strongest premium opportunity in the list

Current state: 18 `HapticFeedback` calls total, all generic system constants — `selectionClick`, `lightImpact`, `mediumImpact`, and one `heavyImpact` on a failed save (`earnings_screen.dart:3713`). Distribution: 12 in `earnings_screen.dart`, 4 in `home_screen.dart`, 2 in `onboarding_screen.dart`, and **0 in the overlay, 0 in radar, 0 in the update dialog**.

The one non-generic pattern already in the codebase is native: a 150 ms one-shot `VibrationEffect` on a steering-wheel long-press (`MediaKeyAccessibilityService.kt:240-258`).

A branded signature is genuinely achievable and genuinely useful here, not decorative. Because the app already owns a native vibration path, `VibrationEffect.createWaveform` gives arbitrary rhythms, so:

- **Accept:** one crisp short pulse.
- **Reject:** a distinct double-pulse.

That lets the driver confirm **which** counter moved by feel alone, eyes on the road — which is a safety property, and it's the same distinction the steering-wheel long-press currently blurs by using one identical buzz for both. Extending it: a rising two-pulse for the free-week achievement, and a soft triple for the weekly reset. This is the highest-value item in Part 5 because it's the only one that makes the app measurably safer to use rather than just nicer to look at.

---

## PART 6 — SYNTHESIS

### 6.1 Findings table

| # | Part | File:Line | Sev | Description | Impact | Recommended fix (not applied) |
|---|---|---|---|---|---|---|
| 1 | 1.3 | `home_screen.dart:833-837` | **High** | `_setAutoCompleteTrips` never notifies the overlay | Overlay `+` stops incrementing `completed` for the rest of the shift; trips silently uncounted | Call `notifyCountersChanged()` with **no args** after the prefs write — it already routes to `_loadCounts`, which re-reads settings |
| 2 | 1.3 | `home_screen.dart:628-642` + `overlay_widget.dart:226-239` | **High** | `_setTripGoal` sends a full counter payload, so `_applyRemoteCounters` early-returns on unchanged values and never re-reads the tier | Pill's red/amber/green threshold stays on the old goal until reopen | Same as #1, or add a distinct `settings_changed` action to `OverlaySync` |
| 3 | 1.3 | `home_screen.dart:932-940` | Med | `_setLanguage` never notifies the overlay | Pill keeps the previous language's `%` placement | Same as #1 |
| 4 | 1.5 | `home_screen.dart:80-93` → `:1557-1592` | Med | `maxAdditionalCancellations` returns `0` (not `null`) for a zero-trip week | Every post-reset Monday opens with a false amber "0 cancellations left" warning | Return `null` for `completedTrips == 0`; caller already renders nothing for `null` |
| 5 | 1.4 | `earnings_screen.dart:829`, `:854`, `:3984`, `:4009` | Med | Three fuel dialogs parse with `replaceAll(',', '.')` only, and their `TextField`s have no `inputFormatters` | `1 234,50` → silent no-op with no error; garbage input also silently ignored | Reuse `_parse`'s normalization and attach `PolishCurrencyInputFormatter` (both already in the file) |
| 6 | 1.2 | `home_screen.dart:265-303`, `:547-626` | Med | `_init` is one unguarded await chain; `_loadAndCheckReset` has `try/finally` with no `catch` | A single platform failure leaves counters at 0, wakelock unapplied, pending taps undrained, overlay dot stale | Wrap each stage in its own `try/catch` + `loge`, so later stages always run |
| 7 | 2.1 | `home_screen.dart:426-434`, `:1309-1310` | Med | Wakelock idle timer is only fed by home's `Listener` | "Keep screen on" dies after 10 min of *active* use on earnings/radar | Hoist `_onUserInteraction` to a root `Listener`, or expose a static ping the sub-screens call |
| 8 | 4.4 | `main.dart:10`, `:29-37` | Med | Full IANA tz DB (`latest_all`) parsed before `runApp`; prefs load serialized after it | Longest single blocking item in cold start, for one timezone | Use `data/latest_10y.dart` or defer to first `_nowWarsaw()`; move `getInstance()` into the `Future.wait` |
| 9 | 5.2 | `home_screen.dart:1306+` | Med | Home has no loading state; renders `0` / `%100,00` pre-load | First thing seen every shift looks like data loss | Skeleton or dimmed heroes until `_loadAndCheckReset` resolves — mirror `radar_screen.dart:403-490` |
| 10 | 5.1 / 5.6 | `overlay_widget.dart:499-508` (whole file) | Med | Zero haptics and zero motion in the overlay | Most-used interaction in the app gives no confirmation | Distinct haptic per button (see #11) + a small scale/colour pop on the value |
| 11 | 5.6 | `MediaKeyAccessibilityService.kt:240-258` | Med | Single identical 150 ms buzz for both accept and reject | Driver can't tell by feel which counter a steering-wheel press moved | `VibrationEffect.createWaveform`: single pulse = accept, double = reject. Mirror the same rhythms via `HapticFeedback` in the overlay |
| 12 | 4.2 | `earnings_screen.dart:2360-2377`, `:2043-2058` | Med | Bar cascade and count-up replay on every view-mode switch, incl. returning to a seen view | Animations read as reloads; 360 ms cascade per toggle | Track animated identity on `_EarningsScreenState` (a `Set<String>`) or drive from one screen-owned controller |
| 13 | 5.3 | `earnings_screen.dart:2060-2127`, `:2605-2703` | Med | The two most important numbers (PLN/h, net profit) are the only heroes with no elevation | App's key figures carry less visual weight than a month chip | Apply the existing `hasGlow` recipe from `home_screen.dart:2158-2172` to exactly these two |
| 14 | 5.4 | all `MaterialPageRoute` / `showModalBottomSheet` sites | Med | Every transition is stock Flutter | Nothing about navigation feels authored | Shared-axis for home→earnings; bottom-up slide for the earnings form route |
| 15 | 5.5 | `overlay_widget.dart:390-474` | Med | Pill at rest has no drag affordance, no goal reference, ambiguous `%100` at 0/0, flat uniform border, no idle dim | The most-seen surface reads as a prototype | See §5.5 items 1-6; the gradient stroke and the grip dots are the cheapest high-impact pair |
| 16 | 4.1 | `home_screen.dart:1306+`, `earnings_screen.dart:1364-1454` | Low | Small `setState`s rebuild entire screens (counters are correctly isolated; settings blocks are not) | Avoidable work on toggles and chart taps | Extract settings rows into their own stateful widgets; split `_buildSlivers` behind `ValueListenableBuilder`s |
| 17 | 1.1 | `overlay_widget.dart:110-112`, `:350-388` | Low | `_trackedPointer` / `_pointerDownPos` / `_pointerIsDrag` only feed release-stripped `logd` | Implies Flutter-side drag detection that doesn't exist; misleads future edits | Delete, or add a comment that tap suppression is entirely native |
| 18 | 1.5 | `overlay_widget.dart:130-139` vs `home_screen.dart:1511-1513` | Low | Overlay shows 1 dp, home shows 2 dp for the same metric | `%84,6` vs `%84,62`; also contravenes the project's own 2-dp rule | Single shared formatter |
| 19 | 1.4 | `earnings_screen.dart:195-198` | Low | Formatter maps `.`→`,` before locating the separator | Pasted `1.234,56` becomes `1,23` | Detect the separator before normalizing |
| 20 | 3.4 | `overlay_widget.dart:183-189` | Low | `prefs.reload()` parses the full ~47 KB prefs XML in the overlay isolate on every open | Delays first correct pill paint | Move the 4 overlay-relevant settings to a small dedicated file, as was done for counters |
| 21 | 1.3 | `home_screen.dart:1098-1119` | Low | History sheet is an immutable snapshot | Taps landing while it's open don't appear | Re-read on tab focus, or pass the store and listen |
| 22 | 1.3 | `earnings_models.dart:39-44` | Low | `driverModeNotifier` has no listeners anywhere | Reactive plumbing exists unwired; next cross-screen change gets missed the same way #1-3 did | Wire home + earnings to it via `ValueListenableBuilder`, drop the manual callbacks |
| 23 | 1.3 | `home_screen.dart:436-452` | Low | `_applyOverlayCounters` doesn't `_snapshotUndo` | Accidental overlay tap can't be undone from home | Snapshot before applying remote counters |
| 24 | 5.2 | `earnings_screen.dart:1063-1064` | Low | Bare centred spinner where radar has a skeleton | Inconsistent load polish between two sibling screens | Reuse `_ShimmerSkeletonCard` |
| 25 | 1.2 | `home_screen.dart:474-489`, `:507-511` | Low | `unawaited` platform calls with no internal `try/catch` | Channel errors become unhandled zone errors | Wrap in `try/catch` + `loge` |
| 26 | 4.1 | `home_screen.dart:2886-2911` | Low | `_filteredTaps` re-filters ≤500 entries per build; `_tapTimeLabel` calls `DateTime.now()` per row per build | Avoidable work on filter-chip taps | Memoize per filter state; hoist `now` out of the row builder |

### 6.2 Top 10 by impact × effort

1. **Overlay settings propagation (#1, #2, #3).** One shared fix — send an argument-less `notifyCountersChanged()` after settings writes — closes all three, and #1 is the only bug in this audit that silently loses the driver's data. Highest impact, lowest effort in the entire list.
2. **Zero-trip cancellation budget returns `0` instead of `null` (#4).** A one-line change that removes a false alarm the driver sees at the start of every single week.
3. **Full IANA timezone database at boot (#8).** A one-line import swap for the largest measurable cold-start win available.
4. **Fuel-dialog decimal parsing (#5).** Three call sites, reusing a normalizer and a formatter that already exist twenty lines away. Turns a silently dead button into a working one for a Polish driver.
5. **Overlay haptics + branded accept/reject rhythm (#10, #11).** Moderate effort, but it's the only item here that makes the app *safer* — eyes-free confirmation of which counter moved — and it's the clearest "premium, not just consistent" signal.
6. **Home loading state (#9).** The template already exists in `radar_screen.dart`. Fixes the app's worst first impression on every cold start.
7. **Selective elevation on the two earnings heroes (#13).** Copy an existing recipe to two widgets. Highest visual return per line changed in this report.
8. **Wakelock idle-timer feed (#7).** Small plumbing change; removes a "the screen went dark while I was typing" bug that's invisible in testing and infuriating in a car.
9. **`_init` error isolation (#6).** Medium effort, prevents a whole class of "my week disappeared" reports from a single unrelated platform hiccup.
10. **Chart/count-up animation identity (#12).** Moderate effort; converts the app's nicest animations from feeling like reloads into feeling like reveals.

Below the line but cheap if you're already in the file: #17, #18, #24.

### 6.3 What's already premium — do not touch

These are genuinely well-executed, and several are better than what most production apps ship:

- **The native drag hand-off.** `OverlayService.onTouch` + `cancelFlutterPointer` (`OverlayService.java:486-581`) is the correct architecture for the app's most-used interaction, and the 20 dp slop and consume-UP-only-after-drag details are both right. Zero Flutter frames during a drag.
- **Both write queues.** `_enqueue`'s "recover the queue, return the raw future" pattern (`shift_counter_store.dart:107-118`, `tap_history_store.dart:62-73`) is exactly right and consistently applied.
- **`ShiftCounterStore`'s atomic write.** `writeAsString` to `.tmp` then `rename(2)`, with a documented Windows fallback and a comment explaining why delete-then-write would lose a shift to a Samsung battery-manager kill (`:187-211`). This is the kind of detail that only gets written after someone lost data once.
- **`applyDelta` as a single queued read-modify-write**, with the comment explaining why `read()` then `write()` would lose a tap to an interleaved overlay `merge()` (`:146-166`). Correct and correctly justified.
- **`_saveDataNow`'s claim-deltas-before-awaiting** pattern (`home_screen.dart:731-771`) — taps landing mid-write accumulate against a fresh baseline instead of being replayed.
- **`MediaKeyAccessibilityService`'s event-driven discipline** and the `isExecutingDart` liveness check + `AtomicBoolean` exactly-once settle (`:176-219`). Exactly-once tap delivery across an isolate that may be half-destroyed is a hard problem, solved properly.
- **The overlay plugin whitelist.** `registerOverlayPlugins` (`OverlayService.java:407-423`) keeping url_launcher/share_plus/pdf/wakelock out of the second isolate is the single biggest RAM win in the app.
- **The overlay's idle cost.** Zero timers, zero animations, `RepaintBoundary` on both leaves. Nothing to improve.
- **All four FIFO caps**, particularly `capFuelReceipts` being enforced in the constructor initializer so no `copyWith` path can bypass it.
- **The monotonic lifetime-trip odometer** surviving FIFO eviction (`earnings_models.dart:690-693`).
- **`didHaveMemoryPressure`** dropping the event cache and both image caches, with the comment explaining that a cold start costs more battery than a re-fetch (`home_screen.dart:464-472`). Almost nobody implements this.
- **`CrashLogger`'s** internal-storage-only choice with the reasoning about world-readable OEM forks (`:56-60`), the 5-writes/sec rate limit with a dropped-count summary, and the 64 KB FIFO bound.
- **`loge`'s release policy** — crash file only, never logcat, because a `FormatException` from `jsonDecode` embeds raw financial JSON (`earnings_models.dart:768-774`).
- **The corrupt-earnings quarantine** — preserving the raw blob under a backup key instead of letting the next persist overwrite it (`:753-776`).
- **Radar's three-state handling** (skeleton / empty / error with retry). Use it as the template for #9 and #24.
- **The earnings form's `_previewListenable`** scoping typing rebuilds to three widgets.
- **`formatPln` returning an em dash for non-finite values** (`:720-721`) so NaN can never leak into the UI.
- **The comment culture throughout.** Nearly every non-obvious decision carries a comment explaining the failure it prevents. That is why this audit could verify prior fixes instead of guessing at them, and it's worth protecting.

### 6.4 Honest assessment

RateHelper is a **solid utility with premium engineering and a prototype's sense of feel** — and unusually, the engineering is the finished half. The storage layer, the two-isolate split, the native drag hand-off, the exactly-once tap delivery and the FIFO discipline are all at a standard I'd expect from a shipped commercial product, and `flutter analyze` is clean at ~12k lines. What hasn't caught up is everything the driver actually perceives. The single biggest gap between where it is and "genuinely premium" is that **the app never acknowledges the driver's input**: the pill's percentage swaps with no haptic, no motion and no sound after the thousandth tap of a shift; the home screen opens every morning showing zeros and `%100,00` before snapping to real data; every screen transition is stock; and the two most important numbers in the app are the only heroes with no visual weight. Notably, none of that requires new architecture — the count-up widget, the elevation recipe, the loading skeleton and the native vibration path all already exist in this codebase, just not applied where they'd matter most. Close the four cross-isolate propagation bugs so the app is *correct*, then spend the polish budget on feedback-on-input rather than anywhere else, and the gap closes fast.
