import 'package:firebase_auth/firebase_auth.dart';

import '../config/backend_config.dart';
import 'biometric_refresh_coordinator.dart';
import 'health_tracker_service.dart';
import 'settings_service.dart';

/// Uses existing connected-provider endpoints only while requesting insights.
/// Apple Health preview access does not authorize automatic uploads.
class AutomaticBiometricSync {
  static final _coordinator = BiometricRefreshCoordinator(refresh: _refresh);
  static final Map<String, int> _predictionRevisions = {};

  static String? get scope {
    if (!SettingsService.cloudSyncEnabled ||
        !SettingsService.personalizedInsightsEnabled) {
      return null;
    }
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      return uid == null ? null : '$uid|${BackendConfig.baseUrl}';
    } catch (_) {
      return null;
    }
  }

  static Future<int> ensureFresh(String? expectedScope) async {
    if (expectedScope == null || scope != expectedScope) return 0;
    return _coordinator.ensureFresh(expectedScope);
  }

  static bool predictionNeedsRefresh(String? key, int revision) =>
      key != null && revision > (_predictionRevisions[key] ?? 0);

  static void predictionLoaded(String? key, int revision) {
    if (key != null && key == scope) _predictionRevisions[key] = revision;
  }

  static Future<bool> _refresh(String expectedScope) async {
    var changed = false;
    var failed = false;
    // Start imports sequentially. A timed-out server request may still finish later.
    for (final provider in [
      HealthTrackerProvider.whoop,
      HealthTrackerProvider.fitbit,
    ]) {
      if (scope != expectedScope) return changed;
      try {
        final status = await HealthTrackerService.getStatus(
          provider,
        ).timeout(const Duration(seconds: 4));
        if (!status.connected || !status.configured || status.setupRequired) {
          continue;
        }
        if (scope != expectedScope) return changed;
        final result = await HealthTrackerService.syncDailyMetrics(
          provider,
          days: 7,
        ).timeout(const Duration(seconds: 8));
        if (!result.connected) {
          failed = true;
        } else {
          changed = changed || result.saved > 0;
        }
      } catch (_) {
        failed = true;
      }
    }
    // Preserve successful imports; failed-only refreshes use a shorter backoff.
    if (failed && !changed) throw StateError('Biometric refresh unavailable');
    return changed;
  }
}
