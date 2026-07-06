import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:google_fonts/google_fonts.dart';

import 'l10n.dart';
import 'log.dart';

const _kCardColor = Color(0xFF1A1A1A);
const _kEmerald = Color(0xFF10B981);
const _kAmber = Color(0xFFF59E0B);
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
    final overlay = await FlutterOverlayWindow.isPermissionGranted();
    final battery = await SystemBridge.isIgnoringBatteryOptimizations();
    final brand = await SystemBridge.detectBrand();
    if (!mounted) return;
    setState(() {
      _overlayGranted = overlay;
      _batteryIgnored = battery;
      _brand = brand;
    });
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
          style: GoogleFonts.dmSans(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: widget.onDone,
            child: Text(
              S.skip,
              style: GoogleFonts.dmSans(color: Colors.white54),
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
                style: GoogleFonts.dmSans(
                  color: Colors.white70,
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
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.dmSans(
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
            style: GoogleFonts.dmSans(
              color: Colors.white70,
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
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  S.stepBatteryTitle,
                  style: GoogleFonts.dmSans(
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
            style: GoogleFonts.dmSans(
              color: Colors.white70,
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
              color: const Color(0xFF0F0F0F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              brand.steps,
              style: GoogleFonts.dmSans(
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
      color: selected ? Colors.white12 : const Color(0xFF0F0F0F),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              color: selected ? Colors.white : Colors.white60,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
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
      child: Container(
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.18) : Colors.white12,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled ? color.withValues(alpha: 0.55) : Colors.white24,
            width: 1.4,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            color: enabled ? color : Colors.white38,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
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
