import 'health_tracker_service.dart';

class AppleHealthService {
  static bool get isSupported => false;

  static Future<List<Map<String, dynamic>>> readDailyMetrics({int days = 30}) {
    throw UnsupportedError('Apple Health is only available on iPhone.');
  }

  static Future<HealthTrackerSyncResult> syncDailyMetrics({int days = 30}) {
    throw UnsupportedError('Apple Health is only available on iPhone.');
  }
}
