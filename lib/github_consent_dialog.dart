import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'fonts.dart';
import 'l10n.dart';

/// First-launch question. Both actions have the same visual weight.
///
/// Pops `true` for automatic checks, `false` for manual only. The route
/// cannot be dismissed any other way, so startup cannot treat silence as a
/// yes.
class GithubConsentDialog extends StatelessWidget {
  const GithubConsentDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      backgroundColor: AppColors.surfaceElevated,
      side: const BorderSide(color: AppColors.hairline),
      minimumSize: const Size.fromHeight(56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(
        fontFamily: AppFonts.dmSans,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.hairline),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              S.githubConsentBody,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              style: buttonStyle,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.githubConsentAllow, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: buttonStyle,
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(S.githubConsentDeny, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
