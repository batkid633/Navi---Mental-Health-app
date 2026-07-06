import 'dart:convert';
import 'dart:io';

import 'package:health/health.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import 'health_tracker_service.dart';

class AppleHealthService {
  static bool get isSupported => Platform.isIOS;

  static const List<HealthDataType> _types = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
  ];

  static Future<HealthTrackerSyncResult> syncDailyMetrics({
    int days = 30,
  }) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Apple Health is only available on iPhone.');
    }

    final requestedDays = days.clamp(1, 90);
    final health = Health();
    await health.configure();
    final authorized = await health.requestAuthorization(_types);
    if (!authorized) {
      return HealthTrackerSyncResult(
        provider: HealthTrackerProvider.appleHealth.id,
        requestedDays: requestedDays,
        fetched: 0,
        saved: 0,
        connected: false,
        detail: 'Apple Health permission was not granted.',
      );
    }

    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: requestedDays - 1));
    final points = await health.getHealthDataFromTypes(
      types: _types,
      startTime: start,
      endTime: now,
    );
    final records = _dailyRecords(points);

    final response = await http
        .post(
          Uri.parse('${BackendConfig.baseUrl}/apple-health/sync'),
          headers: await BackendConfig.getAuthHeaders(),
          body: jsonEncode({'days': requestedDays, 'records': records}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode >= 400) {
      throw Exception('Apple Health sync failed: HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return HealthTrackerSyncResult.fromJson(body);
  }

  static List<Map<String, dynamic>> _dailyRecords(
    List<HealthDataPoint> points,
  ) {
    final byDay = <String, _AppleHealthDay>{};
    for (final point in points) {
      final day = _dateKey(point.dateFrom);
      final bucket = byDay.putIfAbsent(day, () => _AppleHealthDay(day));
      final value = _numericValue(point);
      if (value == null) {
        continue;
      }

      switch (point.type) {
        case HealthDataType.SLEEP_ASLEEP:
          bucket.sleepMinutes += value;
        case HealthDataType.SLEEP_IN_BED:
          bucket.inBedMinutes += value;
        case HealthDataType.RESTING_HEART_RATE:
          bucket.restingHrValues.add(value);
        case HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
          bucket.hrvValues.add(value);
        default:
          break;
      }
    }

    final records = byDay.values.map((day) => day.toJson()).where((record) {
      return record.keys.any((key) => key != 'date' && record[key] != null);
    }).toList();
    records.sort(
      (a, b) => (a['date'] as String).compareTo(b['date'] as String),
    );
    return records;
  }

  static double? _numericValue(HealthDataPoint point) {
    final value = point.toJson()['value'];
    if (value is Map) {
      final numeric = value['numeric_value'] ?? value['value'];
      if (numeric is num) {
        return numeric.toDouble();
      }
      return double.tryParse(numeric?.toString() ?? '');
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  static String _dateKey(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String().substring(0, 10);
  }
}

class _AppleHealthDay {
  final String date;
  double sleepMinutes = 0;
  double inBedMinutes = 0;
  final List<double> restingHrValues = [];
  final List<double> hrvValues = [];

  _AppleHealthDay(this.date);

  Map<String, dynamic> toJson() {
    final sleepHours = sleepMinutes <= 0 ? null : sleepMinutes / 60.0;
    final sleepEfficiency = sleepMinutes <= 0 || inBedMinutes <= 0
        ? null
        : (sleepMinutes / inBedMinutes * 100).clamp(0, 100);
    return {
      'date': date,
      'sleep_hours': sleepHours,
      'sleep_efficiency': sleepEfficiency,
      'resting_hr': _average(restingHrValues),
      'hrv_rmssd': _average(hrvValues),
    };
  }

  double? _average(List<double> values) {
    if (values.isEmpty) {
      return null;
    }
    return values.reduce((a, b) => a + b) / values.length;
  }
}
