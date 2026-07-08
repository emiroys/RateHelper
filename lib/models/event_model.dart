import '../l10n.dart';

class EventModel {
  final String title;
  final String venue;
  final DateTime date;
  final String surgeLevel;

  const EventModel({
    required this.title,
    required this.venue,
    required this.date,
    required this.surgeLevel,
  });

  factory EventModel.fromJson(Map<String, dynamic> json) {
    return EventModel(
      title: json['title']?.toString() ?? S.unknownEvent,
      venue: json['venue']?.toString() ?? S.unknownVenue,
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      surgeLevel: json['surgeLevel']?.toString() ?? 'Low',
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'venue': venue,
    'date': date.toIso8601String(),
    'surgeLevel': surgeLevel,
  };

  String get formattedDateTime {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.$year • $hour:$minute';
  }
}
