import 'package:firebase_auth/firebase_auth.dart';

import '../services/settings_service.dart';

class BackendConfig {
  /// Backend port (usually 8000)
  static const int port = SettingsService.defaultPort;

  /// Get the appropriate backend base URL.
  /// Uses a saved custom URL if present; otherwise WiFi or localhost.
  static String get baseUrl => SettingsService.effectiveBaseUrl;

  /// Get auth headers for API requests
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}
