import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/backend_config.dart';

class WhoopStatus {
  final bool connected;
  final String? expiresAt;
  final String? error;

  WhoopStatus({required this.connected, this.expiresAt, this.error});

  factory WhoopStatus.fromJson(Map<String, dynamic> json) {
    return WhoopStatus(
      connected: json['connected'] == true,
      expiresAt: json['expires_at'] as String?,
      error: json['error'] as String?,
    );
  }

  String get statusLabel {
    if (error != null && error!.isNotEmpty) {
      return 'Error: $error';
    }
    return connected ? 'Connected' : 'Not connected';
  }
}

class WhoopService {
  static Future<WhoopStatus> getStatus() async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/whoop/status');
    final response = await http.get(
      uri,
      headers: await BackendConfig.getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Whoop status request failed: ${response.statusCode}');
    }

    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return WhoopStatus.fromJson(jsonBody);
  }

  static Future<WhoopConnectInfo> getConnectInfo() async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/whoop/connect');
    final response = await http.get(
      uri,
      headers: await BackendConfig.getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Whoop connect request failed: ${response.statusCode}');
    }

    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final authUrl = jsonBody['auth_url'] as String?;
    final redirectUri = jsonBody['redirect_uri'] as String?;
    if (authUrl == null || authUrl.isEmpty) {
      throw Exception('Invalid connect URL returned from backend.');
    }

    return WhoopConnectInfo(
      authUrl: authUrl,
      redirectUri: redirectUri ?? '',
    );
  }

  static Future<WhoopConnectInfo> launchConnectUrl() async {
    final info = await getConnectInfo();
    final uri = Uri.parse(info.authUrl);

    final launched = await launchUrl(
      uri,
      mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );

    if (!launched) {
      throw Exception('Cannot open WHOOP auth URL. Auth URL: ${info.authUrl}');
    }

    return info;
  }

  static Future<void> retrainModel() async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/whoop/retrain');
    final response = await http.post(
      uri,
      headers: await BackendConfig.getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Retrain request failed: ${response.statusCode}');
    }
  }
}

class WhoopConnectInfo {
  final String authUrl;
  final String redirectUri;

  WhoopConnectInfo({required this.authUrl, required this.redirectUri});
}
