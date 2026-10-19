import 'dart:async';

import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';
import '../app_widgets.dart';
import '../earnings_models.dart';
import '../earnings_screen.dart';
import '../fonts.dart';
import '../l10n.dart';
import '../log.dart';
import 'fuel_ui.dart';

const List<int> _quickAmounts = [50, 100, 150, 200];

/// Quick fuel receipt entry (the old Home dialog) plus this week's receipts.
/// With split on, only the driver's share is saved.
class FuelAddTab extends StatefulWidget {
  const FuelAddTab({
    super.key,
    required this.saveReceipt,
    required this.loadReceipts,
  });

  /// Returns how many receipts this week holds after the save.
  final Future<int> Function(double amount) saveReceipt;
  final Future<List<FuelReceipt>> Function() loadReceipts;

  @override
  State<FuelAddTab> createState() => _FuelAddTabState();
}

class _FuelAddTabState extends State<FuelAddTab>
    with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  bool _splitOn = false;
  int _people = kFuelSplitMinPeople;
  bool _saving = false;
  List<FuelReceipt> _receipts = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
    unawaited(_loadReceipts());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadReceipts() async {
    try {
      final receipts = await widget.loadReceipts();
      if (mounted) setState(() => _receipts = receipts);
    } catch (e, s) {
      loge('fuel receipts load failed', name: 'fuel', error: e, stack: s);
    }
  }

  double? get _total {
    final value = parsePlnAmount(_ctrl.text);
    return value != null && value.isFinite && value > 0 ? value : null;
  }

  double? get _amountToSave {
    final total = _total;
    if (total == null) return null;
    return _splitOn ? fuelSplitShare(total, _people) : total;
  }

  void _setQuickAmount(int value) {
    final text = '$value';
    _ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _save() async {
    final amount = _amountToSave;
    if (amount == null || _saving) return;
    setState(() => _saving = true);
    FocusScope.of(context).unfocus();
    try {
      final count = await widget.saveReceipt(amount);
      if (!mounted) return;
      _ctrl.clear();
      setState(() {
        _splitOn = false;
        _people = kFuelSplitMinPeople;
      });
      showFuelSnack(context, S.fuelAddedConfirmation(formatPln(amount), count));
      await _loadReceipts();
    } catch (e, s) {
      loge('fuel receipt save failed', name: 'fuel', error: e, stack: s);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final amount = _amountToSave;
    return ListView(
      key: const ValueKey('fuel-add-list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        FuelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(S.amountPaidLabel, style: fuelLabelStyle),
              TextField(
                key: const ValueKey('fuel-add-amount'),
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [PolishCurrencyInputFormatter()],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_save()),
                style: const TextStyle(
                  fontFamily: AppFonts.jetBrainsMono,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                cursorColor: AppColors.actionAccent,
                decoration: const InputDecoration(
                  hintText: '0',
                  hintStyle: TextStyle(color: AppColors.disabledText),
                  suffixText: 'PLN',
                  suffixStyle: TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.actionAccent,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  for (var i = 0; i < _quickAmounts.length; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FuelPillButton(
                        key: ValueKey('fuel-add-quick-${_quickAmounts[i]}'),
                        label: '${_quickAmounts[i]}',
                        selected: _total == _quickAmounts[i].toDouble(),
                        onTap: () => _setQuickAmount(_quickAmounts[i]),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _splitSection(),
              const SizedBox(height: AppSpacing.md),
              AppPrimaryButton(
                key: const ValueKey('fuel-add-submit'),
                label: amount == null
                    ? S.add
                    : S.fuelAddButton(formatPln(amount)),
                icon: Icons.add_rounded,
                color: AppColors.actionAccent,
                textColor: Colors.black,
                height: 60,
                enabled: amount != null && !_saving,
                onTap: () => unawaited(_save()),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _weekSection(),
      ],
    );
  }

  Widget _splitSection() {
    final share = _total == null ? null : fuelSplitShare(_total!, _people);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: _splitOn
            ? AppColors.actionAccent.withValues(alpha: 0.08)
            : AppColors.surfaceElevated,
        borderRadius: AppRadius.mdBorder,
        border: Border.all(
          color: _splitOn
              ? AppColors.actionAccent.withValues(alpha: 0.4)
              : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: AppRadius.mdBorder,
            onTap: () => setState(() => _splitOn = !_splitOn),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.groups_rounded,
                    color: _splitOn
                        ? AppColors.actionAccent
                        : AppColors.mutedText,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(S.fuelSplitToggle, style: fuelTitleStyle),
                        Text(S.fuelSplitHint, style: fuelMutedStyle),
                      ],
                    ),
                  ),
                  Switch(
                    key: const ValueKey('fuel-add-split'),
                    value: _splitOn,
                    onChanged: (on) => setState(() => _splitOn = on),
                    activeThumbColor: AppColors.actionAccent,
                    activeTrackColor: AppColors.actionAccent.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_splitOn)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          S.fuelSplitPeopleLabel,
                          style: fuelMutedStyle.copyWith(fontSize: 14),
                        ),
                      ),
                      _StepButton(
                        key: const ValueKey('fuel-add-people-minus'),
                        icon: Icons.remove_rounded,
                        enabled: _people > kFuelSplitMinPeople,
                        onTap: () => setState(() => _people--),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$_people',
                          key: const ValueKey('fuel-add-people'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: AppFonts.jetBrainsMono,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      _StepButton(
                        key: const ValueKey('fuel-add-people-plus'),
                        icon: Icons.add_rounded,
                        enabled: _people < kFuelSplitMaxPeople,
                        onTap: () => setState(() => _people++),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    S.fuelSplitYourShare(
                      share == null ? '—' : formatPln(share),
                    ),
                    style: TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: share == null
                          ? AppColors.mutedText
                          : AppColors.actionAccent,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _weekSection() {
    final total = _receipts.fold<double>(0, (sum, r) => sum + r.amountPaid);
    final newestFirst = [..._receipts]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: 10),
          child: Row(
            children: [
              Text(S.fuelThisWeek, style: fuelEyebrowStyle),
              const SizedBox(width: AppSpacing.sm),
              if (_receipts.isNotEmpty)
                Expanded(
                  child: Text(
                    S.fuelWeekSummary(_receipts.length, formatPln(total)),
                    key: const ValueKey('fuel-add-week-summary'),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: fuelMutedStyle.copyWith(
                      color: AppColors.labelText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        FuelCard(
          padding: EdgeInsets.zero,
          child: newestFirst.isEmpty
              ? Padding(
                  padding: AppSpacing.cardPadding,
                  child: Text(S.noFuelReceipts, style: fuelMutedStyle),
                )
              : Column(
                  children: [
                    for (var i = 0; i < newestFirst.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          thickness: 1,
                          indent: 56,
                          color: AppColors.hairline,
                        ),
                      _ReceiptRow(receipt: newestFirst[i]),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceElevated,
      shape: const CircleBorder(side: BorderSide(color: AppColors.hairline)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: kMinTouchTarget,
          height: kMinTouchTarget,
          child: Icon(
            icon,
            color: enabled ? Colors.white : AppColors.disabledText,
          ),
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.receipt});

  final FuelReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.actionAccent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_gas_station_rounded,
              size: 16,
              color: AppColors.actionAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              S.formatReceiptTimestamp(receipt.timestamp),
              style: fuelMutedStyle.copyWith(
                fontSize: 14,
                color: AppColors.labelText,
              ),
            ),
          ),
          Text(
            '${formatPln(receipt.amountPaid)} PLN',
            style: const TextStyle(
              fontFamily: AppFonts.jetBrainsMono,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
