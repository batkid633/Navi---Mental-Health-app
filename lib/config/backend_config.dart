class BackendConfig {
  /// Set to true to use WiFi connection, false for localhost
  static const bool useWiFi = false;

  /// Your computer's local IP address (only used if useWiFi is true)
  /// Example: "192.168.1.100"
  static const String wiFiIP = "192.168.1.161";

  /// Backend port (usually 8000)
  static const int port = 8000;

  /// Get the appropriate backend base URL
  static String get baseUrl {
    if (useWiFi) {
      return "http://$wiFiIP:$port";
    } else {
      return "http://127.0.0.1:$port";
    }
  }

  /// Get auth headers for API requests
  static Future<Map<String, String>> getAuthHeaders() async {
    // TODO: Get Firebase ID token
    // final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    // return {
    //   'Authorization': 'Bearer $token',
    //   'Content-Type': 'application/json',
    // };
    return {'Content-Type': 'application/json'};
  }
}
