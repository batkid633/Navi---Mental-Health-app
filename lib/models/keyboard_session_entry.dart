import 'package:hive/hive.dart';

import 'sync_status.dart';

part 'keyboard_session_entry.g.dart';

@HiveType(typeId: 3)
class KeyboardSessionEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime startedAt;

  @HiveField(2)
  DateTime endedAt;

  @HiveField(3)
  String fieldContext;

  @HiveField(4)
  String platform;

  @HiveField(5)
  int eventCount;

  @HiveField(6)
  int charsEstimated;

  @HiveField(7)
  int backspaceCount;

  @HiveField(8)
  int burstCount;

  @HiveField(9)
  double pauseMeanMs;

  @HiveField(10)
  double pauseStdMs;

  @HiveField(11)
  int activeSeconds;

  @HiveField(12)
  String syncStatus;

  @HiveField(13)
  int syncAttempts;

  @HiveField(14)
  String? lastSyncError;

  @HiveField(15)
  DateTime? lastSyncedAt;

  @HiveField(16)
  DateTime? nextRetryAt;

  KeyboardSessionEntry({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.fieldContext,
    required this.platform,
    required this.eventCount,
    required this.charsEstimated,
    required this.backspaceCount,
    required this.burstCount,
    required this.pauseMeanMs,
    required this.pauseStdMs,
    required this.activeSeconds,
    this.syncStatus = SyncStatus.pending,
    this.syncAttempts = 0,
    this.lastSyncError,
    this.lastSyncedAt,
    this.nextRetryAt,
  });

  double get correctionRate {
    if (charsEstimated <= 0) return 0.0;
    return backspaceCount / charsEstimated;
  }

  double get typingSpeedCpm {
    if (activeSeconds <= 0) return 0.0;
    return charsEstimated / (activeSeconds / 60.0);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'fieldContext': fieldContext,
      'platform': platform,
      'eventCount': eventCount,
      'charsEstimated': charsEstimated,
      'backspaceCount': backspaceCount,
      'burstCount': burstCount,
      'pauseMeanMs': pauseMeanMs,
      'pauseStdMs': pauseStdMs,
      'activeSeconds': activeSeconds,
      'correctionRate': correctionRate,
      'typingSpeedCpm': typingSpeedCpm,
      'syncStatus': syncStatus,
      'syncAttempts': syncAttempts,
      'lastSyncError': lastSyncError,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'nextRetryAt': nextRetryAt?.toIso8601String(),
    };
  }

  factory KeyboardSessionEntry.fromJson(Map<String, dynamic> json) {
    return KeyboardSessionEntry(
      id:
          json['id']?.toString() ??
          canonicalId(_dateTimeFromJson(json['startedAt']) ?? DateTime.now()),
      startedAt: _dateTimeFromJson(json['startedAt']) ?? DateTime.now(),
      endedAt: _dateTimeFromJson(json['endedAt']) ?? DateTime.now(),
      fieldContext: json['fieldContext']?.toString() ?? 'unknown',
      platform: json['platform']?.toString() ?? 'unknown',
      eventCount: _intFromJson(json['eventCount']),
      charsEstimated: _intFromJson(json['charsEstimated']),
      backspaceCount: _intFromJson(json['backspaceCount']),
      burstCount: _intFromJson(json['burstCount']),
      pauseMeanMs: _doubleFromJson(json['pauseMeanMs']),
      pauseStdMs: _doubleFromJson(json['pauseStdMs']),
      activeSeconds: _intFromJson(json['activeSeconds']),
      syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
      syncAttempts: _intFromJson(json['syncAttempts']),
      lastSyncError: json['lastSyncError']?.toString(),
      lastSyncedAt: _dateTimeFromJson(json['lastSyncedAt']),
      nextRetryAt: _dateTimeFromJson(json['nextRetryAt']),
    );
  }

  String get dedupeKey {
    return _stableHash(
      '${startedAt.toUtc().millisecondsSinceEpoch}|'
      '${endedAt.toUtc().millisecondsSinceEpoch}|$fieldContext|$platform',
    );
  }

  static String canonicalId(DateTime startedAt) {
    return 'keyboard_${startedAt.toUtc().microsecondsSinceEpoch}';
  }

  static int _intFromJson(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _doubleFromJson(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
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
