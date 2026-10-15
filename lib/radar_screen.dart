import 'package:flutter/material.dart';
import 'package:rate_helper/fonts.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_widgets.dart';
import 'l10n.dart';
import 'models/event_model.dart';
import 'services/event_service.dart';

const _cardColor = AppColors.surface;
const _emerald = AppColors.emerald;
const _crimson = AppColors.crimson;
const _amber = AppColors.amber;
final _cardBorder = Border.all(color: AppColors.cardBorderColor, width: 1);
final _cardRadius = AppRadius.mdBorder;

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  bool _loading = true;
  EventFetchResult _result = const EventFetchResult.notLoaded();

  @override
  void initState() {
    super.initState();
    _load(userAsked: false);
  }

  /// [userAsked] is the refresh button, pull-to-refresh, or Load events.
  /// Opening the screen passes false, so a disabled automatic fetch stays offline.
  Future<void> _load({required bool userAsked}) async {
    // The first call runs from initState, where _loading is already true and
    // setState is illegal. Later taps (refresh, Load events) do need a frame.
    if (!_loading && mounted) {
      setState(() => _loading = true);
    }
    final result = await EventService.loadForDisplay(userAsked: userAsked);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
    });
  }

  Future<void> _handleRefresh() => _load(userAsked: true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _emerald.withValues(alpha: 0.15),
                borderRadius: AppRadius.smBorder,
                border: Border.all(color: _emerald.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.radar_rounded, color: _emerald, size: 20),
            ),
            Expanded(
              child: Text(
                S.eventRadarTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: S.refresh,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.mutedText),
            onPressed: () => _load(userAsked: true),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final events = _result.events;
    if (_loading && events == null) {
      return _buildShimmerList();
    }
    if (events == null && _result.error != null) {
      return _buildErrorState(S.eventsReadError);
    }
    if (events == null) {
      return _buildNotLoadedState();
    }
    if (events.isEmpty) {
      return _buildEmptyState(S.eventsEmptyDesc);
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: _emerald,
      backgroundColor: _cardColor,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(16),
        itemCount: events.length + 1, // +1 for the top info header
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildRadarHeader(events.length, _result.fetchedAt);
          }
          final event = events[index - 1];
          return _buildFullWidthEventCard(event);
        },
      ),
    );
  }

  Widget _buildRadarHeader(int count, DateTime? fetchedAt) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.radarHeader, AppColors.dialog],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: _cardRadius,
        border: Border.all(color: _emerald.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _emerald.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.trending_up_rounded,
              color: _emerald,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.radarDemandTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  S.radarDemandSubtitle(count),
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.mutedText,
                    height: 1.3,
                  ),
                ),
                if (fetchedAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    S.eventsCacheAge(DateTime.now().difference(fetchedAt)),
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.labelText,
                      height: 1.3,
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

  String _formatEventHeadline(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = dt.year == tomorrow.year &&
        dt.month == tomorrow.month &&
        dt.day == tomorrow.day;

    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$h:$m';

    if (isToday) {
      return '${S.today.toUpperCase()} $timeStr';
    } else if (isTomorrow) {
      return '${S.tomorrow.toUpperCase()} $timeStr';
    } else {
      final d = dt.day.toString().padLeft(2, '0');
      final mo = dt.month.toString().padLeft(2, '0');
      return '$d.$mo • $timeStr';
    }
  }

  Widget _buildFullWidthEventCard(EventModel event) {
    Color surgeColor;
    String surgeLabel;
    switch (event.surgeLevel.toLowerCase()) {
      case 'high':
        surgeColor = _crimson;
        surgeLabel = S.surgeHigh;
        break;
      case 'medium':
        surgeColor = _amber;
        surgeLabel = S.surgeMedium;
        break;
      case 'low':
      default:
        surgeColor = _emerald;
        surgeLabel = S.surgeLow;
        break;
    }

    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: _emerald,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatEventHeadline(event.date),
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: _emerald,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: surgeColor.withValues(alpha: 0.15),
                  borderRadius: AppRadius.pillBorder,
                  border: Border.all(
                    color: surgeColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: surgeColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: surgeColor.withValues(alpha: 0.6),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      surgeLabel,
                      style: TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: surgeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 15,
                color: AppColors.mutedText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  event.venue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.mutedText,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) => const _ShimmerSkeletonCard(),
    );
  }

  Widget _buildNotLoadedState() {
    return AppEmptyState(
      icon: Icons.cloud_download_rounded,
      title: S.eventsNotLoadedTitle,
      description: S.eventsNotLoadedBody,
      actionLabel: S.loadEvents,
      onAction: () => _load(userAsked: true),
    );
  }

  Widget _buildEmptyState(String message) {
    return AppEmptyState(
      icon: Icons.event_busy_rounded,
      title: S.eventsEmptyTitle,
      description: message,
      actionLabel: S.refresh,
      onAction: () => _load(userAsked: true),
    );
  }

  Widget _buildErrorState(String message) {
    return AppEmptyState(
      icon: Icons.wifi_off_rounded,
      title: S.connectionError,
      description: message,
      accent: _crimson,
      actionLabel: S.reload,
      onAction: () => _load(userAsked: true),
    );
  }
}

class _ShimmerSkeletonCard extends StatefulWidget {
  const _ShimmerSkeletonCard();

  @override
  State<_ShimmerSkeletonCard> createState() => _ShimmerSkeletonCardState();
}

class _ShimmerSkeletonCardState extends State<_ShimmerSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _opacityAnimation = Tween<double>(begin: 0.25, end: 0.70).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: _cardRadius,
          border: _cardBorder,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 90,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    borderRadius: AppRadius.xsBorder,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 60,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    borderRadius: AppRadius.xsBorder,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 18,
              decoration: const BoxDecoration(
                color: Colors.white24,
                borderRadius: AppRadius.xsBorder,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: 180,
              height: 14,
              decoration: const BoxDecoration(
                color: Colors.white12,
                borderRadius: AppRadius.xsBorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

