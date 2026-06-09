import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'analytics_service.dart';
import 'cloud_persistence_service.dart';
import 'settings_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();

  NotificationService._();

  final CloudPersistenceService _cloudPersistence = CloudPersistenceService();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  String? _currentUserId;
  bool _initialized = false;

  bool get isSupported {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  Future<void> init() async {
    if (_initialized || !isSupported) {
      return;
    }

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((
      message,
    ) {
      AnalyticsService.track(
        'notification_received_foreground',
        properties: {
          'type': message.data['type'] ?? message.messageType ?? 'unknown',
        },
      );
    });

    _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((
      message,
    ) {
      AnalyticsService.track(
        'notification_opened',
        properties: {
          'type': message.data['type'] ?? message.messageType ?? 'unknown',
        },
      );
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      await AnalyticsService.track(
        'notification_opened_cold_start',
        properties: {
          'type':
              initialMessage.data['type'] ??
              initialMessage.messageType ??
              'unknown',
        },
      );
    }

    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen((token) {
          final uid = _currentUserId;
          if (uid == null || uid.isEmpty) {
            return;
          }
          _saveDeviceRegistration(uid, token).catchError((error) {
            debugPrint(
              '[NotificationService] Token refresh sync failed: $error',
            );
          });
        });

    _initialized = true;
  }

  Future<NotificationRegistrationResult> configureForUser(String? uid) async {
    _currentUserId = uid;
    if (!isSupported) {
      return const NotificationRegistrationResult(
        supported: false,
        enabled: false,
        permissionGranted: false,
      );
    }

    await init();
    await SettingsService.init();

    if (uid == null || uid.isEmpty || !SettingsService.cloudSyncEnabled) {
      return const NotificationRegistrationResult(
        supported: true,
        enabled: false,
        permissionGranted: false,
      );
    }

    await _savePreferences(uid);

    if (!SettingsService.checkInNotificationsEnabled) {
      await _markDeviceDisabled(uid);
      return const NotificationRegistrationResult(
        supported: true,
        enabled: false,
        permissionGranted: false,
      );
    }

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final permissionGranted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!permissionGranted) {
      await _markDeviceDisabled(
        uid,
        permissionStatus: settings.authorizationStatus.name,
      );
      return NotificationRegistrationResult(
        supported: true,
        enabled: true,
        permissionGranted: false,
        permissionStatus: settings.authorizationStatus.name,
      );
    }

    final token = await FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb
          ? const String.fromEnvironment('FCM_WEB_VAPID_KEY')
          : null,
    );
    if (token == null || token.isEmpty) {
      await _markDeviceDisabled(
        uid,
        permissionStatus: settings.authorizationStatus.name,
      );
      return NotificationRegistrationResult(
        supported: true,
        enabled: true,
        permissionGranted: true,
        permissionStatus: settings.authorizationStatus.name,
      );
    }

    await _saveDeviceRegistration(
      uid,
      token,
      permissionStatus: settings.authorizationStatus.name,
    );
    return NotificationRegistrationResult(
      supported: true,
      enabled: true,
      permissionGranted: true,
      permissionStatus: settings.authorizationStatus.name,
    );
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    _initialized = false;
  }

  Future<void> _savePreferences(String uid) {
    return _cloudPersistence.saveNotificationPreferences(
      uid,
      SettingsService.notificationPreferencesSnapshot(),
    );
  }

  Future<void> _saveDeviceRegistration(
    String uid,
    String token, {
    String? permissionStatus,
  }) async {
    final deviceId = await SettingsService.ensureNotificationDeviceId(
      () => const Uuid().v4(),
    );
    await _cloudPersistence.saveNotificationDevice(uid, deviceId, {
      'token': token,
      'platform': _platformName,
      'checkInEnabled': SettingsService.checkInNotificationsEnabled,
      'checkInTimeMinutes': SettingsService.checkInNotificationTimeMinutes,
      'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      'permissionStatus': permissionStatus ?? 'authorized',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _markDeviceDisabled(
    String uid, {
    String permissionStatus = 'disabled',
  }) async {
    final deviceId = await SettingsService.ensureNotificationDeviceId(
      () => const Uuid().v4(),
    );
    await _cloudPersistence.saveNotificationDevice(uid, deviceId, {
      'platform': _platformName,
      'checkInEnabled': false,
      'checkInTimeMinutes': SettingsService.checkInNotificationTimeMinutes,
      'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      'permissionStatus': permissionStatus,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  String get _platformName {
    if (kIsWeb) {
      return 'web';
    }
    return defaultTargetPlatform.name;
  }
}

class NotificationRegistrationResult {
  final bool supported;
  final bool enabled;
  final bool permissionGranted;
  final String? permissionStatus;

  const NotificationRegistrationResult({
    required this.supported,
    required this.enabled,
    required this.permissionGranted,
    this.permissionStatus,
  });
}
