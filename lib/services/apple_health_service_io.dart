import 'dart:convert';
import 'dart:io';

import 'package:health/health.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';
import 'health_tracker_service.dart';
import 'apple_health_normalizer.dart';

class AppleHealthService {
  static bool get isSupported => Platform.isIOS;

  static const _types = AppleHealthNormalizer.types;

  static Future<HealthTrackerSyncResult> syncDailyMetrics({
    int days = 30,
  }) async {
    if (!Platform.isIOS) {
      throw UnsupportedError('Apple Health is only available on iPhone.');
    }

    final requestedDays = days.clamp(1, 90);
    final health = Health();
    await health.configure();
    final authorized = await health.requestAuthorization(
      _types,
      permissions: _types.map((_) => HealthDataAccess.READ).toList(),
    );
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
      startTime: start.subtract(const Duration(days: 2)),
      endTime: now,
    );
    final records = AppleHealthNormalizer.dailyRecords(points)
        .where(
          (row) =>
              DateTime.parse(row['date'] as String).isBefore(start) == false,
        )
        .toList();

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
}
