import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'fonts.dart';
import 'l10n.dart';
import 'services/update_service.dart';

/// Shows the update prompt and starts the cooldown, so a dismissed dialog
/// stays dismissed across cold starts.
Future<void> showUpdatePrompt(
  BuildContext context,
  UpdateCheckResult result,
) async {
  final info = result.info;
  if (info == null) return;

  await UpdateService.instance.markPrompted();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: !info.mandatory,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    builder: (_) => _UpdateDialog(current: result.current, info: info),
  );
}

void _showUpdateSnack(ScaffoldMessengerState? messenger, String message) {
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            fontSize: AppTextStyles.body,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
        duration: const Duration(seconds: 3),
      ),
    );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.current, required this.info});

  final AppVersion current;
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _launching = false;

  Future<void> _startDownload() async {
    if (_launching) return;
    setState(() => _launching = true);

    // Captured before the await: the dialog may be gone by the time the
    // browser hand-off resolves.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);

    final launched = await UpdateService.instance.launchDownload(widget.info);

    if (!mounted) return;
    setState(() => _launching = false);

    if (launched) {
      // A mandatory release keeps the dialog up: the driver comes back from
      // the browser to the same blocking prompt until the APK is installed.
      if (!widget.info.mandatory) navigator.pop();
      return;
    }
    _showUpdateSnack(messenger, S.updateLaunchFailed);
  }

  Future<void> _skip() async {
    await UpdateService.instance.skipVersion(widget.info.displayVersion);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final notes = info.notes;

    return PopScope(
      canPop: !info.mandatory,
      child: Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.mdBorder,
          side: BorderSide(color: AppColors.hairline, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.emerald.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.system_update_alt_rounded,
                      color: AppColors.emerald,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + 4),
                  Expanded(
                    child: Text(
                      info.mandatory
                          ? S.updateMandatoryTitle
                          : S.updateAvailableTitle,
                      style: AppTextStyles.sectionTitleStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _VersionDelta(
                current: widget.current,
                latest: info.displayVersion,
              ),
              if (notes != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(notes, style: AppTextStyles.bodyStyle),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                S.updateBrowserHint,
                style: AppTextStyles.captionStyle.copyWith(height: 1.4),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: _launching
                    ? const _LaunchingButton()
                    : AppPrimaryButton(
                        label: S.updateNow,
                        icon: Icons.download_rounded,
                        onTap: _startDownload,
                      ),
              ),
              if (!info.mandatory) ...[
                const SizedBox(height: AppSpacing.sm + 4),
                Row(
                  children: [
                    Expanded(
                      child: AppSecondaryButton(
                        label: S.updateLater,
                        onTap: _launching
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppSecondaryButton(
                        label: S.updateSkipVersion,
                        accentColor: AppColors.mutedText,
                        onTap: _launching ? null : _skip,
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
}

class _LaunchingButton extends StatelessWidget {
  const _LaunchingButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.mdBorder,
      ),
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppColors.emerald,
        ),
      ),
    );
  }
}

/// `Yüklü 5.0.0  →  Yeni v5.0.1`, so the driver can see exactly what changes.
class _VersionDelta extends StatelessWidget {
  const _VersionDelta({required this.current, required this.latest});

  final AppVersion current;
  final String latest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 4,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.smBorder,
      ),
      child: Row(
        children: [
          Expanded(
            child: _labelledVersion(
              S.updateInstalledLabel,
              current.label,
              AppColors.mutedText,
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            size: 18,
            color: AppColors.disabledText,
          ),
          Expanded(
            child: _labelledVersion(
              S.updateLatestLabel,
              latest,
              AppColors.emerald,
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelledVersion(
    String label,
    String value,
    Color valueColor, {
    bool alignEnd = false,
  }) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTextStyles.eyebrowStyle(AppColors.disabledText),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.tabularMonospace(
            fontSize: AppTextStyles.body,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Footer tile next to the version badge: manual check with its own spinner,
/// bypassing the startup cooldown and any skipped version.
class UpdateCheckTile extends StatefulWidget {
  const UpdateCheckTile({super.key, this.versionLabel});

  /// Installed version shown as a trailing badge (e.g. `5.0.0`).
  final String? versionLabel;

  @override
  State<UpdateCheckTile> createState() => _UpdateCheckTileState();
}

class _UpdateCheckTileState extends State<UpdateCheckTile> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);

    final messenger = ScaffoldMessenger.maybeOf(context);
    final result =
        await UpdateService.instance.check(languageCode: S.lang.name);

    if (!mounted) return;
    setState(() => _checking = false);

    switch (result.status) {
      case UpdateStatus.available:
        await showUpdatePrompt(context, result);
      case UpdateStatus.upToDate:
        _showUpdateSnack(messenger, S.updateUpToDate);
      case UpdateStatus.unreachable:
        _showUpdateSnack(messenger, S.updateUnreachable);
      case UpdateStatus.disabled:
        _showUpdateSnack(messenger, S.updateDisabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final versionLabel = widget.versionLabel;

    return Material(
      color: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
        side: BorderSide(color: AppColors.cardBorderColor, width: 1),
      ),
      child: InkWell(
        onTap: _checking ? null : _check,
        borderRadius: AppRadius.mdBorder,
        splashColor: AppColors.emerald.withValues(alpha: 0.12),
        highlightColor: AppColors.emerald.withValues(alpha: 0.06),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                size: 20,
                color: _checking ? AppColors.disabledText : AppColors.emerald,
              ),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Text(
                  _checking ? S.updateChecking : S.updateCheckAction,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: AppTextStyles.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.mutedText,
                  ),
                ),
              ),
              if (_checking)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.emerald,
                  ),
                )
              else if (versionLabel != null)
                Text(
                  'v$versionLabel',
                  style: AppTextStyles.tabularMonospace(
                    fontSize: AppTextStyles.caption,
                    fontWeight: FontWeight.w600,
                    color: AppColors.disabledText,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
