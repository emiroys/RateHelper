import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'l10n.dart';
import 'models/event_model.dart';
import 'services/event_service.dart';

const _cardColor = AppColors.card;
const _emerald = AppColors.emerald;
const _crimson = AppColors.crimson;
const _amber = AppColors.amber;
final _cardBorder = kCardBorder;
final _cardRadius = kCardBorderRadius;

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
    EventService.clearCache();
    _loadEvents();
    await _eventsFuture;
  }

  String _relativeChip(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diffDays = day.difference(today).inDays;
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');

    if (diffDays == 0) {
      final diffMins = date.difference(now).inMinutes;
      if (diffMins > 0 && diffMins <= 180) {
        if (diffMins < 60) {
          return switch (S.lang) {
            AppLang.tr => '$diffMins DAKİKA İÇİNDE',
            AppLang.pl => 'ZA $diffMins MIN',
            AppLang.en => 'IN $diffMins MINS',
          };
        }
        final hours = (diffMins / 60).round();
        return switch (S.lang) {
          AppLang.tr => '$hours SAAT İÇİNDE',
          AppLang.pl => 'ZA $hours GODZ.',
          AppLang.en => 'IN $hours HOURS',
        };
      }
      return '${S.filterToday.toUpperCase()} $hh:$mm';
    }
    if (diffDays == 1) {
      return '${_tomorrowLabel()} $hh:$mm';
    }
    return date.formattedRadarChip;
  }

  String _tomorrowLabel() => switch (S.lang) {
        AppLang.tr => 'YARIN',
        AppLang.pl => 'JUTRO',
        AppLang.en => 'TOMORROW',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      appBar: AppBar(
        backgroundColor: AppColors.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _emerald.withValues(alpha: 0.15),
                borderRadius: AppRadius.smRadius,
                border: Border.all(color: _emerald.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.radar_rounded, color: _emerald, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.eventRadarTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.titleMd.copyWith(letterSpacing: 0.5),
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
              return const _ShimmerList();
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
              padding: const EdgeInsets.all(kPageInset),
              itemCount: events.length + 1,
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
      padding: const EdgeInsets.all(kPageInset),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: _cardRadius,
        border: _cardBorder,
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
                  style: T.bodyStrong,
                ),
                const SizedBox(height: 4),
                Text(
                  S.radarDemandSubtitle(count),
                  style: T.caption.copyWith(fontWeight: FontWeight.w500, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.all(kPageInset),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.15),
              borderRadius: AppRadius.smRadius,
              border: Border.all(color: _amber.withValues(alpha: 0.40)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.access_time_filled_rounded,
                  size: 14,
                  color: _amber,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _relativeChip(event.date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.labelStrong.copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: T.titleLg.copyWith(height: 1.3),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: surgeColor.withValues(alpha: 0.15),
              borderRadius: AppRadius.smRadius,
              border: Border.all(color: surgeColor.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: surgeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    surgeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.caption.copyWith(color: surgeColor, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, size: 16, color: _amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  event.venue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.label,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: AppEmptyState(
                icon: Icons.wifi_off_rounded,
                title: S.eventsReadError,
                description: message,
                actionLabel: S.refresh,
                onAction: () {
                  EventService.clearCache();
                  _loadEvents();
                },
                accent: _crimson,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: AppEmptyState(
                icon: Icons.event_busy_rounded,
                title: S.eventsEmptyTitle,
                description: message,
                accent: _amber,
              ),
            ),
          ],
        );
      },
    );
  }
}

extension on DateTime {
  String get formattedRadarChip {
    final day = this.day.toString().padLeft(2, '0');
    final month = this.month.toString().padLeft(2, '0');
    final year = this.year;
    final hour = this.hour.toString().padLeft(2, '0');
    final minute = this.minute.toString().padLeft(2, '0');
    return '$day.$month.$year • $hour:$minute';
  }
}

class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _emerald.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: _emerald.withValues(alpha: 0.30)),
            ),
            child: const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: _emerald,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            S.eventRadarTitle,
            style: T.caption.copyWith(
              color: AppColors.mutedText,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
