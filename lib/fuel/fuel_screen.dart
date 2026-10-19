import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_colors.dart';
import '../app_spacing.dart';
import '../app_widgets.dart';
import '../earnings_models.dart';
import '../external_url.dart';
import '../fonts.dart';
import '../l10n.dart';
import '../log.dart';
import 'fuel_add_tab.dart';
import 'fuel_api.dart';
import 'fuel_platform.dart';
import 'fuel_prices.dart';
import 'fuel_receipts.dart';
import 'fuel_ui.dart';
import 'orlen_stations.dart';

/// A position older than this is fetched again when "Nearest" is tapped.
const Duration _positionMaxAge = Duration(minutes: 2);

/// Published prices older than this are shown with an amber age.
const Duration _stalePrice = Duration(hours: 24);

enum FuelTab { add, stations }

/// Home's "Fuel" button: receipt entry and Orlen stations under one title.
class FuelScreen extends StatefulWidget {
  const FuelScreen({
    super.key,
    required this.api,
    this.initialTab = FuelTab.add,
    this.locator = const NativeFuelLocator(),
    this.openUrl = ExternalUrl.open,
    this.now = DateTime.now,
    this.stations = krakowOrlenStations,
    this.saveReceipt = _saveReceipt,
    this.loadReceipts = _loadReceipts,
  });

  /// Null when `ORLEN_API_URL` is not set: stations, sorting by distance,
  /// and directions still work, prices and submissions do not.
  final FuelPriceApi? api;
  final FuelTab initialTab;
  final FuelLocator locator;
  final Future<bool> Function(String url) openUrl;
  final DateTime Function() now;
  final List<OrlenStation> stations;
  final Future<int> Function(double amount) saveReceipt;
  final Future<List<FuelReceipt>> Function() loadReceipts;

  static FuelScreen fromEnvironment({FuelTab initialTab = FuelTab.add}) =>
      FuelScreen(api: FuelPriceApi.fromEnvironment(), initialTab: initialTab);

  static Future<int> _saveReceipt(double amount) =>
      FuelReceiptStore.add(amount);

  static Future<List<FuelReceipt>> _loadReceipts() =>
      FuelReceiptStore.currentWeek();

  @override
  State<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends State<FuelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _lastTabIndex;

  @override
  void initState() {
    super.initState();
    _lastTabIndex = widget.initialTab.index;
    _tabs = TabController(
      length: FuelTab.values.length,
      vsync: this,
      initialIndex: _lastTabIndex,
    )..addListener(_onTabChanged);
  }

  /// Leave no text field focused when the driver changes tabs, so the
  /// keyboard cannot cover the Stations list or pop back up on Add.
  void _onTabChanged() {
    if (_tabs.index == _lastTabIndex) return;
    _lastTabIndex = _tabs.index;
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          S.quickFuelNavLabel,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: _FuelTabBar(controller: _tabs),
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabs,
          children: [
            FuelAddTab(
              saveReceipt: widget.saveReceipt,
              loadReceipts: widget.loadReceipts,
            ),
            FuelStationsTab(
              api: widget.api,
              locator: widget.locator,
              openUrl: widget.openUrl,
              now: widget.now,
              stations: widget.stations,
            ),
          ],
        ),
      ),
    );
  }
}

class _FuelTabBar extends StatelessWidget {
  const _FuelTabBar({required this.controller});

  final TabController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Container(
        height: 52,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.pillBorder,
          border: Border.all(color: AppColors.hairline),
        ),
        child: TabBar(
          controller: controller,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: AppRadius.pillBorder,
            border: Border.all(color: AppColors.strongBorder),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.mutedText,
          labelStyle: const TextStyle(
            fontFamily: AppFonts.dmSans,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
          splashBorderRadius: AppRadius.pillBorder,
          tabs: [
            Tab(
              key: const ValueKey('fuel-tab-add'),
              child: _TabLabel(Icons.add_circle_outline_rounded, S.fuelTabAdd),
            ),
            Tab(
              key: const ValueKey('fuel-tab-stations'),
              child: _TabLabel(Icons.place_outlined, S.fuelTabStations),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class FuelStationsTab extends StatefulWidget {
  const FuelStationsTab({
    super.key,
    required this.api,
    required this.locator,
    required this.openUrl,
    required this.now,
    required this.stations,
  });

  final FuelPriceApi? api;
  final FuelLocator locator;
  final Future<bool> Function(String url) openUrl;
  final DateTime Function() now;
  final List<OrlenStation> stations;

  @override
  State<FuelStationsTab> createState() => _FuelStationsTabState();
}

class _FuelStationsTabState extends State<FuelStationsTab>
    with AutomaticKeepAliveClientMixin {
  PriceBook _book = const {};
  DateTime? _fetchedAt;
  bool _loading = false;
  bool _loadFailed = false;

  FuelSort _sort = FuelSort.cheapest;
  GeoPoint? _position;
  DateTime? _positionAt;
  bool _locating = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrices(fromCache: true));
  }

  Future<void> _loadPrices({bool fromCache = false}) async {
    if (fromCache) {
      final cached = await FuelPriceCache.read();
      if (cached != null && mounted) {
        setState(() {
          _book = cached.book;
          _fetchedAt = cached.fetchedAt;
        });
      }
    }
    final api = widget.api;
    if (api == null || _loading || !mounted) return;
    setState(() => _loading = true);
    try {
      final book = await api.fetchPrices();
      final at = widget.now();
      await FuelPriceCache.write(book, at);
      if (!mounted) return;
      setState(() {
        _book = book;
        _fetchedAt = at;
        _loadFailed = false;
      });
    } catch (e, s) {
      loge('fuel prices fetch failed', name: 'fuel', error: e, stack: s);
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectSort(FuelSort sort) async {
    if (sort != FuelSort.nearest) {
      setState(() => _sort = sort);
      return;
    }
    final at = _positionAt;
    final fresh =
        _position != null &&
        at != null &&
        widget.now().difference(at) < _positionMaxAge;
    if (fresh && _sort != FuelSort.nearest) {
      setState(() => _sort = sort);
      return;
    }
    if (_locating) return;
    setState(() => _locating = true);
    final result = await widget.locator.currentPosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (result.position != null) {
        _position = result.position;
        _positionAt = widget.now();
        _sort = FuelSort.nearest;
      }
    });
    final failure = result.failure;
    if (failure != null) _showLocationFailure(failure);
  }

  void _showLocationFailure(LocationFailure failure) {
    final message = switch (failure) {
      LocationFailure.denied => S.fuelLocationDenied,
      LocationFailure.disabled => S.fuelLocationDisabled,
      LocationFailure.unavailable => S.fuelLocationUnavailable,
    };
    showFuelSnack(
      context,
      message,
      action: failure == LocationFailure.denied
          ? SnackBarAction(
              label: S.openSettings,
              textColor: AppColors.actionAccent,
              onPressed: () => unawaited(widget.locator.openAppSettings()),
            )
          : null,
    );
  }

  Future<void> _openDirections(OrlenStation station) async {
    final app = await showModalBottomSheet<NavApp>(
      context: context,
      backgroundColor: AppColors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => _NavPickerSheet(station: station),
    );
    if (app == null || !mounted) return;
    final opened = await widget.openUrl(navigationUrl(station, app));
    if (!opened && mounted) showFuelSnack(context, S.fuelOpenNavFailed);
  }

  Future<void> _updatePrice(OrlenStation station) async {
    final api = widget.api;
    if (api == null) {
      showFuelSnack(context, S.fuelNotConfigured);
      return;
    }
    final submission = await showModalBottomSheet<PriceSubmission>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => _PriceForm(
        station: station,
        initialFuel: station.sellsLpg ? FuelType.lpg : FuelType.pb95,
      ),
    );
    if (submission == null || !mounted) return;
    final outcome = await api.submit(submission);
    if (!mounted) return;
    showFuelSnack(context, switch (outcome) {
      SubmitOutcome.pending => S.fuelSubmitted,
      SubmitOutcome.invalid => S.fuelSubmitInvalid,
      SubmitOutcome.rateLimited => S.fuelSubmitRateLimited,
      SubmitOutcome.failed => S.fuelSubmitFailed,
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final views = sortStations(
      stations: widget.stations,
      prices: _book,
      sort: _sort,
      position: _position,
    );
    final now = widget.now();
    final first = views.isEmpty ? null : views.first;
    final hasHero =
        first != null &&
        switch (_sort) {
          FuelSort.cheapest =>
            first.prices.pb95 != null || first.prices.lpg != null,
          FuelSort.nearest => first.distanceKm != null,
        };
    final rest = hasHero ? views.skip(1).toList() : views;
    Widget card(StationView view) => _StationCard(
      key: ValueKey('fuel-station-${view.station.id}'),
      view: view,
      now: now,
      onDirections: () => unawaited(_openDirections(view.station)),
      onUpdate: () => unawaited(_updatePrice(view.station)),
    );

    final list = ListView.builder(
      key: const ValueKey('fuel-station-list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      itemCount: rest.length + (hasHero ? 1 : 0) + 1,
      itemBuilder: (context, index) {
        if (hasHero) {
          if (index == 0) {
            return _HeroCard(
              key: ValueKey('fuel-station-${first.station.id}'),
              view: first,
              sort: _sort,
              now: now,
              onDirections: () => unawaited(_openDirections(first.station)),
              onUpdate: () => unawaited(_updatePrice(first.station)),
            );
          }
          index--;
        }
        if (index == rest.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 14,
                  color: AppColors.mutedText,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    S.fuelCommunityNote,
                    textAlign: TextAlign.center,
                    style: fuelMutedStyle,
                  ),
                ),
              ],
            ),
          );
        }
        return card(rest[index]);
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: _SortBar(
            sort: _sort,
            locating: _locating,
            onSelect: (sort) => unawaited(_selectSort(sort)),
          ),
        ),
        _statusRow(now),
        Expanded(
          child: widget.api == null
              ? list
              : RefreshIndicator(
                  color: AppColors.emerald,
                  backgroundColor: AppColors.card,
                  onRefresh: _loadPrices,
                  child: list,
                ),
        ),
      ],
    );
  }

  Widget _statusRow(DateTime now) {
    final (IconData icon, Color color) = _locating
        ? (Icons.my_location_rounded, AppColors.actionAccent)
        : widget.api == null
        ? (Icons.cloud_off_rounded, AppColors.mutedText)
        : _loadFailed
        ? (Icons.error_outline_rounded, AppColors.amber)
        : (Icons.check_circle_outline_rounded, AppColors.emerald);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, AppSpacing.xs, 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusLine(now),
              key: const ValueKey('fuel-status'),
              style: fuelMutedStyle.copyWith(
                color: _loadFailed ? AppColors.amber : AppColors.mutedText,
              ),
            ),
          ),
          if (widget.api != null)
            IconButton(
              key: const ValueKey('fuel-refresh'),
              tooltip: S.refresh,
              onPressed: _loading ? null : () => unawaited(_loadPrices()),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, color: Colors.white),
            )
          else
            const SizedBox(height: kMinTouchTarget),
        ],
      ),
    );
  }

  String _statusLine(DateTime now) {
    if (_locating) return S.fuelLocating;
    if (widget.api == null) return S.fuelNotConfigured;
    final parts = <String>[
      if (_loadFailed) S.fuelLoadFailed,
      if (_fetchedAt != null)
        S.fuelPricesFetchedAgo(S.fuelUpdatedAgo(now.difference(_fetchedAt!))),
    ];
    return parts.join(' · ');
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({
    required this.sort,
    required this.locating,
    required this.onSelect,
  });

  final FuelSort sort;
  final bool locating;
  final ValueChanged<FuelSort> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget segment(FuelSort value, String key, String emoji, String label) {
      return Expanded(
        child: _SortSegment(
          key: ValueKey(key),
          emoji: emoji,
          label: label,
          selected: sort == value,
          busy: value == FuelSort.nearest && locating,
          onTap: () => onSelect(value),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgBorder,
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: [
          segment(
            FuelSort.cheapest,
            'fuel-sort-cheapest',
            '💰',
            S.fuelSortCheapest,
          ),
          segment(
            FuelSort.nearest,
            'fuel-sort-nearest',
            '📍',
            S.fuelSortNearest,
          ),
        ],
      ),
    );
  }
}

class _SortSegment extends StatelessWidget {
  const _SortSegment({
    super.key,
    required this.emoji,
    required this.label,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.emerald.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: AppRadius.mdBorder,
          border: Border.all(
            color: selected
                ? AppColors.emerald.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.mdBorder,
            onTap: onTap,
            child: SizedBox(
              height: 62,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 22,
                      child: busy
                          ? const Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.emerald,
                                ),
                              ),
                            )
                          : Text(emoji, style: const TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: selected ? AppColors.emerald : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DistancePill extends StatelessWidget {
  const _DistancePill(this.km);

  final double km;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.actionAccent.withValues(alpha: 0.14),
        borderRadius: AppRadius.pillBorder,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.near_me_rounded,
            size: 13,
            color: AppColors.actionAccent,
          ),
          const SizedBox(width: 4),
          Text(
            formatDistanceKm(km),
            style: const TextStyle(
              fontFamily: AppFonts.jetBrainsMono,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.actionAccent,
            ),
          ),
        ],
      ),
    );
  }
}

String? _ageText(FuelPrice? price, DateTime now) =>
    price == null ? null : S.fuelUpdatedAgo(now.difference(price.updatedAt));

bool _isStale(FuelPrice? price, DateTime now) =>
    price != null && now.difference(price.updatedAt) > _stalePrice;

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    super.key,
    required this.view,
    required this.sort,
    required this.now,
    required this.onDirections,
    required this.onUpdate,
  });

  final StationView view;
  final FuelSort sort;
  final DateTime now;
  final VoidCallback onDirections;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final station = view.station;
    final cheapest = sort == FuelSort.cheapest;
    final accent = cheapest ? AppColors.emerald : AppColors.actionAccent;
    final distance = view.distanceKm;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: FuelCard(
        accent: accent,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  cheapest
                      ? Icons.workspace_premium_rounded
                      : Icons.near_me_rounded,
                  size: 16,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    cheapest ? S.fuelBestCheapest : S.fuelBestNearest,
                    style: fuelEyebrowStyle.copyWith(color: accent),
                  ),
                ),
                if (distance != null) _DistancePill(distance),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              station.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: fuelTitleStyle.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 2),
            Text(
              station.address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: fuelMutedStyle,
            ),
            const SizedBox(height: 14),
            _PriceRow(view: view, now: now, highlighted: cheapest),
            const SizedBox(height: 14),
            _CardActions(
              station: station,
              primary: true,
              onDirections: onDirections,
              onUpdate: onUpdate,
            ),
          ],
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.view,
    required this.now,
    this.highlighted = false,
  });

  final StationView view;
  final DateTime now;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final type in FuelType.values) ...[
          if (type != FuelType.values.first)
            const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _PriceTile(
              label: type == FuelType.pb95 ? S.fuelPb95 : S.fuelLpg,
              price: view.prices.of(type),
              sold: view.station.sells(type),
              now: now,
              highlighted: highlighted,
            ),
          ),
        ],
      ],
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    super.key,
    required this.view,
    required this.now,
    required this.onDirections,
    required this.onUpdate,
  });

  final StationView view;
  final DateTime now;
  final VoidCallback onDirections;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final station = view.station;
    final distance = view.distanceKm;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FuelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: fuelTitleStyle.copyWith(fontSize: 17),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        station.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: fuelMutedStyle,
                      ),
                    ],
                  ),
                ),
                if (distance != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _DistancePill(distance),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _PriceRow(view: view, now: now),
            const SizedBox(height: 12),
            _CardActions(
              station: station,
              primary: false,
              onDirections: onDirections,
              onUpdate: onUpdate,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardActions extends StatelessWidget {
  const _CardActions({
    required this.station,
    required this.primary,
    required this.onDirections,
    required this.onUpdate,
  });

  final OrlenStation station;

  /// The hero gets a filled Directions button.
  final bool primary;
  final VoidCallback onDirections;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: primary
              ? AppPrimaryButton(
                  key: ValueKey('fuel-directions-${station.id}'),
                  label: S.fuelDirections,
                  icon: Icons.navigation_rounded,
                  color: AppColors.actionAccent,
                  textColor: Colors.black,
                  height: 56,
                  onTap: onDirections,
                )
              : AppSecondaryButton(
                  key: ValueKey('fuel-directions-${station.id}'),
                  label: S.fuelDirections,
                  icon: Icons.navigation_rounded,
                  accentColor: AppColors.actionAccent,
                  height: 56,
                  onTap: onDirections,
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          flex: 3,
          child: AppSecondaryButton(
            key: ValueKey('fuel-update-${station.id}'),
            label: S.fuelUpdatePrice,
            icon: Icons.edit_note_rounded,
            height: 56,
            onTap: onUpdate,
          ),
        ),
      ],
    );
  }
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({
    required this.label,
    required this.price,
    required this.sold,
    required this.now,
    required this.highlighted,
  });

  final String label;
  final FuelPrice? price;
  final bool sold;
  final DateTime now;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final value = price;
    final hasValue = value != null && sold;
    final main = !sold
        ? S.fuelNoLpg
        : value == null
        ? S.fuelNoPrice
        : '${formatPrice(value.price)} zł';
    final age = hasValue ? _ageText(value, now) : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.mdBorder,
        border: Border.all(
          color: highlighted && hasValue
              ? AppColors.emerald.withValues(alpha: 0.45)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: fuelEyebrowStyle.copyWith(fontSize: 11.5)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              main,
              maxLines: 1,
              style: TextStyle(
                fontFamily: hasValue ? AppFonts.jetBrainsMono : AppFonts.dmSans,
                fontSize: hasValue ? 22 : 15,
                fontWeight: FontWeight.w800,
                color: !hasValue
                    ? AppColors.mutedText
                    : highlighted
                    ? AppColors.emerald
                    : Colors.white,
              ),
            ),
          ),
          if (age != null)
            Text(
              age,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: fuelMutedStyle.copyWith(
                fontSize: 11.5,
                color: _isStale(value, now)
                    ? AppColors.amber
                    : AppColors.mutedText,
              ),
            ),
        ],
      ),
    );
  }
}

class _NavPickerSheet extends StatelessWidget {
  const _NavPickerSheet({required this.station});

  final OrlenStation station;

  @override
  Widget build(BuildContext context) {
    Widget option(NavApp app, String label, IconData icon) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: AppPrimaryButton(
          key: ValueKey('fuel-nav-${app.name}'),
          label: label,
          icon: icon,
          height: 64,
          color: AppColors.surfaceElevated,
          onTap: () => Navigator.of(context).pop(app),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            Text(S.fuelNavigateWith, style: fuelLabelStyle),
            const SizedBox(height: 4),
            Text(station.name, style: fuelTitleStyle.copyWith(fontSize: 18)),
            Text(station.address, style: fuelMutedStyle),
            const SizedBox(height: AppSpacing.md),
            option(NavApp.googleMaps, S.fuelGoogleMaps, Icons.map_rounded),
            option(NavApp.waze, S.fuelWaze, Icons.directions_car_rounded),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _PriceForm extends StatefulWidget {
  const _PriceForm({required this.station, required this.initialFuel});

  final OrlenStation station;
  final FuelType initialFuel;

  @override
  State<_PriceForm> createState() => _PriceFormState();
}

class _PriceFormState extends State<_PriceForm> {
  final _controller = TextEditingController();
  late FuelType _fuel = widget.initialFuel;
  PriceInputError? _error;
  bool _attempted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectFuel(FuelType fuel) {
    setState(() {
      _fuel = fuel;
      if (_attempted) _error = validatePriceInput(_controller.text, fuel).error;
    });
  }

  void _submit() {
    final input = validatePriceInput(_controller.text, _fuel);
    if (!input.isValid) {
      setState(() {
        _attempted = true;
        _error = input.error;
      });
      return;
    }
    Navigator.of(context).pop(
      PriceSubmission(
        stationId: widget.station.id,
        fuel: _fuel,
        price: input.value!,
      ),
    );
  }

  String? get _errorText => switch (_error) {
    null => null,
    PriceInputError.empty => S.fuelPriceEmpty,
    PriceInputError.notANumber => S.fuelPriceNotANumber,
    PriceInputError.tooPrecise => S.fuelPriceTooPrecise,
    PriceInputError.outOfRange => S.fuelPriceOutOfRange(
      formatPrice(priceRange(_fuel).$1),
      formatPrice(priceRange(_fuel).$2),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              Text(S.fuelUpdatePrice, style: fuelLabelStyle),
              const SizedBox(height: 4),
              Text(station.name, style: fuelTitleStyle.copyWith(fontSize: 18)),
              Text(station.address, style: fuelMutedStyle),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: FuelPillButton(
                      key: const ValueKey('fuel-form-pb95'),
                      label: S.fuelPb95Long,
                      selected: _fuel == FuelType.pb95,
                      color: AppColors.emerald,
                      height: 56,
                      onTap: () => _selectFuel(FuelType.pb95),
                    ),
                  ),
                  if (station.sellsLpg) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FuelPillButton(
                        key: const ValueKey('fuel-form-lpg'),
                        label: S.fuelLpgLong,
                        selected: _fuel == FuelType.lpg,
                        color: AppColors.emerald,
                        height: 56,
                        onTap: () => _selectFuel(FuelType.lpg),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('fuel-form-price'),
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  LengthLimitingTextInputFormatter(5),
                ],
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_attempted) {
                    setState(() {
                      _error = validatePriceInput(
                        _controller.text,
                        _fuel,
                      ).error;
                    });
                  }
                },
                style: const TextStyle(
                  fontFamily: AppFonts.jetBrainsMono,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  labelText: S.fuelPriceLabel,
                  hintText: _fuel == FuelType.lpg ? '3.19' : '6.29',
                  suffixText: 'zł',
                  errorText: _errorText,
                  errorMaxLines: 2,
                  filled: true,
                  fillColor: AppColors.surfaceElevated,
                  border: const OutlineInputBorder(
                    borderRadius: AppRadius.mdBorder,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(S.fuelSubmitPrompt, style: fuelMutedStyle),
              const SizedBox(height: AppSpacing.md),
              AppPrimaryButton(
                key: const ValueKey('fuel-form-submit'),
                label: S.fuelSubmit,
                icon: Icons.send_rounded,
                height: 60,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
