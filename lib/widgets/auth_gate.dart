import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../services/data_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import 'auth_screen.dart';
import '../pages/onboarding_consent_page.dart';
import '../main.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  final DataService _dataService = DataService();
  bool _localTestMode = false;
  String? _lastNotificationUserId;

  void _syncNotificationsForUser(String? uid) {
    if (_lastNotificationUserId == uid) {
      return;
    }
    _lastNotificationUserId = uid;
    NotificationService.instance.configureForUser(uid).then((_) {}).catchError((
      error,
    ) {
      debugPrint('[AuthGate] Notification sync failed: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user != null) {
          _dataService.setUserId(user.uid);
          _syncNotificationsForUser(user.uid);
          if (!SettingsService.consentCompleted) {
            return OnboardingConsentPage(
              dataService: _dataService,
              onComplete: () {
                setState(() {});
              },
            );
          }
          return NaviHome(dataService: _dataService, authService: _authService);
        }

        if (_localTestMode) {
          _dataService.clearUserId();
          _syncNotificationsForUser(null);
          if (!SettingsService.consentCompleted) {
            return OnboardingConsentPage(
              dataService: _dataService,
              onComplete: () {
                setState(() {});
              },
            );
          }
          return NaviHome(
            dataService: _dataService,
            authService: _authService,
            onSignOut: () async {
              setState(() {
                _localTestMode = false;
              });
            },
          );
        }

        _dataService.clearUserId();
        _syncNotificationsForUser(null);
        return AuthScreen(
          authService: _authService,
          onContinueInLocalTestMode: kDebugMode
              ? () {
                  AnalyticsService.track('local_test_mode_started');
                  setState(() {
                    _localTestMode = true;
                  });
                }
              : null,
        );
      },
    );
  }
}
