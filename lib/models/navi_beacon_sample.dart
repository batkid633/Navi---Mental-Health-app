import 'package:hive/hive.dart';

import 'sync_status.dart';

part 'navi_beacon_sample.g.dart';

@HiveType(typeId: 4)
class NaviBeaconSample extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime capturedAt;

  @HiveField(2)
  int? heartRate;

  @HiveField(3)
  double? temperatureC;

  @HiveField(4)
  double? lux;

  @HiveField(5)
  String activity;

  @HiveField(6)
  int? batteryPercent;

  @HiveField(7)
  double? accelerationX;

  @HiveField(8)
  double? accelerationY;

  @HiveField(9)
  double? accelerationZ;

  @HiveField(10)
  double? motionMagnitude;

  @HiveField(11)
  int? signalQuality;

  @HiveField(12)
  String sourceDeviceId;

  @HiveField(13)
  String syncStatus;

  @HiveField(14)
  int syncAttempts;

  @HiveField(15)
  String? lastSyncError;

  @HiveField(16)
  DateTime? lastSyncedAt;

  @HiveField(17)
  DateTime? nextRetryAt;

  NaviBeaconSample({
    required this.id,
    required this.capturedAt,
    this.heartRate,
    this.temperatureC,
    this.lux,
    required this.activity,
    this.batteryPercent,
    this.accelerationX,
    this.accelerationY,
    this.accelerationZ,
    this.motionMagnitude,
    this.signalQuality,
    required this.sourceDeviceId,
    this.syncStatus = SyncStatus.pending,
    this.syncAttempts = 0,
    this.lastSyncError,
    this.lastSyncedAt,
    this.nextRetryAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'capturedAt': capturedAt.toIso8601String(),
      'heartRate': heartRate,
      'temperatureC': temperatureC,
      'lux': lux,
      'activity': activity,
      'batteryPercent': batteryPercent,
      'accelerationX': accelerationX,
      'accelerationY': accelerationY,
      'accelerationZ': accelerationZ,
      'motionMagnitude': motionMagnitude,
      'signalQuality': signalQuality,
      'sourceDeviceId': sourceDeviceId,
      'syncStatus': syncStatus,
      'syncAttempts': syncAttempts,
      'lastSyncError': lastSyncError,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'nextRetryAt': nextRetryAt?.toIso8601String(),
    };
  }

  factory NaviBeaconSample.fromJson(Map<String, dynamic> json) {
    final capturedAt = _dateTimeFromJson(
      json['capturedAt'] ?? json['captured_at'] ?? json['time'],
    );
    return NaviBeaconSample(
      id:
          json['id']?.toString() ??
          canonicalId(capturedAt ?? DateTime.now(), json['sourceDeviceId']),
      capturedAt: capturedAt ?? DateTime.now(),
      heartRate: _nullableIntFromJson(json['heartRate'] ?? json['hr']),
      temperatureC: _nullableDoubleFromJson(
        json['temperatureC'] ?? json['temp'] ?? json['temperature_c'],
      ),
      lux: _nullableDoubleFromJson(json['lux']),
      activity: _activityFromJson(json['activity']),
      batteryPercent: _nullableIntFromJson(
        json['batteryPercent'] ?? json['battery'],
      ),
      accelerationX: _nullableDoubleFromJson(
        json['accelerationX'] ?? json['ax'],
      ),
      accelerationY: _nullableDoubleFromJson(
        json['accelerationY'] ?? json['ay'],
      ),
      accelerationZ: _nullableDoubleFromJson(
        json['accelerationZ'] ?? json['az'],
      ),
      motionMagnitude: _nullableDoubleFromJson(
        json['motionMagnitude'] ?? json['motion'],
      ),
      signalQuality: _nullableIntFromJson(
        json['signalQuality'] ?? json['quality'],
      ),
      sourceDeviceId: json['sourceDeviceId']?.toString() ?? 'navi_beacon',
      syncStatus: json['syncStatus']?.toString() ?? SyncStatus.pending,
      syncAttempts: _intFromJson(json['syncAttempts']),
      lastSyncError: json['lastSyncError']?.toString(),
      lastSyncedAt: _dateTimeFromJson(json['lastSyncedAt']),
      nextRetryAt: _dateTimeFromJson(json['nextRetryAt']),
    );
  }

  String get dedupeKey {
    return _stableHash(
      '${capturedAt.toUtc().millisecondsSinceEpoch}|$sourceDeviceId|'
      '${heartRate ?? ''}|${temperatureC ?? ''}|${lux ?? ''}|$activity',
    );
  }

  static String canonicalId(DateTime capturedAt, Object? sourceDeviceId) {
    final hash = _stableHash(
      '${capturedAt.toUtc().microsecondsSinceEpoch}|${sourceDeviceId ?? ''}',
    );
    return 'beacon_$hash';
  }

  static String _activityFromJson(dynamic value) {
    if (value is int) {
      return switch (value) {
        1 => 'walking',
        2 => 'running',
        3 => 'restless',
        _ => 'still',
      };
    }
    final text = value?.toString().trim().toLowerCase();
    if (text == 'walking' || text == 'running' || text == 'restless') {
      return text!;
    }
    return 'still';
  }

  static int _intFromJson(dynamic value) {
    return _nullableIntFromJson(value) ?? 0;
  }

  static int? _nullableIntFromJson(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _nullableDoubleFromJson(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _dateTimeFromJson(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
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
