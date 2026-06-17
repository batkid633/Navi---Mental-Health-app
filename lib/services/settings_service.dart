import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../legal/legal_content.dart';

class SettingsService {
  static const String _boxName = 'settings';
  static const String _keyUseWiFi = 'useWiFi';
  static const String _keyWiFiIP = 'wiFiIP';
  static const String _keyBackendUrl = 'backendUrl';
  static const String _keyConsentCompleted = 'consentCompleted';
  static const String _keyConsentVersion = 'consentVersion';
  static const String _keyConsentCompletedAt = 'consentCompletedAt';
  static const String _keyPrivacyPolicyVersion = 'privacyPolicyVersion';
  static const String _keyTermsVersion = 'termsVersion';
  static const String _keyHealthDataConsent = 'healthDataConsent';
  static const String _keyPrivacyPolicyAccepted = 'privacyPolicyAccepted';
  static const String _keyNotEmergencyCareAcknowledged =
      'notEmergencyCareAcknowledged';
  static const String _keyResearchDataSharingEnabled =
      'researchDataSharingEnabled';
  static const String _keyCloudSyncEnabled = 'cloudSyncEnabled';
  static const String _keyPersonalizedInsightsEnabled =
      'personalizedInsightsEnabled';
  static const String _keyKeyboardTrackingEnabled = 'keyboardTrackingEnabled';
  static const String _keyCheckInNotificationsEnabled =
      'checkInNotificationsEnabled';
  static const String _keyCheckInNotificationTimeMinutes =
      'checkInNotificationTimeMinutes';
  static const String _keyNotificationDeviceId = 'notificationDeviceId';
  static const Map<String, String> _backendUrlAliases = {
    'https://navi-backend-712966180400.us-central1.run.app':
        'https://navi-backend-zcp5ib6peq-uc.a.run.app',
  };
  static const String currentConsentVersion = LegalContent.consentVersion;
  static const int defaultPort = 8000;
  static const String productionBackendUrl =
      'https://navi-backend-zcp5ib6peq-uc.a.run.app';
  static const String defaultBackendUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: productionBackendUrl,
  );

  static Box<dynamic>? _box;

  static Future<void> init() async {
    _box ??= await Hive.openBox<dynamic>(_boxName);
    await _migrateMalformedBackendUrl();
  }

  static bool get useWiFi {
    return _box?.get(_keyUseWiFi, defaultValue: false) as bool;
  }

  static String get wiFiIP {
    return _box?.get(_keyWiFiIP, defaultValue: '') as String;
  }

  static String get backendUrl {
    return _box?.get(_keyBackendUrl, defaultValue: '') as String;
  }

  static bool get consentCompleted {
    return _box?.get(_keyConsentCompleted, defaultValue: false) as bool;
  }

  static String get consentVersion {
    return _box?.get(_keyConsentVersion, defaultValue: '') as String;
  }

  static String get consentCompletedAt {
    return _box?.get(_keyConsentCompletedAt, defaultValue: '') as String;
  }

  static String get privacyPolicyVersion {
    return _box?.get(_keyPrivacyPolicyVersion, defaultValue: '') as String;
  }

  static String get termsVersion {
    return _box?.get(_keyTermsVersion, defaultValue: '') as String;
  }

  static bool get healthDataConsent {
    return _box?.get(_keyHealthDataConsent, defaultValue: false) as bool;
  }

  static bool get privacyPolicyAccepted {
    return _box?.get(_keyPrivacyPolicyAccepted, defaultValue: false) as bool;
  }

  static bool get notEmergencyCareAcknowledged {
    return _box?.get(_keyNotEmergencyCareAcknowledged, defaultValue: false)
        as bool;
  }

  static bool get researchDataSharingEnabled {
    return _box?.get(_keyResearchDataSharingEnabled, defaultValue: false)
        as bool;
  }

  static bool get cloudSyncEnabled {
    return _box?.get(_keyCloudSyncEnabled, defaultValue: true) as bool;
  }

  static bool get personalizedInsightsEnabled {
    return _box?.get(_keyPersonalizedInsightsEnabled, defaultValue: true)
        as bool;
  }

  static bool get keyboardTrackingEnabled {
    return _box?.get(_keyKeyboardTrackingEnabled, defaultValue: false) as bool;
  }

  static bool get checkInNotificationsEnabled {
    return _box?.get(_keyCheckInNotificationsEnabled, defaultValue: false)
        as bool;
  }

  static int get checkInNotificationTimeMinutes {
    return _box?.get(_keyCheckInNotificationTimeMinutes, defaultValue: 20 * 60)
        as int;
  }

  static String get notificationDeviceId {
    return _box?.get(_keyNotificationDeviceId, defaultValue: '') as String;
  }

  static bool get hasCustomBackendUrl {
    return backendUrl.trim().isNotEmpty;
  }

  static String get effectiveBaseUrl {
    final customUrl = backendUrl.trim();
    if (customUrl.isNotEmpty && !_isReleaseWebLocalUrl(customUrl)) {
      return _normalizeUrl(customUrl);
    }

    if (defaultBackendUrl.trim().isNotEmpty) {
      return _normalizeUrl(defaultBackendUrl);
    }

    final ip = wiFiIP.trim();
    if (useWiFi && ip.isNotEmpty) {
      return 'http://$ip:$defaultPort';
    }

    return 'http://127.0.0.1:$defaultPort';
  }

  static bool _isReleaseWebLocalUrl(String value) {
    if (!kIsWeb || !kReleaseMode) {
      return false;
    }
    return _isLocalBackendUrl(value);
  }

  static bool _isLocalBackendUrl(String value) {
    final normalized = _normalizeUrl(value);
    return normalized.startsWith('http://127.0.0.1') ||
        normalized.startsWith('http://localhost') ||
        normalized.startsWith('http://10.0.2.2');
  }

  static Future<void> saveUseWiFi(bool value) async {
    await _ensureInitialized();
    await _box?.put(_keyUseWiFi, value);
  }

  static Future<void> saveWiFiIP(String value) async {
    await _ensureInitialized();
    await _box?.put(_keyWiFiIP, value.trim());
  }

  static Future<void> saveBackendUrl(String value) async {
    await _ensureInitialized();
    await _box?.put(_keyBackendUrl, _normalizeUrl(value));
  }

  static Future<void> saveConsentPreferences({
    required bool healthDataConsent,
    required bool privacyPolicyAccepted,
    required bool notEmergencyCareAcknowledged,
    required bool researchDataSharingEnabled,
    required bool cloudSyncEnabled,
    required bool personalizedInsightsEnabled,
    required bool keyboardTrackingEnabled,
  }) async {
    await _ensureInitialized();
    final completed =
        healthDataConsent &&
        privacyPolicyAccepted &&
        notEmergencyCareAcknowledged;
    await _box?.put(_keyHealthDataConsent, healthDataConsent);
    await _box?.put(_keyPrivacyPolicyAccepted, privacyPolicyAccepted);
    await _box?.put(
      _keyNotEmergencyCareAcknowledged,
      notEmergencyCareAcknowledged,
    );
    await _box?.put(_keyResearchDataSharingEnabled, researchDataSharingEnabled);
    await _box?.put(_keyCloudSyncEnabled, cloudSyncEnabled);
    await _box?.put(
      _keyPersonalizedInsightsEnabled,
      personalizedInsightsEnabled,
    );
    await _box?.put(_keyKeyboardTrackingEnabled, keyboardTrackingEnabled);
    await _box?.put(_keyConsentCompleted, completed);
    if (completed) {
      await _box?.put(_keyConsentVersion, currentConsentVersion);
      await _box?.put(
        _keyPrivacyPolicyVersion,
        LegalContent.privacyPolicyVersion,
      );
      await _box?.put(_keyTermsVersion, LegalContent.termsVersion);
      await _box?.put(
        _keyConsentCompletedAt,
        DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  static Future<void> saveResearchDataSharingEnabled(bool value) async {
    await _ensureInitialized();
    await _box?.put(_keyResearchDataSharingEnabled, value);
  }

  static Future<void> saveCloudSyncEnabled(bool value) async {
    await _ensureInitialized();
    await _box?.put(_keyCloudSyncEnabled, value);
  }

  static Future<void> savePersonalizedInsightsEnabled(bool value) async {
    await _ensureInitialized();
    await _box?.put(_keyPersonalizedInsightsEnabled, value);
  }

  static Future<void> saveKeyboardTrackingEnabled(bool value) async {
    await _ensureInitialized();
    await _box?.put(_keyKeyboardTrackingEnabled, value);
  }

  static Future<void> saveCheckInNotificationSettings({
    required bool enabled,
    required int timeMinutes,
  }) async {
    await _ensureInitialized();
    await _box?.put(_keyCheckInNotificationsEnabled, enabled);
    await _box?.put(
      _keyCheckInNotificationTimeMinutes,
      timeMinutes.clamp(0, 23 * 60 + 59),
    );
  }

  static Future<String> ensureNotificationDeviceId(
    String Function() createId,
  ) async {
    await _ensureInitialized();
    final existing = notificationDeviceId.trim();
    if (existing.isNotEmpty) {
      return existing;
    }
    final deviceId = createId();
    await _box?.put(_keyNotificationDeviceId, deviceId);
    return deviceId;
  }

  static Map<String, dynamic> privacyConsentSnapshot() {
    return {
      'consentCompleted': consentCompleted,
      'consentVersion': consentVersion,
      'consentCompletedAt': consentCompletedAt,
      'privacyPolicyVersion': privacyPolicyVersion,
      'termsVersion': termsVersion,
      'healthDataConsent': healthDataConsent,
      'privacyPolicyAccepted': privacyPolicyAccepted,
      'notEmergencyCareAcknowledged': notEmergencyCareAcknowledged,
      'researchDataSharingEnabled': researchDataSharingEnabled,
      'cloudSyncEnabled': cloudSyncEnabled,
      'personalizedInsightsEnabled': personalizedInsightsEnabled,
      'keyboardTrackingEnabled': keyboardTrackingEnabled,
      'checkInNotificationsEnabled': checkInNotificationsEnabled,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static Map<String, dynamic> notificationPreferencesSnapshot() {
    return {
      'checkInNotificationsEnabled': checkInNotificationsEnabled,
      'checkInNotificationTimeMinutes': checkInNotificationTimeMinutes,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static Future<void> resetToDefaults() async {
    await _ensureInitialized();
    await _box?.put(_keyUseWiFi, false);
    await _box?.put(_keyWiFiIP, '');
    await _box?.put(_keyBackendUrl, '');
    await _box?.put(_keyResearchDataSharingEnabled, false);
    await _box?.put(_keyCloudSyncEnabled, true);
    await _box?.put(_keyPersonalizedInsightsEnabled, true);
    await _box?.put(_keyKeyboardTrackingEnabled, false);
    await _box?.put(_keyCheckInNotificationsEnabled, false);
    await _box?.put(_keyCheckInNotificationTimeMinutes, 20 * 60);
  }

  static Future<void> resetPrivacyControls() async {
    await _ensureInitialized();
    await _box?.put(_keyConsentCompleted, false);
    await _box?.put(_keyConsentVersion, '');
    await _box?.put(_keyConsentCompletedAt, '');
    await _box?.put(_keyPrivacyPolicyVersion, '');
    await _box?.put(_keyTermsVersion, '');
    await _box?.put(_keyHealthDataConsent, false);
    await _box?.put(_keyPrivacyPolicyAccepted, false);
    await _box?.put(_keyNotEmergencyCareAcknowledged, false);
    await _box?.put(_keyResearchDataSharingEnabled, false);
    await _box?.put(_keyCloudSyncEnabled, true);
    await _box?.put(_keyPersonalizedInsightsEnabled, true);
    await _box?.put(_keyKeyboardTrackingEnabled, false);
    await _box?.put(_keyCheckInNotificationsEnabled, false);
    await _box?.put(_keyCheckInNotificationTimeMinutes, 20 * 60);
  }

  static Future<void> _ensureInitialized() async {
    if (_box == null) {
      await init();
    }
  }

  static Future<void> _migrateMalformedBackendUrl() async {
    final savedUrl = _box?.get(_keyBackendUrl, defaultValue: '') as String;
    if (savedUrl.isEmpty) {
      return;
    }

    final normalizedUrl = _normalizeUrl(savedUrl);
    final migratedUrl =
        kIsWeb && kReleaseMode && _isLocalBackendUrl(normalizedUrl)
        ? productionBackendUrl
        : _backendUrlAliases[normalizedUrl] ?? normalizedUrl;
    if (migratedUrl != savedUrl) {
      await _box?.put(_keyBackendUrl, migratedUrl);
    }
  }

  static String _normalizeUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    // Fix common malformed URL inputs.
    trimmed = trimmed.replaceAll('\\', '/');
    if (trimmed.startsWith(r'$1//')) {
      trimmed = 'https://${trimmed.substring(5)}';
    }
    if (trimmed.startsWith('http:/') && !trimmed.startsWith('http://')) {
      trimmed = 'http://${trimmed.substring(6)}';
    } else if (trimmed.startsWith('https:/') &&
        !trimmed.startsWith('https://')) {
      trimmed = 'https://${trimmed.substring(7)}';
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      // Remove repeated slashes after scheme if present.
      trimmed = trimmed.replaceFirstMapped(
        RegExp(r'^(https?:)/+'),
        (match) => '${match.group(1)}//',
      );
    } else {
      trimmed = 'http://$trimmed';
    }

    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    return trimmed;
  }
}
