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
import 'contact_developer.dart';
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
    required this.notificationControls,
    required this.hidePill,
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
    notificationControls: false,
    hidePill: false,
    lang: AppLang.tr,
  );

  final bool autoComplete;
  final bool steeringWheel;
  final bool keepScreenOn;
  final bool autoUpdate;
  final bool autoEvents;
  final PillOrientation pillOrientation;
  final bool showOverlayCancel;
  final bool notificationControls;

  /// Shade-only mode. Home keeps it false whenever [notificationControls]
  /// is off.
  final bool hidePill;
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
        other.notificationControls == notificationControls &&
        other.hidePill == hidePill &&
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
    notificationControls,
    hidePill,
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
    required this.setNotificationControls,
    required this.setHidePill,
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
  final Future<void> Function(bool enabled) setNotificationControls;
  final Future<void> Function(bool enabled) setHidePill;
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                _SettingsSection(
                  title: S.settingsDriving,
                  children: [
                    _ActionRow(
                      icon: Icons.groups_outlined,
                      title: S.drivingMode,
                      value: _driverModeValue(activeDriverMode),
                      onTap: () => unawaited(_pickDriverMode(context)),
                    ),
                    _SwitchRow(
                      icon: Icons.task_alt_rounded,
                      label: S.autoCompleteTrips,
                      value: snapshot.autoComplete,
                      switchKey: const ValueKey('settings-auto-complete'),
                      onChanged: (enabled) =>
                          unawaited(bindings.setAutoComplete(enabled)),
                    ),
                    _SwitchRow(
                      icon: Icons.settings_remote_outlined,
                      label: S.steeringWheelCounter,
                      value: snapshot.steeringWheel,
                      switchKey: const ValueKey('settings-steering-wheel'),
                      onChanged: (enabled) =>
                          unawaited(bindings.setSteeringWheel(enabled)),
                    ),
                    _SwitchRow(
                      icon: Icons.light_mode_outlined,
                      label: S.keepScreenOn,
                      value: snapshot.keepScreenOn,
                      switchKey: const ValueKey('settings-keep-screen-on'),
                      onChanged: (enabled) =>
                          unawaited(bindings.setKeepScreenOn(enabled)),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: S.settingsOverlay,
                  children: [
                    _PillOrientationRow(
                      orientation: snapshot.pillOrientation,
                      onSelected: (orientation) =>
                          unawaited(bindings.setPillOrientation(orientation)),
                    ),
                    _SwitchRow(
                      icon: Icons.cancel_outlined,
                      label: S.overlayShowCancelButton,
                      value: snapshot.showOverlayCancel,
                      switchKey: const ValueKey('settings-overlay-cancel'),
                      onChanged: (enabled) =>
                          unawaited(bindings.setOverlayCancel(enabled)),
                    ),
                    _SwitchRow(
                      icon: Icons.notifications_active_outlined,
                      label: S.notificationControls,
                      subtitle: S.notificationControlsHint,
                      value: snapshot.notificationControls,
                      switchKey: const ValueKey(
                        'settings-notification-controls',
                      ),
                      hasNestedChild: snapshot.notificationControls,
                      onChanged: (enabled) =>
                          unawaited(bindings.setNotificationControls(enabled)),
                    ),
                    // Depends on the notification buttons, so it is only
                    // offered under them; switching those off also clears it
                    // on Home.
                    if (snapshot.notificationControls)
                      _SwitchRow(
                        icon: Icons.visibility_off_outlined,
                        label: S.hidePill,
                        subtitle: S.hidePillHint,
                        value: snapshot.hidePill,
                        switchKey: const ValueKey('settings-hide-pill'),
                        nested: true,
                        onChanged: (enabled) =>
                            unawaited(bindings.setHidePill(enabled)),
                      ),
                  ],
                ),
                _SettingsSection(
                  title: S.settingsPreferences,
                  children: [
                    _ActionRow(
                      icon: Icons.language_outlined,
                      title: S.navLang,
                      value: _langName(snapshot.lang),
                      onTap: () =>
                          unawaited(_pickLanguage(context, snapshot.lang)),
                    ),
                    _SwitchRow(
                      icon: Icons.autorenew_rounded,
                      label: S.autoUpdateCheck,
                      value: snapshot.autoUpdate,
                      switchKey: const ValueKey('settings-auto-update'),
                      onChanged: (enabled) =>
                          unawaited(bindings.setAutoUpdate(enabled)),
                    ),
                    _SwitchRow(
                      icon: Icons.event_outlined,
                      label: S.autoFetchEvents,
                      value: snapshot.autoEvents,
                      switchKey: const ValueKey('settings-auto-events'),
                      onChanged: (enabled) =>
                          unawaited(bindings.setAutoEvents(enabled)),
                    ),
                  ],
                ),
                _SettingsSection(
                  title: S.settingsSystem,
                  children: [
                    UpdateCheckTile(versionLabel: bindings.versionLabel()),
                    _ActionRow(
                      icon: Icons.menu_book_outlined,
                      title: S.setupGuide,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SetupGuideScreen(),
                          ),
                        );
                      },
                    ),
                    _ActionRow(
                      icon: Icons.bug_report_outlined,
                      title: S.crashLogTitle,
                      onTap: () => unawaited(showCrashLogSheet(context)),
                    ),
                    _ActionRow(
                      key: const ValueKey('settings-contact-developer'),
                      icon: Icons.support_agent_outlined,
                      title: S.contactDeveloper,
                      value: ContactDeveloper.subtitle,
                      onTap: () => unawaited(_contactDeveloper(context)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _contactDeveloper(BuildContext context) async {
    final opened = await ContactDeveloper.open();
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.contactDeveloperFailed),
        backgroundColor: AppColors.card,
      ),
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

const double _rowMinHeight = 72;
const double _rowPadH = AppSpacing.md;
const double _rowPadV = 14;
const double _badgeGap = 14;

/// Extra left inset for a dependent row; its badge lines up past the
/// parent's so the connector has room to turn.
const double _nestedInset = 28;

/// Center of the parent badge, where the connector line runs.
const double _connectorX = _rowPadH + AppIconBadge.size / 2;

const _titleStyle = TextStyle(
  fontFamily: AppFonts.dmSans,
  fontSize: 15,
  fontWeight: FontWeight.w700,
  color: Colors.white,
  height: 1.25,
);

const _subtitleStyle = TextStyle(
  fontFamily: AppFonts.dmSans,
  fontSize: 12.5,
  fontWeight: FontWeight.w500,
  color: AppColors.mutedText,
  height: 1.35,
);

/// Bold eyebrow header above one rounded card of rows separated by hairlines.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final joinsParent = child is _SwitchRow && child.nested;
      if (i > 0 && !joinsParent) {
        rows.add(
          const Divider(
            height: 1,
            thickness: 1,
            indent: _rowPadH + AppIconBadge.size + _badgeGap,
            color: AppColors.hairline,
          ),
        );
      }
      rows.add(child);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: 10),
            child: Text(
              title,
              style: AppTextStyles.eyebrowStyle(
                AppColors.labelText,
              ).copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Material(
            color: AppColors.card,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.lgBorder,
              side: BorderSide(color: AppColors.hairline, width: 1),
            ),
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }
}

/// Shared row layout: badge, title/subtitle, trailing control.
class _RowShell extends StatelessWidget {
  const _RowShell({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
    this.subtitle,
    this.active = false,
    this.nested = false,
    this.hasNestedChild = false,
    this.trailingPad = AppSpacing.sm,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback onTap;
  final bool active;
  final bool nested;
  final bool hasNestedChild;
  final double trailingPad;

  @override
  Widget build(BuildContext context) {
    final body = InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: _rowMinHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _rowPadH + (nested ? _nestedInset : 0),
            _rowPadV,
            trailingPad,
            _rowPadV,
          ),
          child: Row(
            children: [
              AppIconBadge(icon: icon, active: active),
              const SizedBox(width: _badgeGap),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: _titleStyle,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: _subtitleStyle,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              trailing,
            ],
          ),
        ),
      ),
    );
    if (!nested && !hasNestedChild) return body;
    return CustomPaint(
      painter: _ConnectorPainter(
        nested: nested,
        hasNestedChild: hasNestedChild,
      ),
      child: body,
    );
  }
}

/// Thin line tying a dependent row's badge back to its parent's badge.
class _ConnectorPainter extends CustomPainter {
  const _ConnectorPainter({required this.nested, required this.hasNestedChild});

  final bool nested;
  final bool hasNestedChild;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.strongBorder
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final midY = size.height / 2;
    if (hasNestedChild) {
      canvas.drawLine(
        Offset(_connectorX, midY + AppIconBadge.size / 2 + 4),
        Offset(_connectorX, size.height),
        paint,
      );
    }
    if (nested) {
      final path = Path()
        ..moveTo(_connectorX, 0)
        ..lineTo(_connectorX, midY - 8)
        ..quadraticBezierTo(_connectorX, midY, _connectorX + 8, midY)
        ..lineTo(_rowPadH + _nestedInset - 4, midY);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      old.nested != nested || old.hasNestedChild != hasNestedChild;
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.switchKey,
    this.subtitle,
    this.nested = false,
    this.hasNestedChild = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Key switchKey;

  /// Rendered as a sub-setting of the row above it.
  final bool nested;

  /// Draws the top of the connector down to a [nested] row below.
  final bool hasNestedChild;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: _RowShell(
        icon: icon,
        title: label,
        subtitle: subtitle,
        active: value,
        nested: nested,
        hasNestedChild: hasNestedChild,
        onTap: () => onChanged(!value),
        trailing: Switch(
          key: switchKey,
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.emerald,
          activeTrackColor: AppColors.emerald.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
  });

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      icon: icon,
      title: title,
      subtitle: value,
      onTap: onTap,
      trailingPad: AppSpacing.md - AppSpacing.xs,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.mutedText,
      ),
    );
  }
}

class _PillOrientationRow extends StatelessWidget {
  const _PillOrientationRow({
    required this.orientation,
    required this.onSelected,
  });

  final PillOrientation orientation;
  final ValueChanged<PillOrientation> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _rowPadH,
        _rowPadV,
        _rowPadH,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconBadge(
                icon: orientation == PillOrientation.vertical
                    ? Icons.view_agenda_outlined
                    : Icons.picture_in_picture_alt_outlined,
              ),
              const SizedBox(width: _badgeGap),
              Expanded(
                child: Text(
                  S.overlayPillOrientation,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: AppIconBadge.size + _badgeGap),
            child: Row(
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
          ),
        ],
      ),
    );
  }

  Widget _chip(PillOrientation value, String label) {
    final selected = orientation == value;
    return Material(
      color: selected
          ? AppColors.emerald.withValues(alpha: 0.18)
          : AppColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.smBorder,
        side: BorderSide(
          color: selected
              ? AppColors.emerald.withValues(alpha: 0.55)
              : Colors.transparent,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () => onSelected(value),
        borderRadius: AppRadius.smBorder,
        child: SizedBox(
          height: kMinTouchTarget + 4,
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
