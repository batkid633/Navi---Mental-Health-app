import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

class AnalyticsService {
  AnalyticsService._();

  static const String schemaVersion = 'navi_product_event_v2';

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final String _sessionId = _newId('session');

  static Future<void> track(
    String name, {
    Map<String, Object?> properties = const {},
  }) async {
    final uid = _auth.currentUser?.uid;
    final safeName = _safeEventName(name);
    final safeProperties = _safeProperties(properties);

    debugPrint('[Analytics] $safeName $safeProperties');

    if (uid == null || uid.isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    final eventId = _newId(safeName);
    unawaited(
      _sendToBackend(
        eventId: eventId,
        name: safeName,
        properties: safeProperties,
        clientRecordedAt: now,
      ),
    );

    try {
      final dayKey = now.toIso8601String().substring(0, 10);
      final userRef = _firestore.collection('users').doc(uid);

      await userRef.collection('analytics_events').add({
        'eventId': eventId,
        'name': safeName,
        'properties': safeProperties,
        'platform': _platformLabel,
        'sessionId': _sessionId,
        'recordedAt': FieldValue.serverTimestamp(),
        'clientRecordedAt': now.toIso8601String(),
      });

      await userRef.collection('daily_analytics').doc(dayKey).set({
        'date': dayKey,
        'eventCounts.$safeName': FieldValue.increment(1),
        'lastEventAt': FieldValue.serverTimestamp(),
        'platforms.$_platformLabel': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('[Analytics] track failed for $safeName: $error');
    }
  }

  static Future<void> _sendToBackend({
    required String eventId,
    required String name,
    required Map<String, Object?> properties,
    required DateTime clientRecordedAt,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${BackendConfig.baseUrl}/analytics/events'),
            headers: await BackendConfig.getAuthHeaders(),
            body: jsonEncode({
              'events': [
                {
                  'event_id': eventId,
                  'name': name,
                  'properties': properties,
                  'platform': _platformLabel,
                  'app_version': _appVersion,
                  'schema_version': schemaVersion,
                  'session_id': _sessionId,
                  'client_recorded_at': clientRecordedAt.toIso8601String(),
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[Analytics] backend ingest failed for $name: ${response.statusCode}',
        );
      }
    } catch (error) {
      debugPrint('[Analytics] backend ingest skipped for $name: $error');
    }
  }

  static String _safeEventName(String name) {
    final normalized = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (normalized.isEmpty) {
      return 'unknown_event';
    }
    return normalized.length > 60 ? normalized.substring(0, 60) : normalized;
  }

  static Map<String, Object?> _safeProperties(Map<String, Object?> input) {
    final output = <String, Object?>{};
    for (final entry in input.entries) {
      final key = _safeEventName(entry.key);
      final value = entry.value;
      if (value == null || value is String || value is num || value is bool) {
        output[key] = value is String && value.length > 120
            ? value.substring(0, 120)
            : value;
      }
    }
    return output;
  }

  static String get _platformLabel {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.name;
  }

  static String get _appVersion {
    return const String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  }

  static String _newId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    return '${_safeEventName(prefix)}_${now}_$random';
  }
}
