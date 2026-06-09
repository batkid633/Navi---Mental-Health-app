import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/audio_entry.dart';
import '../models/evaluation_feedback.dart';
import '../models/journal_entry.dart';
import '../models/keyboard_session_entry.dart';
import '../models/sync_status.dart';
import 'encryption_service.dart';
import '../utils/audio_bytes.dart';

class CloudPersistenceService {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final EncryptionService _encryptionService;

  CloudPersistenceService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    EncryptionService? encryptionService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _encryptionService = encryptionService ?? EncryptionService();

  CollectionReference<Map<String, dynamic>> _journalCollection(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('journal_entries');
  }

  CollectionReference<Map<String, dynamic>> _audioCollection(String uid) {
    return _firestore.collection('users').doc(uid).collection('audio_entries');
  }

  CollectionReference<Map<String, dynamic>> _feedbackCollection(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('evaluation_feedback');
  }

  CollectionReference<Map<String, dynamic>> _keyboardSessionCollection(
    String uid,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('keyboard_sessions');
  }

  DocumentReference<Map<String, dynamic>> _privacyConsentDocument(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('privacy_consent');
  }

  CollectionReference<Map<String, dynamic>> _consentRecordsCollection(
    String uid,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('consent_records');
  }

  CollectionReference<Map<String, dynamic>> _notificationDevicesCollection(
    String uid,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notification_devices');
  }

  DocumentReference<Map<String, dynamic>> _notificationPreferencesDocument(
    String uid,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('notification_preferences');
  }

  Future<List<JournalEntry>> loadJournalEntries(String uid) async {
    final snapshot = await _journalCollection(
      uid,
    ).orderBy('date', descending: false).get();
    final entries = <JournalEntry>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final payload = data['encryption'] is Map
          ? await _encryptionService.decryptJson(uid, data)
          : data;
      entries.add(
        JournalEntry.fromJson({
          'id': doc.id,
          'date': _dateToIsoString(data['date']),
          'text': payload['text'],
          'sentimentLabel': payload['sentimentLabel'],
          'sentimentScore': payload['sentimentScore'],
          'sentimentSource': payload['sentimentSource'],
          'sentimentFallbackReason': payload['sentimentFallbackReason'],
          'syncStatus': SyncStatus.synced,
          'syncAttempts': 0,
          'lastSyncedAt': _dateToIsoString(data['updatedAt']),
        }),
      );
    }
    return entries;
  }

  Future<String> saveJournalEntry(String uid, JournalEntry entry) async {
    final canonicalId = entry.id.startsWith('journal_')
        ? entry.id
        : 'journal_${DateTime.now().microsecondsSinceEpoch}';
    final encrypted = await _encryptionService.encryptJson(uid, {
      'text': entry.text,
      'sentimentLabel': entry.sentimentLabel,
      'sentimentScore': entry.sentimentScore,
      'sentimentSource': entry.sentimentSource,
      'sentimentFallbackReason': entry.sentimentFallbackReason,
    });
    await _journalCollection(uid).doc(canonicalId).set({
      'date': Timestamp.fromDate(entry.date),
      ...encrypted,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return canonicalId;
  }

  Future<List<AudioEntry>> loadAudioEntries(String uid) async {
    final snapshot = await _audioCollection(
      uid,
    ).orderBy('date', descending: false).get();
    final entries = <AudioEntry>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final payload = data['encryption'] is Map
          ? await _encryptionService.decryptJson(uid, data)
          : data;
      entries.add(
        AudioEntry.fromJson({
          'id': doc.id,
          'date': _dateToIsoString(data['date']),
          'filePath':
              payload['downloadUrl'] ??
              payload['filePath'] ??
              data['storagePath'] ??
              '',
          'fileName': payload['fileName'] ?? '',
          'duration': payload['duration'] ?? 0,
          'transcription': payload['transcription'],
          'mode': payload['mode'] ?? 'emotional_venting',
          'moodLabel': payload['moodLabel'],
          'isTraining': payload['isTraining'] ?? false,
          'storagePath': data['storagePath'],
          'downloadUrl': payload['downloadUrl'],
          'syncStatus': SyncStatus.synced,
          'syncAttempts': 0,
          'lastSyncedAt': _dateToIsoString(data['updatedAt']),
        }),
      );
    }
    return entries;
  }

  Future<String> saveAudioEntry(String uid, AudioEntry entry) async {
    String? storagePath;
    String? downloadUrl;
    final canonicalId = entry.id.startsWith('audio_')
        ? entry.id
        : 'audio_${DateTime.now().microsecondsSinceEpoch}';

    try {
      final bytes = await readAudioBytes(entry.filePath);
      storagePath = 'users/$uid/audio/$canonicalId/blob.enc';
      final ref = _storage.ref(storagePath);
      await ref.putData(
        Uint8List.fromList(await _encryptionService.encryptBytes(uid, bytes)),
        SettableMetadata(
          contentType: 'application/octet-stream',
          customMetadata: {
            'encryption': EncryptionService.algorithmName,
            'schemaVersion': EncryptionService.schemaVersion.toString(),
          },
        ),
      );
      downloadUrl = await ref.getDownloadURL();
    } catch (_) {
      // Metadata still syncs if the local file/blob is no longer available.
    }
    storagePath ??= entry.storagePath;

    final encrypted = await _encryptionService.encryptJson(uid, {
      'fileName': entry.fileName,
      'filePath': entry.filePath,
      'duration': entry.duration,
      'transcription': entry.transcription,
      'mode': entry.mode,
      'moodLabel': entry.moodLabel,
      'isTraining': entry.isTraining,
      'downloadUrl': downloadUrl,
    });
    final data = {
      'date': Timestamp.fromDate(entry.date),
      ...encrypted,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (storagePath != null) {
      data['storagePath'] = storagePath;
      entry.storagePath = storagePath;
    }
    if (downloadUrl != null) {
      entry.downloadUrl = downloadUrl;
    }
    await _audioCollection(uid).doc(canonicalId).set(data);
    return canonicalId;
  }

  Future<List<EvaluationFeedback>> loadEvaluationFeedback(String uid) async {
    final snapshot = await _feedbackCollection(
      uid,
    ).orderBy('updatedAt', descending: false).get();
    final feedback = <EvaluationFeedback>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final payload = data['encryption'] is Map
          ? await _encryptionService.decryptJson(uid, data)
          : data;
      feedback.add(
        EvaluationFeedback.fromJson({
          'id': doc.id,
          ...payload,
          'createdAt': _dateToIsoString(data['createdAt']),
          'updatedAt': _dateToIsoString(data['updatedAt']),
          'lastSyncedAt': _dateToIsoString(data['updatedAt']),
          'syncStatus': SyncStatus.synced,
          'syncAttempts': 0,
        }),
      );
    }
    return feedback;
  }

  Future<String> saveEvaluationFeedback(
    String uid,
    EvaluationFeedback feedback,
  ) async {
    final canonicalId = feedback.id.startsWith('feedback_')
        ? feedback.id
        : EvaluationFeedback.canonicalId(
            feedback.targetType,
            feedback.targetDate,
          );
    final encrypted = await _encryptionService.encryptJson(uid, {
      'journalEntryId': feedback.journalEntryId,
      'predictedDelta': feedback.predictedDelta,
      'confidence': feedback.confidence,
      'modelVersion': feedback.modelVersion,
      'insight': feedback.insight,
      'accuracyRating': feedback.accuracyRating,
      'helpfulnessRating': feedback.helpfulnessRating,
      'actualMoodDirection': feedback.actualMoodDirection,
      'note': feedback.note,
    });
    await _feedbackCollection(uid).doc(canonicalId).set({
      'targetType': feedback.targetType,
      'targetDate': feedback.targetDate,
      'createdAt': Timestamp.fromDate(feedback.createdAt),
      'updatedAt': Timestamp.fromDate(feedback.updatedAt),
      ...encrypted,
      'serverUpdatedAt': FieldValue.serverTimestamp(),
    });
    return canonicalId;
  }

  Future<List<KeyboardSessionEntry>> loadKeyboardSessions(String uid) async {
    final snapshot = await _keyboardSessionCollection(
      uid,
    ).orderBy('startedAt', descending: false).get();
    final entries = <KeyboardSessionEntry>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final payload = data['encryption'] is Map
          ? await _encryptionService.decryptJson(uid, data)
          : data;
      entries.add(
        KeyboardSessionEntry.fromJson({
          'id': doc.id,
          ...payload,
          'startedAt': _dateToIsoString(data['startedAt']),
          'endedAt': _dateToIsoString(data['endedAt']),
          'syncStatus': SyncStatus.synced,
          'syncAttempts': 0,
          'lastSyncedAt': _dateToIsoString(data['updatedAt']),
        }),
      );
    }
    return entries;
  }

  Future<String> saveKeyboardSession(
    String uid,
    KeyboardSessionEntry entry,
  ) async {
    final canonicalId = entry.id.startsWith('keyboard_')
        ? entry.id
        : KeyboardSessionEntry.canonicalId(entry.startedAt);
    final encrypted = await _encryptionService.encryptJson(uid, {
      'fieldContext': entry.fieldContext,
      'platform': entry.platform,
      'eventCount': entry.eventCount,
      'charsEstimated': entry.charsEstimated,
      'backspaceCount': entry.backspaceCount,
      'burstCount': entry.burstCount,
      'pauseMeanMs': entry.pauseMeanMs,
      'pauseStdMs': entry.pauseStdMs,
      'activeSeconds': entry.activeSeconds,
      'correctionRate': entry.correctionRate,
      'typingSpeedCpm': entry.typingSpeedCpm,
    });
    await _keyboardSessionCollection(uid).doc(canonicalId).set({
      'startedAt': Timestamp.fromDate(entry.startedAt),
      'endedAt': Timestamp.fromDate(entry.endedAt),
      ...encrypted,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return canonicalId;
  }

  Future<void> deleteJournalEntry(String uid, String entryId) {
    return _journalCollection(uid).doc(entryId).delete();
  }

  Future<void> deleteAudioEntry(String uid, String entryId) async {
    final doc = await _audioCollection(uid).doc(entryId).get();
    final storagePath = doc.data()?['storagePath'] as String?;
    await _audioCollection(uid).doc(entryId).delete();
    if (storagePath != null && storagePath.isNotEmpty) {
      await _storage.ref(storagePath).delete();
    }
  }

  Future<void> deleteEvaluationFeedback(String uid, String feedbackId) {
    return _feedbackCollection(uid).doc(feedbackId).delete();
  }

  Future<void> deleteKeyboardSession(String uid, String entryId) {
    return _keyboardSessionCollection(uid).doc(entryId).delete();
  }

  Future<void> savePrivacyConsent(
    String uid,
    Map<String, dynamic> preferences,
  ) async {
    final recordedAt = FieldValue.serverTimestamp();
    final encrypted = await _encryptionService.encryptJson(uid, preferences);
    await _privacyConsentDocument(
      uid,
    ).set({...encrypted, 'serverUpdatedAt': recordedAt});
    await _consentRecordsCollection(uid).add({
      ...encrypted,
      'recordType': 'privacy_consent_snapshot',
      'serverRecordedAt': recordedAt,
    });
  }

  Future<void> saveNotificationPreferences(
    String uid,
    Map<String, dynamic> preferences,
  ) async {
    await _notificationPreferencesDocument(
      uid,
    ).set({...preferences, 'serverUpdatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> saveNotificationDevice(
    String uid,
    String deviceId,
    Map<String, dynamic> device,
  ) async {
    await _notificationDevicesCollection(uid).doc(deviceId).set({
      ...device,
      'serverUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteNotificationDevice(String uid, String deviceId) {
    return _notificationDevicesCollection(uid).doc(deviceId).delete();
  }

  Future<Map<String, dynamic>> exportUserData(String uid) async {
    final profileSnapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('profile')
        .get();
    final featureSnapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('backend_ml_features')
        .get();
    final analyticsSnapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('daily_analytics')
        .get();
    final audioFiles = await _listStorageItems('users/$uid/audio');

    return {
      'firestore': {
        'journalEntries': (await loadJournalEntries(
          uid,
        )).map((entry) => entry.toJson()).toList(),
        'audioEntries': (await loadAudioEntries(
          uid,
        )).map((entry) => entry.toJson()).toList(),
        'evaluationFeedback': (await loadEvaluationFeedback(
          uid,
        )).map((feedback) => feedback.toJson()).toList(),
        'keyboardSessions': (await loadKeyboardSessions(
          uid,
        )).map((session) => session.toJson()).toList(),
        'profile': {
          for (final doc in profileSnapshot.docs) doc.id: _jsonSafe(doc.data()),
        },
        'notificationDevices': await _exportCollection(
          _notificationDevicesCollection(uid),
        ),
        'consentRecords': await _exportCollection(
          _consentRecordsCollection(uid),
        ),
        'backendMlFeatures': {
          for (final doc in featureSnapshot.docs) doc.id: _jsonSafe(doc.data()),
        },
        'dailyAnalytics': {
          for (final doc in analyticsSnapshot.docs)
            doc.id: _jsonSafe(doc.data()),
        },
      },
      'storage': {'audioFiles': audioFiles},
    };
  }

  Future<void> deleteUserData(String uid) async {
    await _deleteCollection(_journalCollection(uid));
    await _deleteCollection(_audioCollection(uid));
    await _deleteCollection(_feedbackCollection(uid));
    await _deleteCollection(_keyboardSessionCollection(uid));
    await _deleteCollection(
      _firestore.collection('users').doc(uid).collection('profile'),
    );
    await _deleteCollection(_notificationDevicesCollection(uid));
    await _deleteCollection(_consentRecordsCollection(uid));
    await _deleteCollection(
      _firestore.collection('users').doc(uid).collection('backend_ml_features'),
    );
    await _deleteCollection(
      _firestore.collection('users').doc(uid).collection('analytics_events'),
    );
    await _deleteCollection(
      _firestore.collection('users').doc(uid).collection('daily_analytics'),
    );
    await _deleteStoragePrefix('users/$uid/audio');
    await _firestore.collection('users').doc(uid).delete();
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    while (true) {
      final snapshot = await collection.limit(100).get();
      if (snapshot.docs.isEmpty) {
        return;
      }
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<Map<String, dynamic>> _exportCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snapshot = await collection.get();
    return {for (final doc in snapshot.docs) doc.id: _jsonSafe(doc.data())};
  }

  Future<List<Map<String, dynamic>>> _listStorageItems(String prefix) async {
    try {
      final result = await _storage.ref(prefix).listAll();
      return result.items
          .map((item) => {'name': item.name, 'fullPath': item.fullPath})
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _deleteStoragePrefix(String prefix) async {
    try {
      final result = await _storage.ref(prefix).listAll();
      for (final item in result.items) {
        await item.delete();
      }
      for (final child in result.prefixes) {
        await _deleteStoragePrefix(child.fullPath);
      }
    } catch (_) {
      // Missing storage prefixes are already deleted from the user's view.
    }
  }

  String _dateToIsoString(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value).toIso8601String();
    }
    return value?.toString() ?? DateTime.now().toIso8601String();
  }

  dynamic _jsonSafe(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_jsonSafe).toList();
    }
    return value;
  }
}
