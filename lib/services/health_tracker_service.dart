import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../config/backend_config.dart';

enum HealthTrackerProvider {
  whoop(
    id: 'whoop',
    label: 'WHOOP',
    statusPath: '/whoop/status',
    connectPath: '/whoop/connect',
    syncPath: '/whoop/sync',
  ),
  fitbit(
    id: 'fitbit',
    label: 'Google Health (Fitbit)',
    statusPath: '/fitbit/status',
    connectPath: '/fitbit/connect',
    syncPath: '/fitbit/sync',
  ),
  appleHealth(
    id: 'apple_health',
    label: 'Apple Health',
    statusPath: '/apple-health/status',
    connectPath: null,
    syncPath: null,
  );

  final String id;
  final String label;
  final String statusPath;
  final String? connectPath;
  final String? syncPath;

  const HealthTrackerProvider({
    required this.id,
    required this.label,
    required this.statusPath,
    required this.connectPath,
    required this.syncPath,
  });
}

class HealthTrackerStatus {
  final bool connected;
  final bool configured;
  final bool setupRequired;
  final bool platformNative;
  final String? expiresAt;
  final String? message;
  final String? error;

  HealthTrackerStatus({
    required this.connected,
    this.configured = true,
    this.setupRequired = false,
    this.platformNative = false,
    this.expiresAt,
    this.message,
    this.error,
  });

  factory HealthTrackerStatus.fromJson(Map<String, dynamic> json) {
    return HealthTrackerStatus(
      connected: json['connected'] == true,
      configured: json['configured'] != false,
      setupRequired: json['setup_required'] == true,
      platformNative: json['platform_native'] == true,
      expiresAt: json['expires_at'] as String?,
      message: json['message'] as String?,
      error: json['error'] as String?,
    );
  }

  String get statusLabel {
    if (error != null && error!.isNotEmpty) {
      return 'Error';
    }
    if (connected) {
      return 'Connected';
    }
    if (setupRequired || !configured) {
      return 'Setup required';
    }
    return 'Not connected';
  }
}

class HealthTrackerConnectInfo {
  final String authUrl;
  final String redirectUri;

  HealthTrackerConnectInfo({required this.authUrl, required this.redirectUri});
}

class HealthTrackerSyncResult {
  final String provider;
  final int requestedDays;
  final int fetched;
  final int saved;
  final bool connected;
  final String? detail;

  HealthTrackerSyncResult({
    required this.provider,
    required this.requestedDays,
    required this.fetched,
    required this.saved,
    this.connected = true,
    this.detail,
  });

  factory HealthTrackerSyncResult.fromJson(Map<String, dynamic> json) {
    return HealthTrackerSyncResult(
      provider: json['provider']?.toString() ?? 'health_tracker',
      requestedDays: (json['requested_days'] as num?)?.toInt() ?? 0,
      fetched: (json['fetched'] as num?)?.toInt() ?? 0,
      saved: (json['saved'] as num?)?.toInt() ?? 0,
      connected: json['connected'] != false,
      detail: json['detail'] as String?,
    );
  }
}

class HealthTrackerService {
  static Future<HealthTrackerStatus> getStatus(
    HealthTrackerProvider provider,
  ) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}${provider.statusPath}');
    final response = await http.get(
      uri,
      headers: await BackendConfig.getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception(
        '${provider.label} status request failed: ${response.statusCode}',
      );
    }

    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return HealthTrackerStatus.fromJson(jsonBody);
  }

  static Future<HealthTrackerConnectInfo> getConnectInfo(
    HealthTrackerProvider provider,
  ) async {
    final connectPath = provider.connectPath;
    if (connectPath == null) {
      throw Exception('${provider.label} uses native device permissions.');
    }

    final uri = Uri.parse('${BackendConfig.baseUrl}$connectPath');
    final response = await http.get(
      uri,
      headers: await BackendConfig.getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      String detail = response.body;
      try {
        final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
        detail = jsonBody['detail']?.toString() ?? response.body;
      } catch (_) {
        // Keep raw body.
      }
      throw Exception(
        '${provider.label} connect request failed: ${response.statusCode} $detail',
      );
    }

    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    final authUrl = jsonBody['auth_url'] as String?;
    final redirectUri = jsonBody['redirect_uri'] as String?;
    if (authUrl == null || authUrl.isEmpty) {
      throw Exception('Invalid connect URL returned from backend.');
    }

    return HealthTrackerConnectInfo(
      authUrl: authUrl,
      redirectUri: redirectUri ?? '',
    );
  }

  static Future<HealthTrackerConnectInfo> launchConnectUrl(
    HealthTrackerProvider provider,
  ) async {
    final info = await getConnectInfo(provider);
    final uri = Uri.parse(info.authUrl);

    final launched = await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );

    if (!launched) {
      throw Exception('Cannot open ${provider.label} auth URL.');
    }

    return info;
  }

  static Future<HealthTrackerSyncResult> syncDailyMetrics(
    HealthTrackerProvider provider, {
    int days = 30,
  }) async {
    final syncPath = provider.syncPath;
    if (syncPath == null) {
      throw Exception('${provider.label} does not support backend sync yet.');
    }

    final uri = Uri.parse(
      '${BackendConfig.baseUrl}$syncPath',
    ).replace(queryParameters: {'days': '$days'});
    final response = await http.post(
      uri,
      headers: await BackendConfig.getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      String detail = response.body;
      try {
        final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
        detail = jsonBody['detail']?.toString() ?? response.body;
      } catch (_) {
        // Keep raw body.
      }
      throw Exception(
        '${provider.label} sync failed: ${response.statusCode} $detail',
      );
    }

    final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
    return HealthTrackerSyncResult.fromJson(jsonBody);
  }
}
