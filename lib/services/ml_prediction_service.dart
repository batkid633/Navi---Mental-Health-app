import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tomorrow_outlook.dart';
import '../config/backend_config.dart';
import 'automatic_biometric_sync.dart';

class MLPredictionService {
  static Future<TomorrowOutlook?> loadTomorrowOutlook({
    required String date,
    bool forceReload = false,
  }) async {
    try {
      final syncScope = AutomaticBiometricSync.scope;
      final revision = await AutomaticBiometricSync.ensureFresh(syncScope);
      if (syncScope != null && AutomaticBiometricSync.scope != syncScope) {
        return null;
      }
      final response = await http
          .post(
            Uri.parse("${BackendConfig.baseUrl}/predict/tomorrow"),
            headers: await BackendConfig.getAuthHeaders(),
            body: jsonEncode({
              "date": date,
              "force_reload":
                  forceReload ||
                  AutomaticBiometricSync.predictionNeedsRefresh(
                    syncScope,
                    revision,
                  ),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;
      final outlook = TomorrowOutlook.fromJson(jsonDecode(response.body));
      if (syncScope != null && AutomaticBiometricSync.scope != syncScope) {
        return null;
      }
      AutomaticBiometricSync.predictionLoaded(syncScope, revision);
      return outlook;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<TomorrowOutlook?> loadTrajectoryOutlook({
    required String date,
  }) async {
    try {
      final syncScope = AutomaticBiometricSync.scope;
      await AutomaticBiometricSync.ensureFresh(syncScope);
      if (syncScope != null && AutomaticBiometricSync.scope != syncScope) {
        return null;
      }
      final response = await http
          .post(
            Uri.parse("${BackendConfig.baseUrl}/predict/trajectory"),
            headers: await BackendConfig.getAuthHeaders(),
            body: jsonEncode({"date": date}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;
      return TomorrowOutlook.fromJson(jsonDecode(response.body));
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
