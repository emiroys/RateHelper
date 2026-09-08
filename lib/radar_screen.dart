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
  late Future<List<EventModel>> _eventsFuture;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  void _loadEvents() {
    setState(() {
      _eventsFuture = EventService.fetchUpcomingEvents();
    });
  }

  Future<void> _handleRefresh() async {
    // Clear in-memory cache to force network re-fetch on manual pull-to-refresh
    EventService.clearCache();
    _loadEvents();
    await _eventsFuture;
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
            onPressed: () {
              EventService.clearCache();
              _loadEvents();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: _emerald,
        backgroundColor: _cardColor,
        child: FutureBuilder<List<EventModel>>(
          future: _eventsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildShimmerList();
            }

            if (snapshot.hasError) {
              return _buildErrorState(S.eventsReadError);
            }

            final events = snapshot.data ?? [];
            if (events.isEmpty) {
              return _buildEmptyState(S.eventsEmptyDesc);
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.all(16),
              itemCount: events.length + 1, // +1 for the top info header
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildRadarHeader(events.length);
                }
                final event = events[index - 1];
                return _buildFullWidthEventCard(event);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildRadarHeader(int count) {
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

  Widget _buildEmptyState(String message) {
    return AppEmptyState(
      icon: Icons.event_busy_rounded,
      title: S.eventsEmptyTitle,
      description: message,
      actionLabel: S.tryAgain,
      onAction: () {
        EventService.clearCache();
        _loadEvents();
      },
    );
  }

  Widget _buildErrorState(String message) {
    return AppEmptyState(
      icon: Icons.wifi_off_rounded,
      title: S.connectionError,
      description: message,
      accent: _crimson,
      actionLabel: S.reload,
      onAction: () {
        EventService.clearCache();
        _loadEvents();
      },
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

