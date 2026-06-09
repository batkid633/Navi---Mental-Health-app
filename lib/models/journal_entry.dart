import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'sync_status.dart';

part 'journal_entry.g.dart';

@HiveType(typeId: 0)
class JournalEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime date;

  @HiveField(2)
  String text;

  @HiveField(3)
  String? sentimentLabel;

  @HiveField(4)
  double? sentimentScore;

  @HiveField(5)
  String syncStatus;

  @HiveField(6)
  int syncAttempts;

  @HiveField(7)
  String? lastSyncError;

  @HiveField(8)
  DateTime? lastSyncedAt;

  @HiveField(9)
  DateTime? nextRetryAt;

  @HiveField(10)
  String? sentimentSource;

  @HiveField(11)
  String? sentimentFallbackReason;

  JournalEntry({
    required this.id,
    required this.date,
    required this.text,
    this.sentimentLabel,
    this.sentimentScore,
    this.syncStatus = SyncStatus.pending,
    this.syncAttempts = 0,
    this.lastSyncError,
    this.lastSyncedAt,
    this.nextRetryAt,
    this.sentimentSource,
    this.sentimentFallbackReason,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'text': text,
      'sentimentLabel': sentimentLabel,
      'sentimentScore': sentimentScore,
      'syncStatus': syncStatus,
      'syncAttempts': syncAttempts,
      'lastSyncError': lastSyncError,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'nextRetryAt': nextRetryAt?.toIso8601String(),
      'sentimentSource': sentimentSource,
      'sentimentFallbackReason': sentimentFallbackReason,
    };
  }

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    final id =
        json['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    final dynamic dateValue = json['date'];
    late final DateTime date;
    if (dateValue is DateTime) {
      date = dateValue;
    } else if (dateValue is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateValue);
    } else if (dateValue is String) {
      date = DateTime.tryParse(dateValue) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    final dynamic sentimentScoreValue =
        json['sentimentScore'] ?? json['sentiment_score'];
    final double? sentimentScore = sentimentScoreValue is num
        ? sentimentScoreValue.toDouble()
        : double.tryParse(sentimentScoreValue?.toString() ?? '');

    return JournalEntry(
      id: id,
      date: date,
      text: json['text']?.toString() ?? '',
      sentimentLabel: json['sentimentLabel'] ?? json['sentiment_label'],
      sentimentScore: sentimentScore,
      syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
      syncAttempts: _intFromJson(json['syncAttempts']),
      lastSyncError: json['lastSyncError']?.toString(),
      lastSyncedAt: _dateTimeFromJson(json['lastSyncedAt']),
      nextRetryAt: _dateTimeFromJson(json['nextRetryAt']),
      sentimentSource: (json['sentimentSource'] ?? json['sentiment_source'])
          ?.toString(),
      sentimentFallbackReason:
          (json['sentimentFallbackReason'] ?? json['sentiment_fallback_reason'])
              ?.toString(),
    );
  }

  String get dedupeKey {
    final dateKey = date.toUtc().millisecondsSinceEpoch.toString();
    final textKey = text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return _stableHash('$dateKey|$textKey');
  }

  static String canonicalId(DateTime date, String text) {
    final dateKey = date.toUtc().millisecondsSinceEpoch.toString();
    final textKey = text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    return 'journal_${_stableHash('$dateKey|$textKey')}';
  }

  static int _intFromJson(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse(value.toString());
  }

  static String _stableHash(String input) {
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
