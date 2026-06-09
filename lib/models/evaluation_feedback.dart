import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'sync_status.dart';

part 'evaluation_feedback.g.dart';

@HiveType(typeId: 2)
class EvaluationFeedback extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String targetType;

  @HiveField(2)
  String targetDate;

  @HiveField(3)
  String? journalEntryId;

  @HiveField(4)
  double? predictedDelta;

  @HiveField(5)
  double? confidence;

  @HiveField(6)
  String? modelVersion;

  @HiveField(7)
  String? insight;

  @HiveField(8)
  String? accuracyRating;

  @HiveField(9)
  String? helpfulnessRating;

  @HiveField(10)
  String? actualMoodDirection;

  @HiveField(11)
  String? note;

  @HiveField(12)
  DateTime createdAt;

  @HiveField(13)
  DateTime updatedAt;

  @HiveField(14)
  String syncStatus;

  @HiveField(15)
  int syncAttempts;

  @HiveField(16)
  String? lastSyncError;

  @HiveField(17)
  DateTime? lastSyncedAt;

  @HiveField(18)
  DateTime? nextRetryAt;

  EvaluationFeedback({
    required this.id,
    required this.targetType,
    required this.targetDate,
    this.journalEntryId,
    this.predictedDelta,
    this.confidence,
    this.modelVersion,
    this.insight,
    this.accuracyRating,
    this.helpfulnessRating,
    this.actualMoodDirection,
    this.note,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.syncAttempts = 0,
    this.lastSyncError,
    this.lastSyncedAt,
    this.nextRetryAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'targetType': targetType,
      'targetDate': targetDate,
      'journalEntryId': journalEntryId,
      'predictedDelta': predictedDelta,
      'confidence': confidence,
      'modelVersion': modelVersion,
      'insight': insight,
      'accuracyRating': accuracyRating,
      'helpfulnessRating': helpfulnessRating,
      'actualMoodDirection': actualMoodDirection,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'syncStatus': syncStatus,
      'syncAttempts': syncAttempts,
      'lastSyncError': lastSyncError,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'nextRetryAt': nextRetryAt?.toIso8601String(),
    };
  }

  factory EvaluationFeedback.fromJson(Map<String, dynamic> json) {
    return EvaluationFeedback(
      id:
          json['id']?.toString() ??
          canonicalId(
            json['targetType']?.toString() ?? 'unknown',
            json['targetDate']?.toString() ?? DateTime.now().toIso8601String(),
          ),
      targetType: json['targetType']?.toString() ?? 'unknown',
      targetDate: json['targetDate']?.toString() ?? '',
      journalEntryId: json['journalEntryId']?.toString(),
      predictedDelta: _doubleFromJson(json['predictedDelta']),
      confidence: _doubleFromJson(json['confidence']),
      modelVersion: json['modelVersion']?.toString(),
      insight: json['insight']?.toString(),
      accuracyRating: json['accuracyRating']?.toString(),
      helpfulnessRating: json['helpfulnessRating']?.toString(),
      actualMoodDirection: json['actualMoodDirection']?.toString(),
      note: json['note']?.toString(),
      createdAt: _dateTimeFromJson(json['createdAt']) ?? DateTime.now(),
      updatedAt: _dateTimeFromJson(json['updatedAt']) ?? DateTime.now(),
      syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
      syncAttempts: _intFromJson(json['syncAttempts']),
      lastSyncError: json['lastSyncError']?.toString(),
      lastSyncedAt: _dateTimeFromJson(json['lastSyncedAt']),
      nextRetryAt: _dateTimeFromJson(json['nextRetryAt']),
    );
  }

  static String canonicalId(String targetType, String targetDate) {
    return 'feedback_${_stableHash('$targetType|$targetDate')}';
  }

  static double? _doubleFromJson(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
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
