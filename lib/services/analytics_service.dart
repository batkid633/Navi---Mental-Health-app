import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

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

    try {
      final now = DateTime.now().toUtc();
      final dayKey = now.toIso8601String().substring(0, 10);
      final userRef = _firestore.collection('users').doc(uid);

      await userRef.collection('analytics_events').add({
        'name': safeName,
        'properties': safeProperties,
        'platform': _platformLabel,
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
}
