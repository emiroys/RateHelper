import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:rate_helper/fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'display_mode.dart';
import 'format_rate.dart';
import 'instruments/gauge_painter.dart';
import 'instruments/plate.dart';
import 'l10n.dart';
import 'log.dart';

const _kCardColor = AppColors.card;
const _kEmerald = AppColors.emerald;
const _kAmber = AppColors.amber;
const _kSysChannel = MethodChannel('com.ratehelper.app/system');

enum DeviceBrand { samsung, xiaomi, huawei, oneplus, other }

extension on DeviceBrand {
  String get label {
    switch (this) {
      case DeviceBrand.samsung:
        return S.brandSamsung;
      case DeviceBrand.xiaomi:
        return S.brandXiaomi;
      case DeviceBrand.huawei:
        return S.brandHuawei;
      case DeviceBrand.oneplus:
        return S.brandOnePlus;
      case DeviceBrand.other:
        return S.brandOther;
    }
  }

  String get steps {
    switch (this) {
      case DeviceBrand.samsung:
        return S.samsungSteps;
      case DeviceBrand.xiaomi:
        return S.xiaomiSteps;
      case DeviceBrand.huawei:
        return S.huaweiSteps;
      case DeviceBrand.oneplus:
        return S.onePlusSteps;
      case DeviceBrand.other:
        return S.otherSteps;
    }
  }
}

DeviceBrand _brandFromManufacturer(String? raw) {
  final m = (raw ?? '').toLowerCase();
  if (m.contains('samsung')) return DeviceBrand.samsung;
  if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
    return DeviceBrand.xiaomi;
  }
  if (m.contains('huawei') || m.contains('honor')) return DeviceBrand.huawei;
  if (m.contains('oneplus') || m.contains('oppo') || m.contains('realme')) {
    return DeviceBrand.oneplus;
  }
  return DeviceBrand.other;
}

class SystemBridge {
  SystemBridge._();

  static Future<DeviceBrand> detectBrand() async {
    try {
      final res = await _kSysChannel.invokeMethod<String>('manufacturer');
      return _brandFromManufacturer(res);
    } catch (e) {
      logd('manufacturer probe failed: $e', name: 'onboard');
      return DeviceBrand.other;
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _kSysChannel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openBatterySettings() async {
    try {
      await _kSysChannel.invokeMethod<bool>('openBatteryOptimizationSettings');
    } catch (e) {
      logd('openBatterySettings failed: $e', name: 'onboard');
    }
  }

  static Future<void> openAppDetails() async {
    try {
      await _kSysChannel.invokeMethod<bool>('openAppDetails');
    } catch (e) {
      logd('openAppDetails failed: $e', name: 'onboard');
    }
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  bool _overlayGranted = false;
  bool _batteryIgnored = false;
  DeviceBrand _brand = DeviceBrand.other;
  bool _showBrandPicker = false;
  bool _ignitionDone = false;
  final _plateCtrl = TextEditingController();
  String _plate = kDefaultPlate;

  // Demo pill state.
  int _demoAccepted = 8;
  int _demoRejected = 2;
  Offset _demoOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    await _refreshStatus();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(kDriverPlateKey);
      if (saved != null && saved.isNotEmpty) {
        _plateCtrl.text = saved;
        _plate = saved;
      }
    } catch (_) {}
    HapticFeedback.mediumImpact();
    await DisplayMode.instance.playSelfTest();
    if (mounted) setState(() => _ignitionDone = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _plateCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final overlay = await FlutterOverlayWindow.isPermissionGranted();
      final battery = await SystemBridge.isIgnoringBatteryOptimizations();
      final brand = await SystemBridge.detectBrand();
      if (!mounted) return;
      setState(() {
        _overlayGranted = overlay;
        _batteryIgnored = battery;
        _brand = brand;
      });
    } on PlatformException catch (e, s) {
      loge('Failed to refresh status', name: 'onboarding', error: e, stack: s);
    }
  }

  Future<void> _persistPlate() async {
    final plate = normalizePlate(_plateCtrl.text);
    if (plate.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kDriverPlateKey, plate);
    } catch (_) {}
  }

  Future<void> _requestOverlay() async {
    HapticFeedback.lightImpact();
    await _persistPlate();
    await FlutterOverlayWindow.requestPermission();
    await _refreshStatus();
  }

  Future<void> _openBattery() async {
    HapticFeedback.lightImpact();
    await SystemBridge.openBatterySettings();
  }

  Future<void> _finish() async {
    await _persistPlate();
    widget.onDone();
  }

  bool get _canFinish => _overlayGranted;

  double get _demoRate {
    final t = _demoAccepted + _demoRejected;
    if (t == 0) return 100;
    return (_demoAccepted / t) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          S.onboardingTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _finish,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, kMinTouchTarget),
            ),
            child: Text(
              S.skipLater,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_ignitionDone)
                _IgnitionSplash(onDone: () {})
              else ...[
                Text(
                  S.platePrompt,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Center(child: LicensePlate(text: _plate, height: 44)),
                const SizedBox(height: 12),
                TextField(
                  controller: _plateCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [PlateInputFormatter()],
                  style: T.titleLg.copyWith(fontWeight: FontWeight.w700, letterSpacing: 2, fontFamily: AppFonts.jetBrainsMono),
                  decoration: InputDecoration(
                    hintText: S.plateHint,
                    hintStyle: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: AppColors.mutedText,
                    ),
                    filled: true,
                    fillColor: AppColors.inset,
                    border: const OutlineInputBorder(
                      borderRadius: AppRadius.smRadius,
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _plate = normalizePlate(v)),
                ),
                const SizedBox(height: 28),
                Text(
                  S.overlayDemoTitle,
                  style: T.titleSm.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  S.overlayDemoBody,
                  style: T.body.copyWith(color: AppColors.mutedText, height: 1.45),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 120,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 20 + _demoOffset.dx,
                        top: 20 + _demoOffset.dy,
                        child: GestureDetector(
                          onPanUpdate: (d) {
                            setState(() {
                              _demoOffset += d.delta;
                            });
                          },
                          child: _DemoPill(
                            rate: _demoRate,
                            accepted: _demoAccepted,
                            rejected: _demoRejected,
                            onReject: () {
                              HapticFeedback.selectionClick();
                              setState(() => _demoRejected++);
                            },
                            onAccept: () {
                              HapticFeedback.selectionClick();
                              setState(() => _demoAccepted++);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: ArcGauge(
                    value: _demoRate,
                    arcValue: _demoRate * kGaugeSweep.value,
                    redline: 80,
                    color: _demoRate < 80
                        ? AppColors.crimson
                        : (_demoRate < 82 ? AppColors.amber : AppColors.emerald),
                    label: S.acceptRate,
                    size: 160,
                  ),
                ),
                const SizedBox(height: 24),
                _StepCard(
                  title: S.stepOverlayTitle,
                  body: S.stepOverlayBody,
                  done: _overlayGranted,
                  cta: _overlayGranted ? S.stepOverlayDone : S.stepOverlayCta,
                  onTap: _overlayGranted ? null : _requestOverlay,
                ),
                const SizedBox(height: 16),
                _BatteryCard(
                  brand: _brand,
                  done: _batteryIgnored,
                  showBrandPicker: _showBrandPicker,
                  onToggleBrandPicker: () =>
                      setState(() => _showBrandPicker = !_showBrandPicker),
                  onBrandChanged: (b) => setState(() => _brand = b),
                  onOpenSettings: _openBattery,
                ),
                const SizedBox(height: 32),
                _BigCta(
                  label: S.finish,
                  enabled: _canFinish,
                  color: _kEmerald,
                  onTap: _canFinish ? _finish : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IgnitionSplash extends StatefulWidget {
  const _IgnitionSplash({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_IgnitionSplash> createState() => _IgnitionSplashState();
}

class _IgnitionSplashState extends State<_IgnitionSplash> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: kGaugeSweep,
            builder: (context, sweep, _) {
              return ArcGauge(
                value: 100,
                arcValue: 100 * sweep,
                redline: 80,
                color: AppColors.emerald,
                label: 'RateHelper',
                size: 200,
              );
            },
          ),
          const SizedBox(height: 16),
          const LicensePlate(text: kDefaultPlate, height: 32),
        ],
      ),
    );
  }
}

class _DemoPill extends StatelessWidget {
  const _DemoPill({
    required this.rate,
    required this.accepted,
    required this.rejected,
    required this.onReject,
    required this.onAccept,
  });

  final double rate;
  final int accepted;
  final int rejected;
  final VoidCallback onReject;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final color = rate < 80
        ? AppColors.crimson
        : (rate < 82 ? AppColors.amber : AppColors.emerald);
    return Material(
      color: AppColors.overlayPill,
      elevation: 8,
      shadowColor: Colors.black,
                    shape: const StadiumBorder(
                      side: BorderSide(
                        color: AppColors.hairlineStrong,
                        width: 1,
                      ),
                    ),
      child: SizedBox(
        width: 240,
        height: 72,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _DemoBtn(color: AppColors.crimson, icon: Icons.remove_rounded, onTap: onReject),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatRatePercent(rate),
                  style: T.rateFor(color).copyWith(fontSize: 26),
                ),
                Text(
                  '$accepted/$rejected',
                  style: T.overlayRatioFor(),
                ),
              ],
            ),
            const SizedBox(width: 10),
            _DemoBtn(color: AppColors.emerald, icon: Icons.add_rounded, onTap: onAccept),
          ],
        ),
      ),
    );
  }
}

class _DemoBtn extends StatelessWidget {
  const _DemoBtn({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.20),
      shape: CircleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.55), width: 1.5),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashColor: color.withValues(alpha: 0.35),
        highlightColor: color.withValues(alpha: 0.15),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.body,
    required this.done,
    required this.cta,
    required this.onTap,
  });

  final String title;
  final String body;
  final bool done;
  final String cta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kPageInset),
      decoration: BoxDecoration(
        color: _kCardColor,
        borderRadius: kCardBorderRadius,
        border: kCardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: T.titleXs.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (done)
                const Icon(Icons.check_circle_rounded, color: _kEmerald),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: T.label.copyWith(height: 1.45),
          ),
          const SizedBox(height: 14),
          _BigCta(
            label: cta,
            enabled: onTap != null,
            color: done ? _kEmerald : _kAmber,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard({
    required this.brand,
    required this.done,
    required this.showBrandPicker,
    required this.onToggleBrandPicker,
    required this.onBrandChanged,
    required this.onOpenSettings,
  });

  final DeviceBrand brand;
  final bool done;
  final bool showBrandPicker;
  final VoidCallback onToggleBrandPicker;
  final ValueChanged<DeviceBrand> onBrandChanged;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kPageInset),
      decoration: BoxDecoration(
        color: _kCardColor,
        borderRadius: kCardBorderRadius,
        border: kCardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  S.stepBatteryTitle,
                  style: T.titleXs.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              if (done)
                const Icon(Icons.check_circle_rounded, color: _kEmerald),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            S.stepBatteryBody,
            style: T.label.copyWith(height: 1.45),
          ),
          const SizedBox(height: 10),
          Text(
            brand.label,
            style: T.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: AppColors.inset,
              borderRadius: AppRadius.smRadius,
            ),
            child: Text(
              brand.steps,
              style: T.label.copyWith(color: Colors.white, fontWeight: FontWeight.w500, height: 1.5),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onToggleBrandPicker,
              child: Text(
                S.wrongPhone,
                style: T.label,
              ),
            ),
          ),
          if (showBrandPicker) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in DeviceBrand.values)
                  _BrandChip(
                    label: b.label,
                    selected: b == brand,
                    onTap: () => onBrandChanged(b),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
          _BigCta(
            label: S.stepBatteryCta,
            enabled: true,
            color: done ? _kEmerald : _kAmber,
            onTap: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _BrandChip extends StatelessWidget {
  const _BrandChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white12 : AppColors.inset,
      borderRadius: AppRadius.pillRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        splashColor: Colors.white.withValues(alpha: 0.12),
        highlightColor: Colors.white.withValues(alpha: 0.06),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: selected
                ? T.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w800)
                : T.caption.copyWith(color: AppColors.labelText, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _BigCta extends StatelessWidget {
  const _BigCta({
    required this.label,
    required this.enabled,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? color.withValues(alpha: 0.18) : Colors.white12,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdRadius,
        side: BorderSide(
          color: enabled ? color.withValues(alpha: 0.55) : AppColors.disabledText,
          width: 1.4,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled
            ? () {
                HapticFeedback.lightImpact();
                onTap?.call();
              }
            : null,
        splashColor: enabled ? color.withValues(alpha: 0.25) : null,
        highlightColor: enabled ? color.withValues(alpha: 0.12) : null,
        child: Container(
          height: 60,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: T.bodyStrong.copyWith(color: enabled ? color : AppColors.disabledText, fontWeight: FontWeight.w900, letterSpacing: 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Same content as the onboarding flow, opened later from the AppBar
/// so the user can re-read the instructions without resetting the
/// `onboardingComplete` flag.
class SetupGuideScreen extends StatefulWidget {
  const SetupGuideScreen({super.key});

  @override
  State<SetupGuideScreen> createState() => _SetupGuideScreenState();
}

class _SetupGuideScreenState extends State<SetupGuideScreen> {
  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(onDone: () => Navigator.of(context).pop());
  }
}
