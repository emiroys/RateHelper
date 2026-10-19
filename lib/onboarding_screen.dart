import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:rate_helper/fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'l10n.dart';
import 'log.dart';
import 'startup_language.dart';

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

/// Five-step first-run guide.
///
/// The same widget also backs the later Setup Guide entry in Settings. In that
/// mode it never writes `onboardingComplete`; [onDone] simply pops the route.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.onLanguageChanged,
    this.isSetupGuide = false,
  });

  final VoidCallback onDone;

  /// Lets the Settings-hosted guide reuse Home's language setter so the
  /// overlay and the rest of the app relabel immediately.
  final Future<void> Function(AppLang lang)? onLanguageChanged;

  final bool isSetupGuide;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  static const int _stepCount = 5;

  final ScrollController _scrollController = ScrollController();

  int _step = 0;
  bool _overlayGranted = false;
  bool _batteryIgnored = false;
  bool _statusLoaded = false;
  DeviceBrand _brand = DeviceBrand.other;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from Android Settings must refresh the status without
    // resetting the wizard to step 1.
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStatus());
    }
  }

  Future<void> _refreshStatus() async {
    bool? overlay;
    bool? battery;
    DeviceBrand? brand;
    try {
      final overlayFuture = FlutterOverlayWindow.isPermissionGranted();
      final batteryFuture = SystemBridge.isIgnoringBatteryOptimizations();
      final brandFuture = SystemBridge.detectBrand();
      overlay = await overlayFuture;
      battery = await batteryFuture;
      brand = await brandFuture;
    } catch (e, s) {
      loge(
        'Failed to refresh onboarding status',
        name: 'onboarding',
        error: e,
        stack: s,
      );
    }
    if (!mounted) return;
    setState(() {
      if (overlay != null) _overlayGranted = overlay;
      if (battery != null) _batteryIgnored = battery;
      if (brand != null) _brand = brand;
      _statusLoaded = true;
    });
  }

  void _goToStep(int step) {
    if (step < 0 || step >= _stepCount) return;
    HapticFeedback.selectionClick();
    setState(() => _step = step);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _nextStep() async {
    if (_step < _stepCount - 1) {
      _goToStep(_step + 1);
      return;
    }
    await _finishRequested();
  }

  void _backStep() {
    if (_step > 0) _goToStep(_step - 1);
  }

  Future<void> _requestOverlay() async {
    HapticFeedback.lightImpact();
    try {
      await FlutterOverlayWindow.requestPermission();
    } on PlatformException catch (e) {
      logd('overlay permission request failed: $e', name: 'onboard');
    }
    await _refreshStatus();
  }

  Future<void> _openBattery() async {
    HapticFeedback.lightImpact();
    await SystemBridge.openBatterySettings();
  }

  Future<void> _openAppInfo() async {
    HapticFeedback.lightImpact();
    await SystemBridge.openAppDetails();
  }

  Future<void> _setLanguage(AppLang lang) async {
    if (lang == S.lang) return;
    HapticFeedback.selectionClick();
    S.setLang(lang);
    if (mounted) setState(() {});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAppLanguagePrefsKey, lang.name);
    } catch (e) {
      logd('language save failed: $e', name: 'onboard');
    }
    final callback = widget.onLanguageChanged;
    if (callback != null) {
      try {
        await callback(lang);
      } catch (e) {
        logd('language callback failed: $e', name: 'onboard');
      }
    }
  }

  Future<void> _finishRequested() async {
    if (widget.isSetupGuide) {
      widget.onDone();
      return;
    }
    if (_overlayGranted && _batteryIgnored) {
      widget.onDone();
      return;
    }
    // Overlay permission is a hard requirement; battery state is only
    // verifiable through Android's Doze whitelist. Either way, explain the
    // consequence before letting the user leave setup.
    final leave = await _confirmSkip(overlayMissing: !_overlayGranted);
    if (leave == true) widget.onDone();
  }

  Future<bool?> _confirmSkip({required bool overlayMissing}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.dialog,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgBorder),
        title: Text(
          S.onboardingSkipTitle,
          style: T.dmSans20.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            overlayMissing
                ? S.onboardingSkipOverlayBody
                : S.onboardingSkipBatteryBody,
            style: AppTextStyles.bodyStyle.copyWith(
              color: AppColors.mutedText,
              height: 1.45,
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('onboarding-skip-stay'),
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, kMinTouchTarget),
            ),
            child: Text(
              S.onboardingSkipStay,
              textAlign: TextAlign.center,
              style: T.dmSans12.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.labelText,
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('onboarding-skip-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, kMinTouchTarget),
            ),
            child: Text(
              S.onboardingSkipConfirm,
              textAlign: TextAlign.center,
              style: T.dmSans12.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.crimson,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryLabel = _step == _stepCount - 1
        ? (widget.isSetupGuide
              ? S.onboardingCloseGuide
              : S.onboardingOpenRateHelper)
        : S.onboardingContinue;
    final primaryIcon = _step == _stepCount - 1
        ? (widget.isSetupGuide ? Icons.close_rounded : Icons.play_arrow_rounded)
        : Icons.arrow_forward_rounded;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                child: KeyedSubtree(
                  key: ValueKey('onboarding-step-${_step + 1}'),
                  child: _buildStep(),
                ),
              ),
            ),
            _buildBottomBar(primaryLabel, primaryIcon),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final showSkip = !widget.isSetupGuide && _step < _stepCount - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.14),
                  borderRadius: AppRadius.mdBorder,
                  border: Border.all(
                    color: AppColors.emerald.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.speed_rounded,
                  color: AppColors.emerald,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'RateHelper',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: Colors.white,
                    fontSize: AppTextStyles.headline,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              if (showSkip)
                TextButton(
                  key: const ValueKey('onboarding-skip'),
                  onPressed: () => unawaited(_finishRequested()),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, kMinTouchTarget),
                  ),
                  child: Text(
                    S.skip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.dmSans14.copyWith(color: AppColors.labelText),
                  ),
                )
              else if (widget.isSetupGuide)
                AppTapTarget(
                  key: const ValueKey('onboarding-close'),
                  onTap: widget.onDone,
                  tooltip: S.onboardingCloseGuide,
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppColors.labelText,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _LanguageSelector(
            current: S.lang,
            onSelected: (lang) => unawaited(_setLanguage(lang)),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            S.onboardingStepOf(_step + 1, _stepCount),
            style: AppTextStyles.eyebrowStyle(AppColors.emerald),
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadius.xsBorder,
            child: LinearProgressIndicator(
              value: (_step + 1) / _stepCount,
              minHeight: 6,
              backgroundColor: AppColors.surfaceElevated,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.emerald,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(String primaryLabel, IconData primaryIcon) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_step > 0) ...[
              Expanded(
                child: AppSecondaryButton(
                  key: const ValueKey('onboarding-back'),
                  label: S.onboardingBack,
                  icon: Icons.arrow_back_rounded,
                  height: 54,
                  onTap: _backStep,
                ),
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
            ],
            Expanded(
              flex: 2,
              child: AppPrimaryButton(
                key: const ValueKey('onboarding-primary'),
                label: primaryLabel,
                icon: primaryIcon,
                height: 54,
                color: AppColors.emerald,
                textColor: Colors.black,
                onTap: () => unawaited(_nextStep()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        // The language key forces a rebuild after a manual language change.
        return KeyedSubtree(
          key: ValueKey('welcome-${S.lang.name}'),
          child: const _WelcomeStep(),
        );
      case 1:
        return _PermissionStep(
          loaded: _statusLoaded,
          granted: _overlayGranted,
          onOpenSettings: () => unawaited(_requestOverlay()),
        );
      case 2:
        return _BatteryStep(
          loaded: _statusLoaded,
          ignored: _batteryIgnored,
          brand: _brand,
          onBrandChanged: (brand) => setState(() => _brand = brand),
          onOpenSettings: () => unawaited(_openBattery()),
          onOpenAppInfo: () => unawaited(_openAppInfo()),
        );
      case 3:
        // The language key forces a rebuild after a manual language change.
        return KeyedSubtree(
          key: ValueKey('optional-${S.lang.name}'),
          child: const _OptionalStep(),
        );
      default:
        return _ReadyStep(
          overlayGranted: _overlayGranted,
          batteryIgnored: _batteryIgnored,
        );
    }
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.current, required this.onSelected});

  final AppLang current;
  final ValueChanged<AppLang> onSelected;

  static const _codes = {AppLang.tr: 'TR', AppLang.en: 'EN', AppLang.pl: 'PL'};

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: S.onboardingLanguageSelector,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.pillBorder,
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            for (final lang in AppLang.values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: lang == current,
                  label: S.languageName(lang),
                  child: Material(
                    color: lang == current
                        ? AppColors.emerald.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: AppRadius.pillBorder,
                    child: InkWell(
                      key: ValueKey('onboarding-lang-${lang.name}'),
                      onTap: () => onSelected(lang),
                      borderRadius: AppRadius.pillBorder,
                      child: SizedBox(
                        height: kMinTouchTarget,
                        child: Center(
                          child: Text(
                            _codes[lang]!,
                            style: T.dmSans12.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: lang == current
                                  ? AppColors.emerald
                                  : AppColors.labelText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading({
    required this.icon,
    required this.title,
    required this.lead,
    this.accent = AppColors.emerald,
  });

  final IconData icon;
  final String title;
  final String lead;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: accent, size: 28),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: T.dmSans24.copyWith(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.15,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          lead,
          style: AppTextStyles.bodyStyle.copyWith(
            color: AppColors.mutedText,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, this.background});

  final Widget child;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: background ?? AppColors.surface,
        borderRadius: AppRadius.mdBorder,
        border: Border.all(color: AppColors.cardBorderColor),
      ),
      child: child,
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconBadge(icon: icon, active: true),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.headlineStyle.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: AppTextStyles.bodyStyle.copyWith(
                    color: AppColors.mutedText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
    this.icon = Icons.info_outline_rounded,
    this.accent = AppColors.labelText,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.headlineStyle.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: AppTextStyles.bodyStyle.copyWith(
                    color: AppColors.mutedText,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.color,
    this.body,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppRadius.mdBorder,
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.headlineStyle.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    body!,
                    style: AppTextStyles.bodyStyle.copyWith(
                      color: AppColors.mutedText,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedSteps extends StatelessWidget {
  const _NumberedSteps({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.emerald.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  '${i + 1}',
                  style: T.dmSans12.copyWith(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
              Expanded(
                child: Text(
                  steps[i],
                  style: AppTextStyles.bodyStyle.copyWith(
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeading(
          icon: Icons.dashboard_customize_rounded,
          title: S.onboardingWelcomeTitle,
          lead: S.onboardingWelcomeLead,
        ),
        const SizedBox(height: AppSpacing.lg),
        _FeatureCard(
          icon: Icons.add_chart_rounded,
          title: S.onboardingFeatureRequestsTitle,
          body: S.onboardingFeatureRequestsBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _FeatureCard(
          icon: Icons.percent_rounded,
          title: S.onboardingFeatureRatesTitle,
          body: S.onboardingFeatureRatesBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _FeatureCard(
          icon: Icons.picture_in_picture_alt_rounded,
          title: S.onboardingFeatureOverlayTitle,
          body: S.onboardingFeatureOverlayBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _FeatureCard(
          icon: Icons.settings_remote_rounded,
          title: S.onboardingFeatureAltControlsTitle,
          body: S.onboardingFeatureAltControlsBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _FeatureCard(
          icon: Icons.local_gas_station_rounded,
          title: S.onboardingFeatureToolsTitle,
          body: S.onboardingFeatureToolsBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _FeatureCard(
          icon: Icons.lock_outline_rounded,
          title: S.onboardingFeatureLocalTitle,
          body: S.onboardingFeatureLocalBody,
        ),
      ],
    );
  }
}

class _PermissionStep extends StatelessWidget {
  const _PermissionStep({
    required this.loaded,
    required this.granted,
    required this.onOpenSettings,
  });

  final bool loaded;
  final bool granted;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeading(
          icon: Icons.layers_outlined,
          title: S.onboardingOverlayTitle,
          lead: S.onboardingOverlayLead,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (!loaded)
          _StatusBanner(
            key: const ValueKey('onboarding-overlay-status'),
            icon: Icons.hourglass_top_rounded,
            title: S.onboardingPermissionChecking,
            color: AppColors.labelText,
          )
        else if (granted)
          _StatusBanner(
            key: const ValueKey('onboarding-overlay-status'),
            icon: Icons.check_circle_rounded,
            title: S.onboardingPermissionGranted,
            body: S.onboardingPermissionGrantedBody,
            color: AppColors.emerald,
          )
        else
          _StatusBanner(
            key: const ValueKey('onboarding-overlay-status'),
            icon: Icons.error_outline_rounded,
            title: S.onboardingPermissionMissing,
            body: S.onboardingPermissionMissingBody,
            color: AppColors.amber,
          ),
        const SizedBox(height: AppSpacing.lg),
        _InfoCard(
          title: S.onboardingOverlayWhatTitle,
          body: S.onboardingOverlayWhatBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _InfoCard(
          title: S.onboardingOverlayWhyTitle,
          body: S.onboardingOverlayWhyBody,
          icon: Icons.help_outline_rounded,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          S.onboardingOverlayHowTitle,
          style: AppTextStyles.headlineStyle.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _NumberedSteps(
          steps: [
            S.onboardingOverlayHowStep1,
            S.onboardingOverlayHowStep2,
            S.onboardingOverlayHowStep3,
            S.onboardingOverlayHowStep4,
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPrimaryButton(
          key: const ValueKey('onboarding-overlay-open-settings'),
          label: S.onboardingOpenPermissionSettings,
          icon: Icons.open_in_new_rounded,
          color: AppColors.emerald,
          textColor: Colors.black,
          onTap: onOpenSettings,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        Text(
          S.onboardingOverlayUnavailable,
          style: AppTextStyles.captionStyle.copyWith(height: 1.4),
        ),
      ],
    );
  }
}

class _BatteryStep extends StatelessWidget {
  const _BatteryStep({
    required this.loaded,
    required this.ignored,
    required this.brand,
    required this.onBrandChanged,
    required this.onOpenSettings,
    required this.onOpenAppInfo,
  });

  final bool loaded;
  final bool ignored;
  final DeviceBrand brand;
  final ValueChanged<DeviceBrand> onBrandChanged;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAppInfo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeading(
          icon: Icons.battery_saver_rounded,
          title: S.onboardingBatteryTitle,
          lead: S.onboardingBatteryLead,
          accent: AppColors.amber,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          S.onboardingBatterySystemStatus,
          style: AppTextStyles.eyebrowStyle(AppColors.labelText),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (!loaded)
          _StatusBanner(
            key: const ValueKey('onboarding-battery-status'),
            icon: Icons.hourglass_top_rounded,
            title: S.onboardingBatteryChecking,
            color: AppColors.labelText,
          )
        else if (ignored)
          _StatusBanner(
            key: const ValueKey('onboarding-battery-status'),
            icon: Icons.check_circle_rounded,
            title: S.onboardingBatteryVerified,
            body: S.onboardingBatteryVerifiedBody,
            color: AppColors.emerald,
          )
        else
          _StatusBanner(
            key: const ValueKey('onboarding-battery-status'),
            icon: Icons.info_outline_rounded,
            title: S.onboardingBatteryNotVerified,
            body: S.onboardingBatteryNotVerifiedBody,
            color: AppColors.amber,
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          S.onboardingBatteryBrandLabel,
          style: AppTextStyles.headlineStyle.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final b in DeviceBrand.values)
              _BrandChip(
                key: ValueKey('onboarding-brand-${b.name}'),
                label: b.label,
                selected: b == brand,
                onTap: () => onBrandChanged(b),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          S.onboardingBatteryBrandNote,
          style: AppTextStyles.captionStyle.copyWith(height: 1.4),
        ),
        const SizedBox(height: AppSpacing.md),
        _SurfaceCard(
          background: AppColors.inset,
          child: Text(
            brand.steps,
            style: AppTextStyles.bodyStyle.copyWith(
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          S.onboardingBatteryManualNote,
          style: AppTextStyles.captionStyle.copyWith(height: 1.4),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppPrimaryButton(
          key: const ValueKey('onboarding-battery-open-settings'),
          label: S.onboardingBatteryOpenSettings,
          icon: Icons.open_in_new_rounded,
          color: AppColors.emerald,
          textColor: Colors.black,
          onTap: onOpenSettings,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppSecondaryButton(
          key: const ValueKey('onboarding-battery-open-app-info'),
          label: S.onboardingOpenAppInfo,
          icon: Icons.info_outline_rounded,
          height: 48,
          onTap: onOpenAppInfo,
        ),
      ],
    );
  }
}

class _BrandChip extends StatelessWidget {
  const _BrandChip({
    super.key,
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
      color: selected
          ? AppColors.emerald.withValues(alpha: 0.16)
          : AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.pillBorder,
        side: BorderSide(
          color: selected
              ? AppColors.emerald.withValues(alpha: 0.55)
              : AppColors.hairline,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillBorder,
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + AppSpacing.xs,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.dmSans12.copyWith(
              color: selected ? Colors.white : AppColors.labelText,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionalStep extends StatelessWidget {
  const _OptionalStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeading(
          icon: Icons.tune_rounded,
          title: S.onboardingOptionalTitle,
          lead: S.onboardingOptionalLead,
          accent: AppColors.actionAccent,
        ),
        const SizedBox(height: AppSpacing.lg),
        _OptionalFeatureCard(
          icon: Icons.settings_remote_rounded,
          title: S.onboardingOptionalSteeringTitle,
          body: S.onboardingOptionalSteeringBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _OptionalFeatureCard(
          icon: Icons.notifications_active_outlined,
          title: S.onboardingOptionalNotificationsTitle,
          body: S.onboardingOptionalNotificationsBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _OptionalFeatureCard(
          icon: Icons.picture_in_picture_alt_rounded,
          title: S.onboardingOptionalPillTitle,
          body: S.onboardingOptionalPillBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _OptionalFeatureCard(
          icon: Icons.local_gas_station_rounded,
          title: S.onboardingOptionalToolsTitle,
          body: S.onboardingOptionalToolsBody,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _OptionalFeatureCard(
          icon: Icons.event_outlined,
          title: S.onboardingOptionalRadarTitle,
          body: S.onboardingOptionalRadarBody,
        ),
      ],
    );
  }
}

class _OptionalFeatureCard extends StatelessWidget {
  const _OptionalFeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return _SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconBadge(icon: icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.headlineStyle.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const _OptionalBadge(),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: AppTextStyles.bodyStyle.copyWith(
                    color: AppColors.mutedText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionalBadge extends StatelessWidget {
  const _OptionalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.actionAccent.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillBorder,
        border: Border.all(
          color: AppColors.actionAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        S.onboardingOptionalBadge,
        style: AppTextStyles.eyebrowStyle(AppColors.actionAccent),
      ),
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep({
    required this.overlayGranted,
    required this.batteryIgnored,
  });

  final bool overlayGranted;
  final bool batteryIgnored;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeading(
          icon: Icons.check_circle_rounded,
          title: S.onboardingReadyTitle,
          lead: S.onboardingReadyLead,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          S.onboardingSummaryTitle,
          style: AppTextStyles.eyebrowStyle(AppColors.labelText),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SurfaceCard(
          child: Column(
            children: [
              _SummaryRow(
                icon: Icons.layers_outlined,
                title: S.onboardingSummaryOverlay,
                value: overlayGranted
                    ? S.onboardingSummaryGranted
                    : S.onboardingSummaryNotGranted,
                color: overlayGranted ? AppColors.emerald : AppColors.amber,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1, color: AppColors.hairline),
              ),
              _SummaryRow(
                icon: Icons.battery_saver_rounded,
                title: S.onboardingSummaryBattery,
                value: batteryIgnored
                    ? S.onboardingSummaryBatteryVerified
                    : S.onboardingSummaryBatteryUnverified,
                color: batteryIgnored ? AppColors.emerald : AppColors.amber,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1, color: AppColors.hairline),
              ),
              _SummaryRow(
                icon: Icons.tune_rounded,
                title: S.onboardingSummaryOptional,
                value: S.onboardingSummaryOptionalValue,
                color: AppColors.labelText,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _InfoCard(
          title: S.onboardingSummaryTitle,
          body: S.onboardingReadySettingsHint,
          icon: Icons.settings_outlined,
          accent: AppColors.emerald,
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.bodyStyle.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: AppTextStyles.captionStyle.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Same content as the onboarding flow, opened later from Settings so the
/// driver can re-read the instructions without resetting the
/// `onboardingComplete` flag.
class SetupGuideScreen extends StatelessWidget {
  const SetupGuideScreen({super.key, this.onLanguageChanged});

  final Future<void> Function(AppLang lang)? onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return OnboardingScreen(
      isSetupGuide: true,
      onLanguageChanged: onLanguageChanged,
      onDone: () => Navigator.of(context).pop(),
    );
  }
}
