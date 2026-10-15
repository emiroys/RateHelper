import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'crash_logger.dart';
import 'earnings_models.dart';
import 'earnings_screen.dart';
import 'fonts.dart';
import 'l10n.dart';
import 'onboarding_screen.dart';
import 'overlay_widget.dart';
import 'update_dialog.dart';

/// Live mirror of the settings Home still owns.
///
/// The switches live on this screen, but wakelock, the accessibility
/// pending-enable flag, overlay reopen, and [OverlaySync] stay on Home.
/// Publishing a new snapshot is how a toggle shows up there immediately.
@immutable
class SettingsSnapshot {
  const SettingsSnapshot({
    required this.autoComplete,
    required this.steeringWheel,
    required this.keepScreenOn,
    required this.autoUpdate,
    required this.autoEvents,
    required this.pillOrientation,
    required this.showOverlayCancel,
    required this.lang,
  });

  static const initial = SettingsSnapshot(
    autoComplete: false,
    steeringWheel: false,
    keepScreenOn: false,
    autoUpdate: false,
    autoEvents: false,
    pillOrientation: PillOrientation.horizontal,
    showOverlayCancel: false,
    lang: AppLang.tr,
  );

  final bool autoComplete;
  final bool steeringWheel;
  final bool keepScreenOn;
  final bool autoUpdate;
  final bool autoEvents;
  final PillOrientation pillOrientation;
  final bool showOverlayCancel;
  final AppLang lang;

  @override
  bool operator ==(Object other) {
    return other is SettingsSnapshot &&
        other.autoComplete == autoComplete &&
        other.steeringWheel == steeringWheel &&
        other.keepScreenOn == keepScreenOn &&
        other.autoUpdate == autoUpdate &&
        other.autoEvents == autoEvents &&
        other.pillOrientation == pillOrientation &&
        other.showOverlayCancel == showOverlayCancel &&
        other.lang == lang;
  }

  @override
  int get hashCode => Object.hash(
    autoComplete,
    steeringWheel,
    keepScreenOn,
    autoUpdate,
    autoEvents,
    pillOrientation,
    showOverlayCancel,
    lang,
  );
}

/// Closures into Home's existing setters. Pref keys and permission flows
/// are not reimplemented here.
class SettingsBindings {
  const SettingsBindings({
    required this.snapshot,
    required this.versionLabel,
    required this.setAutoComplete,
    required this.setSteeringWheel,
    required this.setKeepScreenOn,
    required this.setAutoUpdate,
    required this.setAutoEvents,
    required this.setPillOrientation,
    required this.setOverlayCancel,
    required this.setLanguage,
    required this.onDriverModeChanged,
  });

  final ValueListenable<SettingsSnapshot> snapshot;
  final String? Function() versionLabel;
  final Future<void> Function(bool enabled) setAutoComplete;
  final Future<void> Function(bool enabled) setSteeringWheel;
  final Future<void> Function(bool enabled) setKeepScreenOn;
  final Future<void> Function(bool enabled) setAutoUpdate;
  final Future<void> Function(bool enabled) setAutoEvents;
  final Future<void> Function(PillOrientation orientation) setPillOrientation;
  final Future<void> Function(bool enabled) setOverlayCancel;
  final Future<void> Function(AppLang lang) setLanguage;
  final VoidCallback onDriverModeChanged;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.bindings});

  final SettingsBindings bindings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final bindings = widget.bindings;
    return ValueListenableBuilder<SettingsSnapshot>(
      valueListenable: bindings.snapshot,
      builder: (context, snapshot, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              S.settingsTitle,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                _sectionHeader(S.settingsDriving),
                const SizedBox(height: 12),
                _ActionTile(
                  title: S.drivingMode,
                  value: _driverModeValue(activeDriverMode),
                  onTap: () => unawaited(_pickDriverMode(context)),
                ),
                const SizedBox(height: 10),
                _SwitchTile(
                  label: S.autoCompleteTrips,
                  value: snapshot.autoComplete,
                  switchKey: const ValueKey('settings-auto-complete'),
                  onChanged: (enabled) =>
                      unawaited(bindings.setAutoComplete(enabled)),
                ),
                const SizedBox(height: 10),
                _SwitchTile(
                  label: S.steeringWheelCounter,
                  value: snapshot.steeringWheel,
                  switchKey: const ValueKey('settings-steering-wheel'),
                  onChanged: (enabled) =>
                      unawaited(bindings.setSteeringWheel(enabled)),
                ),
                const SizedBox(height: 10),
                _SwitchTile(
                  label: S.keepScreenOn,
                  value: snapshot.keepScreenOn,
                  switchKey: const ValueKey('settings-keep-screen-on'),
                  onChanged: (enabled) =>
                      unawaited(bindings.setKeepScreenOn(enabled)),
                ),
                const SizedBox(height: 28),
                _sectionHeader(S.settingsOverlay),
                const SizedBox(height: 12),
                _PillOrientationCard(
                  orientation: snapshot.pillOrientation,
                  onSelected: (orientation) =>
                      unawaited(bindings.setPillOrientation(orientation)),
                ),
                const SizedBox(height: 10),
                _SwitchTile(
                  label: S.overlayShowCancelButton,
                  value: snapshot.showOverlayCancel,
                  switchKey: const ValueKey('settings-overlay-cancel'),
                  onChanged: (enabled) =>
                      unawaited(bindings.setOverlayCancel(enabled)),
                ),
                const SizedBox(height: 28),
                _sectionHeader(S.settingsPreferences),
                const SizedBox(height: 12),
                _ActionTile(
                  title: S.navLang,
                  value: _langName(snapshot.lang),
                  icon: Icons.language_rounded,
                  onTap: () => unawaited(_pickLanguage(context, snapshot.lang)),
                ),
                const SizedBox(height: 10),
                _SwitchTile(
                  label: S.autoUpdateCheck,
                  value: snapshot.autoUpdate,
                  switchKey: const ValueKey('settings-auto-update'),
                  onChanged: (enabled) =>
                      unawaited(bindings.setAutoUpdate(enabled)),
                ),
                const SizedBox(height: 10),
                _SwitchTile(
                  label: S.autoFetchEvents,
                  value: snapshot.autoEvents,
                  switchKey: const ValueKey('settings-auto-events'),
                  onChanged: (enabled) =>
                      unawaited(bindings.setAutoEvents(enabled)),
                ),
                const SizedBox(height: 28),
                _sectionHeader(S.settingsSystem),
                const SizedBox(height: 12),
                UpdateCheckTile(versionLabel: bindings.versionLabel()),
                const SizedBox(height: 10),
                _ActionTile(
                  title: S.setupGuide,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SetupGuideScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _ActionTile(
                  title: S.crashLogTitle,
                  onTap: () => unawaited(showCrashLogSheet(context)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDriverMode(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    await showDriverModeDialog(context, prefs, () {
      widget.bindings.onDriverModeChanged();
      if (mounted) setState(() {});
    });
  }

  Future<void> _pickLanguage(BuildContext context, AppLang current) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _LangOption(
              flag: '🇹🇷',
              name: 'Türkçe',
              selected: current == AppLang.tr,
              onTap: () {
                unawaited(widget.bindings.setLanguage(AppLang.tr));
                Navigator.of(ctx).pop();
              },
            ),
            _LangOption(
              flag: '🇬🇧',
              name: 'English',
              selected: current == AppLang.en,
              onTap: () {
                unawaited(widget.bindings.setLanguage(AppLang.en));
                Navigator.of(ctx).pop();
              },
            ),
            _LangOption(
              flag: '🇵🇱',
              name: 'Polski',
              selected: current == AppLang.pl,
              onTap: () {
                unawaited(widget.bindings.setLanguage(AppLang.pl));
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String _driverModeValue(DriverMode mode) => switch (mode) {
  DriverMode.paired => S.driverModePaired,
  DriverMode.trio => S.driverModeTrio,
  DriverMode.solo => S.driverModeSolo,
};

String _langName(AppLang lang) => switch (lang) {
  AppLang.tr => 'Türkçe',
  AppLang.en => 'English',
  AppLang.pl => 'Polski',
};

Widget _sectionHeader(String title) {
  return Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs),
    child: Text(title, style: AppTextStyles.eyebrowStyle(AppColors.labelText)),
  );
}

/// Crash-log sheet moved off the home overflow menu. Same file, same copy
/// and clear actions.
Future<void> showCrashLogSheet(BuildContext context) async {
  String body = '';
  final f = await CrashLogger.currentLogFile();
  if (f != null) {
    try {
      final content = await f.readAsString();
      if (content.trim().isNotEmpty) {
        body = content;
      }
    } on FileSystemException {
      // Stay with the empty-state placeholder.
    }
  }
  final isEmpty = body.trim().isEmpty;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.sheet,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.crashLogTitle,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: AppColors.labelText,
              ),
            ),
            const SizedBox(height: 12),
            if (isEmpty)
              AppEmptyState(
                compact: true,
                icon: Icons.verified_rounded,
                title: S.crashLogEmptyTitle,
                description: S.crashLogEmpty,
              )
            else ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    body,
                    style: const TextStyle(
                      fontFamily: AppFonts.jetBrainsMono,
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, kMinTouchTarget),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: body));
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(S.crashLogCopied),
                            duration: const Duration(seconds: 1),
                            backgroundColor: AppColors.card,
                          ),
                        );
                      },
                      child: Text(
                        S.crashLogCopy,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, kMinTouchTarget),
                      ),
                      onPressed: () async {
                        await CrashLogger.clear();
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                      },
                      child: Text(
                        S.crashLogClear,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          color: AppColors.crimson,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.switchKey,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key switchKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.cardBorderColor, width: 1),
        borderRadius: AppRadius.mdBorder,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedText,
              ),
            ),
          ),
          Switch(
            key: switchKey,
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.emerald,
            activeTrackColor: AppColors.emerald.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.onTap,
    this.value,
    this.icon,
  });

  final String title;
  final String? value;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
        side: BorderSide(color: AppColors.cardBorderColor, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdBorder,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget + 8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: Colors.white70),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (value != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          value!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.dmSans,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.mutedText,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillOrientationCard extends StatelessWidget {
  const _PillOrientationCard({
    required this.orientation,
    required this.onSelected,
  });

  final PillOrientation orientation;
  final ValueChanged<PillOrientation> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.cardBorderColor, width: 1),
        borderRadius: AppRadius.mdBorder,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              top: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              S.overlayPillOrientation,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: AppTextStyles.body,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedText,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _chip(
                  PillOrientation.horizontal,
                  S.overlayPillHorizontal,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _chip(PillOrientation.vertical, S.overlayPillVertical),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(PillOrientation value, String label) {
    final selected = orientation == value;
    return Material(
      color: selected
          ? AppColors.emerald.withValues(alpha: 0.22)
          : AppColors.inset,
      borderRadius: AppRadius.smBorder,
      child: InkWell(
        onTap: () => onSelected(value),
        borderRadius: AppRadius.smBorder,
        child: SizedBox(
          height: kMinTouchTarget + 8,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: AppTextStyles.body,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.emerald : AppColors.mutedText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangOption extends StatelessWidget {
  const _LangOption({
    required this.flag,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String flag;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name,
                  style: selected
                      ? const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        )
                      : const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          color: AppColors.mutedText,
                        ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  color: AppColors.emerald,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
