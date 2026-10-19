import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'l10n.dart';
import 'log.dart';
import 'startup_language.dart';
import 'survey_api.dart';
import 'survey_store.dart';

/// Mandatory one-time market-research survey.
///
/// This is intentionally a full-screen root widget, not a dialog: there is no
/// barrier to tap outside and no AppBar back affordance. Android Back is
/// blocked by [PopScope]. It is shown only after onboarding has completed and
/// never on top of the native overlay.
class SurveyScreen extends StatefulWidget {
  const SurveyScreen({
    super.key,
    required this.onCompleted,
    this.api,
    this.prefs,
  });

  final VoidCallback onCompleted;

  /// Injectable for tests; production resolves ORLEN_API_URL.
  final SurveyApi? api;

  /// Injectable for tests; production uses SharedPreferences.getInstance().
  final SharedPreferences? prefs;

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  SurveyContinueChoice? _continueChoice;
  SurveyPriceChoice? _priceChoice;
  SurveyFeatureChoice? _featureChoice;

  bool _submitting = false;
  bool _submitted = false;
  bool _queued = false;
  String? _error;

  int get _answeredCount =>
      (_continueChoice == null ? 0 : 1) +
      (_priceChoice == null ? 0 : 1) +
      (_featureChoice == null ? 0 : 1);

  bool get _allAnswered => _answeredCount == 3;

  Future<SharedPreferences> _getPrefs() async =>
      widget.prefs ?? await SharedPreferences.getInstance();

  Future<void> _setLanguage(AppLang lang) async {
    if (lang == S.lang) return;
    S.setLang(lang);
    if (mounted) setState(() {});
    try {
      final prefs = await _getPrefs();
      await prefs.setString(kAppLanguagePrefsKey, lang.name);
    } catch (e) {
      logd('survey language save failed: $e', name: 'survey');
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_allAnswered) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final prefs = await _getPrefs();
      final installationId = await SurveyStore.installationId(prefs);
      final answers = SurveyAnswers(
        continueChoice: _continueChoice!,
        priceChoice: _priceChoice!,
        featureChoice: _featureChoice!,
      );
      final payload = answers.toJson(installationId);

      // Persist before setting the completion flag: a kill between these two
      // steps can show the survey again, but can never lose the answers.
      final saved = await SurveyStore.savePending(prefs, payload);
      if (!saved) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = S.surveyErrorLocal;
        });
        return;
      }
      final completed = await SurveyStore.markCompleted(prefs);
      if (!completed) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = S.surveyErrorLocal;
        });
        return;
      }

      final result = await SurveyStore.syncPending(
        prefs: prefs,
        api: widget.api,
        force: true,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitted = true;
        _queued = result == SurveySyncResult.queued;
      });
    } catch (e, s) {
      loge('survey submission failed', name: 'survey', error: e, stack: s);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = S.surveyErrorLocal;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      key: const ValueKey('survey-pop-scope'),
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.lg,
                  ),
                  child: _submitted ? _buildSuccess() : _buildForm(),
                ),
              ),
              _buildBottomAction(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                  Icons.insights_rounded,
                  color: AppColors.emerald,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'RateHelper',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.headlineStyle.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _SurveyLanguageSelector(
            current: S.lang,
            onSelected: (lang) => unawaited(_setLanguage(lang)),
          ),
          if (!_submitted) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              S.surveyProgress(_answeredCount),
              style: AppTextStyles.eyebrowStyle(AppColors.emerald),
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: AppRadius.xsBorder,
              child: LinearProgressIndicator(
                value: _answeredCount / 3,
                minHeight: 6,
                backgroundColor: AppColors.surfaceElevated,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.emerald,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          S.surveyTitle,
          style: T.dmSans24.copyWith(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.15,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SurveyIntroCard(text: S.surveyIntro),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _SurveyErrorBanner(message: _error!),
        ],
        const SizedBox(height: AppSpacing.lg),
        _QuestionCard(
          number: 1,
          title: S.surveyQuestion1,
          children: [
            _ChoiceTile(
              key: const ValueKey('survey-continue-yes'),
              label: S.surveyContinueYes,
              selected: _continueChoice == SurveyContinueChoice.yes,
              onTap: _submitting
                  ? null
                  : () => setState(() {
                      _continueChoice = SurveyContinueChoice.yes;
                    }),
            ),
            _ChoiceTile(
              key: const ValueKey('survey-continue-maybe'),
              label: S.surveyContinueMaybe,
              selected: _continueChoice == SurveyContinueChoice.maybe,
              onTap: _submitting
                  ? null
                  : () => setState(() {
                      _continueChoice = SurveyContinueChoice.maybe;
                    }),
            ),
            _ChoiceTile(
              key: const ValueKey('survey-continue-no'),
              label: S.surveyContinueNo,
              selected: _continueChoice == SurveyContinueChoice.no,
              onTap: _submitting
                  ? null
                  : () => setState(() {
                      _continueChoice = SurveyContinueChoice.no;
                    }),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _QuestionCard(
          number: 2,
          title: S.surveyQuestion2,
          children: [
            for (final price in SurveyPriceChoice.values)
              _ChoiceTile(
                key: ValueKey('survey-price-${price.name}'),
                label: _priceLabel(price),
                selected: _priceChoice == price,
                onTap: _submitting
                    ? null
                    : () => setState(() {
                        _priceChoice = price;
                      }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
        _QuestionCard(
          number: 3,
          title: S.surveyQuestion3,
          children: [
            for (final feature in SurveyFeatureChoice.values)
              _ChoiceTile(
                key: ValueKey('survey-feature-${feature.name}'),
                label: _featureLabel(feature),
                selected: _featureChoice == feature,
                onTap: _submitting
                    ? null
                    : () => setState(() {
                        _featureChoice = feature;
                      }),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: AppColors.mutedText,
              size: 16,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                S.surveyAnonymousNote,
                style: AppTextStyles.captionStyle.copyWith(height: 1.4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    final color = _queued ? AppColors.amber : AppColors.emerald;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(
              _queued ? Icons.cloud_off_rounded : Icons.check_circle_rounded,
              color: color,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _queued ? S.surveyQueuedTitle : S.surveySuccessTitle,
          style: T.dmSans24.copyWith(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.15,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _queued ? S.surveyQueuedBody : S.surveySuccessBody,
          style: AppTextStyles.bodyStyle.copyWith(
            color: AppColors.mutedText,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAction() {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_submitted && !_allAnswered) ...[
            Text(
              S.surveyAnswerRequired,
              textAlign: TextAlign.center,
              style: AppTextStyles.captionStyle.copyWith(height: 1.35),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          AppPrimaryButton(
            key: ValueKey(_submitted ? 'survey-continue' : 'survey-submit'),
            label: _submitted
                ? S.surveyContinue
                : (_submitting ? S.surveySubmitting : S.surveySubmit),
            icon: _submitted
                ? Icons.arrow_forward_rounded
                : (_submitting ? null : Icons.send_rounded),
            height: 54,
            color: AppColors.emerald,
            textColor: Colors.black,
            enabled: _submitted || (_allAnswered && !_submitting),
            onTap: () {
              if (_submitted) {
                widget.onCompleted();
              } else {
                unawaited(_submit());
              }
            },
          ),
        ],
      ),
    );
  }

  static String _priceLabel(SurveyPriceChoice choice) => switch (choice) {
    SurveyPriceChoice.five => S.surveyPrice5,
    SurveyPriceChoice.ten => S.surveyPrice10,
    SurveyPriceChoice.fifteen => S.surveyPrice15,
    SurveyPriceChoice.twenty => S.surveyPrice20,
    SurveyPriceChoice.twentyFivePlus => S.surveyPrice25Plus,
    SurveyPriceChoice.notPay => S.surveyPriceNotPay,
  };

  static String _featureLabel(SurveyFeatureChoice choice) => switch (choice) {
    SurveyFeatureChoice.overlayCounters => S.surveyFeatureOverlay,
    SurveyFeatureChoice.steeringNotifications => S.surveyFeatureSteering,
    SurveyFeatureChoice.earningsRental => S.surveyFeatureEarnings,
    SurveyFeatureChoice.fuelOrlen => S.surveyFeatureFuel,
    SurveyFeatureChoice.weeklyReports => S.surveyFeatureWeekly,
    SurveyFeatureChoice.other => S.surveyFeatureOther,
  };
}

class _SurveyLanguageSelector extends StatelessWidget {
  const _SurveyLanguageSelector({
    required this.current,
    required this.onSelected,
  });

  final AppLang current;
  final ValueChanged<AppLang> onSelected;

  static const _codes = {AppLang.tr: 'TR', AppLang.en: 'EN', AppLang.pl: 'PL'};

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: S.surveyLanguageSelector,
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
                      key: ValueKey('survey-lang-${lang.name}'),
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

class _SurveyIntroCard extends StatelessWidget {
  const _SurveyIntroCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdBorder,
        border: Border.all(color: AppColors.cardBorderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.emerald,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyStyle.copyWith(
                color: AppColors.mutedText,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SurveyErrorBanner extends StatelessWidget {
  const _SurveyErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.crimson.withValues(alpha: 0.10),
        borderRadius: AppRadius.mdBorder,
        border: Border.all(color: AppColors.crimson.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.crimson,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyStyle.copyWith(
                color: AppColors.crimson,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.number,
    required this.title,
    required this.children,
  });

  final int number;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdBorder,
        border: Border.all(color: AppColors.cardBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$number. $title',
            style: T.dmSans15.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppColors.emerald : AppColors.labelText;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? AppColors.emerald.withValues(alpha: 0.10)
            : AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdBorder,
          side: BorderSide(
            color: selected
                ? AppColors.emerald.withValues(alpha: 0.60)
                : AppColors.hairline,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdBorder,
          child: Container(
            constraints: const BoxConstraints(minHeight: kMinTouchTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + AppSpacing.xs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: accent,
                  size: 22,
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.bodyStyle.copyWith(
                      color: Colors.white,
                      height: 1.35,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
