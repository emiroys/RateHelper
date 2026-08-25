import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:rate_helper/fonts.dart';

import 'app_colors.dart';
import 'app_widgets.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  Future<void> _requestOverlay() async {
    HapticFeedback.lightImpact();
    await FlutterOverlayWindow.requestPermission();
    await _refreshStatus();
  }

  Future<void> _openBattery() async {
    HapticFeedback.lightImpact();
    await SystemBridge.openBatterySettings();
  }

  bool get _canFinish => _overlayGranted;

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
              style: const TextStyle(fontFamily: AppFonts.dmSans,
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: widget.onDone,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, kMinTouchTarget),
            ),
            child: Text(
              S.skip,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: AppFonts.dmSans, color: AppColors.mutedText),
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
              Text(
                S.onboardingIntro,
                style: const TextStyle(fontFamily: AppFonts.dmSans, 
                  color: AppColors.mutedText,
                  fontSize: 14,
                  height: 1.45,
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
                onBrandChanged: (b) => setState(() => _brand = b),
                onOpenSettings: _openBattery,
              ),
              const SizedBox(height: 32),
              _BigCta(
                label: S.finish,
                enabled: _canFinish,
                color: _kEmerald,
                onTap: _canFinish ? widget.onDone : null,
              ),
            ],
          ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontFamily: AppFonts.dmSans, 
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (done)
                const Icon(Icons.check_circle_rounded, color: _kEmerald),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(fontFamily: AppFonts.dmSans, 
              color: AppColors.mutedText,
              fontSize: 13,
              height: 1.45,
            ),
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
    required this.onBrandChanged,
    required this.onOpenSettings,
  });

  final DeviceBrand brand;
  final bool done;
  final ValueChanged<DeviceBrand> onBrandChanged;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  S.stepBatteryTitle,
                  style: const TextStyle(fontFamily: AppFonts.dmSans, 
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (done)
                const Icon(Icons.check_circle_rounded, color: _kEmerald),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            S.stepBatteryBody,
            style: const TextStyle(fontFamily: AppFonts.dmSans, 
              color: AppColors.mutedText,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.inset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              brand.steps,
              style: const TextStyle(fontFamily: AppFonts.dmSans, 
                color: Colors.white,
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 14),
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
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: selected
                ? const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  )
                : const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: AppColors.labelText,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
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
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 60,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.18) : Colors.white12,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? color.withValues(alpha: 0.55) : AppColors.disabledText,
            width: 1.4,
          ),
        ),
        // Polish CTAs ("NADAJ UPRAWNIENIE", "OTWÓRZ USTAWIENIA") are far wider
        // than their Turkish equivalents at this letter spacing.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: AppFonts.dmSans,
              color: enabled ? color : AppColors.disabledText,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
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
