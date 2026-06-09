import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'sync_status.dart';

part 'audio_entry.g.dart';

@HiveType(typeId: 1)
class AudioEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime date;

  @HiveField(2)
  String filePath;

  @HiveField(3)
  String fileName;

  @HiveField(4)
  int duration; // in seconds

  @HiveField(5)
  String? transcription;

  @HiveField(6)
  String mode; // 'emotional_venting' or 'deeper_analysis'

  @HiveField(7)
  String? moodLabel;

  @HiveField(8)
  bool isTraining;

  @HiveField(9)
  String syncStatus;

  @HiveField(10)
  int syncAttempts;

  @HiveField(11)
  String? lastSyncError;

  @HiveField(12)
  DateTime? lastSyncedAt;

  @HiveField(13)
  DateTime? nextRetryAt;

  @HiveField(14)
  String? storagePath;

  @HiveField(15)
  String? downloadUrl;

  AudioEntry({
    required this.id,
    required this.date,
    required this.filePath,
    required this.fileName,
    required this.duration,
    this.transcription,
    required this.mode,
    this.moodLabel,
    this.isTraining = false,
    this.syncStatus = SyncStatus.pending,
    this.syncAttempts = 0,
    this.lastSyncError,
    this.lastSyncedAt,
    this.nextRetryAt,
    this.storagePath,
    this.downloadUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'filePath': filePath,
      'fileName': fileName,
      'duration': duration,
      'transcription': transcription,
      'mode': mode,
      'moodLabel': moodLabel,
      'isTraining': isTraining,
      'syncStatus': syncStatus,
      'syncAttempts': syncAttempts,
      'lastSyncError': lastSyncError,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'nextRetryAt': nextRetryAt?.toIso8601String(),
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
    };
  }

  factory AudioEntry.fromJson(Map<String, dynamic> json) {
    return AudioEntry(
      id:
          json['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      date: _dateTimeFromJson(json['date']) ?? DateTime.now(),
      filePath: json['filePath']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      duration: _intFromJson(json['duration']),
      transcription: json['transcription']?.toString(),
      mode: json['mode']?.toString() ?? 'emotional_venting',
      moodLabel: json['moodLabel']?.toString(),
      isTraining: json['isTraining'] ?? false,
      syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
      syncAttempts: _intFromJson(json['syncAttempts']),
      lastSyncError: json['lastSyncError']?.toString(),
      lastSyncedAt: _dateTimeFromJson(json['lastSyncedAt']),
      nextRetryAt: _dateTimeFromJson(json['nextRetryAt']),
      storagePath: json['storagePath']?.toString(),
      downloadUrl: json['downloadUrl']?.toString(),
    );
  }

  String get dedupeKey {
    return _stableHash(
      '${date.toUtc().millisecondsSinceEpoch}|$fileName|$duration|$mode|'
      '$isTraining|${moodLabel ?? ''}',
    );
  }

  static String canonicalId({
    required DateTime date,
    required String fileName,
    required int duration,
    required String mode,
    required bool isTraining,
    String? moodLabel,
  }) {
    final hash = _stableHash(
      '${date.toUtc().millisecondsSinceEpoch}|$fileName|$duration|$mode|'
      '$isTraining|${moodLabel ?? ''}',
    );
    return 'audio_$hash';
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
