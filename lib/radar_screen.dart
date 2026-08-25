import 'package:flutter/material.dart';
import 'package:rate_helper/fonts.dart';

import 'app_colors.dart';
import 'app_widgets.dart';
import 'l10n.dart';
import 'models/event_model.dart';
import 'services/event_service.dart';

const _cardColor = AppColors.elevated;
const _emerald = AppColors.emerald;
const _crimson = AppColors.crimson;
const _amber = AppColors.amber;
final _cardBorder = Border.all(color: AppColors.hairline, width: 1);
final _cardRadius = BorderRadius.circular(20);

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
                borderRadius: BorderRadius.circular(12),
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
      padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 14,
                      color: AppColors.mutedText,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        event.formattedDateTime,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.jetBrainsMono,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: surgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: surgeColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
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
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        surgeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: surgeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            event.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorderColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 18, color: _amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    event.venue,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.mutedText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.3, end: 0.7),
          duration: const Duration(milliseconds: 800),
          builder: (context, opacity, child) {
            return Opacity(
              opacity: opacity,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _cardColor,
                  border: _cardBorder,
                  borderRadius: _cardRadius,
                ),
                // Height comes from the placeholder blocks themselves; a fixed
                // height overflowed once the card border took its 2px.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 130,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        Container(
                          width: 110,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 200,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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
