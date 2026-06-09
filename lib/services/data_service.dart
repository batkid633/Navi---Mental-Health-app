import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../models/journal_entry.dart';
import '../models/audio_entry.dart';
import '../models/evaluation_feedback.dart';
import '../models/keyboard_session_entry.dart';
import '../models/sync_status.dart';
import '../config/backend_config.dart';
import 'cloud_persistence_service.dart';
import 'ml_export_services.dart';
import 'sentiment_service.dart';
import 'settings_service.dart';
import 'encryption_service.dart';

class DataService {
  static const _sharedJournalBoxName = 'journal_shared';
  static const _legacyJournalBoxName = 'journal';
  static const _sharedAudioBoxName = 'audio_shared';
  static const _legacyAudioBoxName = 'audio';
  static const _sharedFeedbackBoxName = 'evaluation_feedback_shared';
  static const _sharedKeyboardBoxName = 'keyboard_sessions_shared';

  String? _currentUserId;
  final EncryptionService _encryptionService = EncryptionService();
  late final CloudPersistenceService _cloudPersistence =
      CloudPersistenceService(encryptionService: _encryptionService);
  bool _journalCloudInitialized = false;
  bool _audioCloudInitialized = false;
  bool _feedbackCloudInitialized = false;
  bool _keyboardCloudInitialized = false;

  void setUserId(String userId) {
    if (_currentUserId != userId) {
      _currentUserId = userId;
      _journalCloudInitialized = false;
      _audioCloudInitialized = false;
      _feedbackCloudInitialized = false;
      _keyboardCloudInitialized = false;
    }
  }

  void clearUserId() {
    _currentUserId = null;
    _journalCloudInitialized = false;
    _audioCloudInitialized = false;
    _feedbackCloudInitialized = false;
    _keyboardCloudInitialized = false;
  }

  // Journal entries - local with user scoping.
  // If the user-specific box is empty, migrate legacy shared entries.
  Future<Box<JournalEntry>> getJournalBox() async {
    final boxName = _currentUserId == null
        ? '${_sharedJournalBoxName}_secure'
        : 'journal_secure_$_currentUserId';
    debugPrint(
      '[DataService] Opening journal box: $boxName (userId: $_currentUserId)',
    );
    final journalBox = await Hive.openBox<JournalEntry>(
      boxName,
      encryptionCipher: HiveAesCipher(
        await _encryptionService.hiveKeyForUser(_currentUserId),
      ),
    );
    debugPrint(
      '[DataService] Journal box opened with ${journalBox.length} entries',
    );

    // Always attempt migration to recover lost data.
    // This includes both authenticated users and unauthenticated users
    // using the shared journal box.
    await _migrateJournalData(journalBox);
    debugPrint(
      '[DataService] After migration: ${journalBox.length} total entries',
    );

    if (!_journalCloudInitialized) {
      _journalCloudInitialized = true;
      unawaited(_initializeJournalDataInBackground(journalBox));
    }
    return journalBox;
  }

  Future<void> _initializeJournalDataInBackground(
    Box<JournalEntry> journalBox,
  ) async {
    try {
      await _loadJournalEntriesFromCloud(
        journalBox,
      ).timeout(const Duration(seconds: 10));
      await _importHistoricalTrainingData(
        journalBox,
      ).timeout(const Duration(seconds: 8));
      await _scoreMissingSentiment(journalBox);
      await _retryQueuedJournalSync(
        journalBox,
      ).timeout(const Duration(seconds: 12));
      await _rewriteJournalEntriesToCloud(
        journalBox,
      ).timeout(const Duration(seconds: 12));
      await _syncDailyFeaturesToBackend(
        journalBox,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[DataService] Journal background initialization skipped: $e');
    }
  }

  Future<void> _migrateJournalData(Box<JournalEntry> journalBox) async {
    await _migrateFromLegacyBox(journalBox, _legacyJournalBoxName);
    await _migrateFromLegacyBox(journalBox, _sharedJournalBoxName);
    await _migrateFromLegacyBox(journalBox, 'journal_local-test-user');
    if (_currentUserId != null) {
      await _migrateFromLegacyBox(journalBox, 'journal_$_currentUserId');
    }
  }

  Future<void> _migrateFromLegacyBox(
    Box<JournalEntry> journalBox,
    String legacyBoxName,
  ) async {
    try {
      final legacyBox = await Hive.openBox<dynamic>(legacyBoxName);
      debugPrint(
        '[DataService] Checking legacy box "$legacyBoxName": ${legacyBox.length} entries',
      );
      if (legacyBox.isNotEmpty) {
        int migratedCount = 0;
        for (final key in legacyBox.keys) {
          final dynamic legacyValue = legacyBox.get(key);
          final entry = _convertToJournalEntry(legacyValue);
          if (entry != null) {
            await journalBox.put(entry.id, entry);
            migratedCount++;
          }
        }
        if (migratedCount > 0) {
          debugPrint(
            '[DataService] Migrated $migratedCount entries from "$legacyBoxName"',
          );
        }
      }
    } catch (e) {
      debugPrint('[DataService] Error migrating from "$legacyBoxName": $e');
    }
  }

  Future<void> _importHistoricalTrainingData(
    Box<JournalEntry> journalBox,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse('${BackendConfig.baseUrl}/journal/history'),
            headers: await BackendConfig.getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return;
      }

      final body = jsonDecode(response.body);
      final data = body is Map ? body['data'] : null;
      if (data is! List) {
        return;
      }

      var importedCount = 0;
      for (final item in data) {
        if (item is! Map) continue;
        final map = <String, dynamic>{};
        item.forEach((key, value) {
          if (key != null) {
            map[key.toString()] = value;
          }
        });
        final entry = JournalEntry.fromJson(map);
        if (!journalBox.containsKey(entry.id)) {
          entry.syncStatus = SyncStatus.pending;
          await journalBox.put(entry.id, entry);
          importedCount++;
        }
      }

      if (importedCount > 0) {
        debugPrint(
          '[DataService] Imported $importedCount historical training entries',
        );
      }
    } catch (e) {
      debugPrint('[DataService] Historical training import skipped: $e');
    }
  }

  Future<void> _scoreMissingSentiment(Box<JournalEntry> journalBox) async {
    final entriesToScore = journalBox.values
        .where(
          (entry) =>
              entry.sentimentScore == null && entry.text.trim().isNotEmpty,
        )
        .toList();

    if (entriesToScore.isNotEmpty) {
      debugPrint(
        '[DataService] Scoring sentiment for ${entriesToScore.length} entries',
      );
    }

    for (final entry in entriesToScore) {
      try {
        final sentiment = await SentimentService.analyze(entry.text);
        entry.sentimentScore = (sentiment['compound'] as num).toDouble();
        entry.sentimentLabel = sentiment['label'] as String?;
        entry.sentimentSource = sentiment['source']?.toString();
        entry.sentimentFallbackReason = sentiment['fallbackReason']?.toString();
        entry.syncStatus = SyncStatus.pending;
        await journalBox.put(entry.id, entry);
      } catch (e) {
        debugPrint(
          '[DataService] Sentiment scoring failed for entry ${entry.id}: $e',
        );
      }
    }
  }

  JournalEntry? _convertToJournalEntry(dynamic value) {
    if (value is JournalEntry) {
      return value;
    }
    if (value is Map) {
      try {
        final map = <String, dynamic>{};
        value.forEach((key, val) {
          if (key != null) {
            map[key.toString()] = val;
          }
        });
        return JournalEntry.fromJson(_normalizeJournalMap(map));
      } catch (_) {
        return null;
      }
    }
    if (value is String) {
      try {
        final decoded = value.isNotEmpty ? jsonDecode(value) : null;
        if (decoded is Map) {
          final map = <String, dynamic>{};
          decoded.forEach((key, val) {
            if (key != null) {
              map[key.toString()] = val;
            }
          });
          return JournalEntry.fromJson(_normalizeJournalMap(map));
        }
      } catch (_) {
        try {
          final repaired = value.replaceAll("'", '"');
          final decoded = jsonDecode(repaired);
          if (decoded is Map) {
            final map = <String, dynamic>{};
            decoded.forEach((key, val) {
              if (key != null) {
                map[key.toString()] = val;
              }
            });
            return JournalEntry.fromJson(_normalizeJournalMap(map));
          }
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _normalizeJournalMap(Map<String, dynamic> map) {
    final dateValue = map['date'] ?? map['createdAt'] ?? map['timestamp'];
    final dateString = dateValue is DateTime
        ? dateValue.toIso8601String()
        : dateValue is int
        ? DateTime.fromMillisecondsSinceEpoch(dateValue).toIso8601String()
        : dateValue?.toString() ?? DateTime.now().toIso8601String();

    final sentimentScoreValue = map['sentimentScore'] ?? map['sentiment_score'];
    final double? sentimentScore = sentimentScoreValue is num
        ? sentimentScoreValue.toDouble()
        : double.tryParse(sentimentScoreValue?.toString() ?? '');

    return {
      'id':
          map['id']?.toString() ??
          map['entryId']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      'date': dateString,
      'text': map['text']?.toString() ?? '',
      'sentimentLabel': map['sentimentLabel'] ?? map['sentiment_label'],
      'sentimentScore': sentimentScore,
      'sentimentSource': map['sentimentSource'] ?? map['sentiment_source'],
      'sentimentFallbackReason':
          map['sentimentFallbackReason'] ?? map['sentiment_fallback_reason'],
    };
  }

  // Audio entries - local with user scoping.
  // If the user-specific box is empty, try to fall back to a legacy shared box.
  Future<Box<AudioEntry>> getAudioBox() async {
    final boxName = _currentUserId == null
        ? '${_sharedAudioBoxName}_secure'
        : 'audio_secure_$_currentUserId';
    final audioBox = await Hive.openBox<AudioEntry>(
      boxName,
      encryptionCipher: HiveAesCipher(
        await _encryptionService.hiveKeyForUser(_currentUserId),
      ),
    );

    if (audioBox.isEmpty) {
      await _migrateAudioData(audioBox);
    }
    if (!_audioCloudInitialized) {
      await _loadAudioEntriesFromCloud(audioBox);
      await _retryQueuedAudioSync(audioBox);
      await _rewriteAudioEntriesToCloud(audioBox);
      _audioCloudInitialized = true;
    }

    return audioBox;
  }

  Future<Box<EvaluationFeedback>> getEvaluationFeedbackBox() async {
    final boxName = _currentUserId == null
        ? '${_sharedFeedbackBoxName}_secure'
        : 'evaluation_feedback_secure_$_currentUserId';
    final feedbackBox = await Hive.openBox<EvaluationFeedback>(
      boxName,
      encryptionCipher: HiveAesCipher(
        await _encryptionService.hiveKeyForUser(_currentUserId),
      ),
    );

    await _migrateEvaluationFeedbackData(feedbackBox);

    if (!_feedbackCloudInitialized) {
      await _loadEvaluationFeedbackFromCloud(feedbackBox);
      await _retryQueuedEvaluationFeedbackSync(feedbackBox);
      await _rewriteEvaluationFeedbackToCloud(feedbackBox);
      _feedbackCloudInitialized = true;
    }

    return feedbackBox;
  }

  Future<Box<KeyboardSessionEntry>> getKeyboardSessionBox() async {
    final boxName = _currentUserId == null
        ? '${_sharedKeyboardBoxName}_secure'
        : 'keyboard_sessions_secure_$_currentUserId';
    final keyboardBox = await Hive.openBox<KeyboardSessionEntry>(
      boxName,
      encryptionCipher: HiveAesCipher(
        await _encryptionService.hiveKeyForUser(_currentUserId),
      ),
    );

    await _migrateKeyboardSessionData(keyboardBox);

    if (!_keyboardCloudInitialized) {
      await _loadKeyboardSessionsFromCloud(keyboardBox);
      await _retryQueuedKeyboardSessionSync(keyboardBox);
      await _rewriteKeyboardSessionsToCloud(keyboardBox);
      _keyboardCloudInitialized = true;
    }

    return keyboardBox;
  }

  Future<void> _migrateKeyboardSessionData(
    Box<KeyboardSessionEntry> keyboardBox,
  ) async {
    await _migrateFromLegacyKeyboardBox(keyboardBox, _sharedKeyboardBoxName);
    if (_currentUserId != null) {
      await _migrateFromLegacyKeyboardBox(
        keyboardBox,
        'keyboard_sessions_$_currentUserId',
      );
    }
  }

  Future<void> _migrateFromLegacyKeyboardBox(
    Box<KeyboardSessionEntry> keyboardBox,
    String legacyBoxName,
  ) async {
    try {
      final legacyBox = await Hive.openBox<dynamic>(legacyBoxName);
      for (final key in legacyBox.keys) {
        final dynamic legacyValue = legacyBox.get(key);
        final entry = _convertToKeyboardSessionEntry(legacyValue);
        if (entry != null) {
          await keyboardBox.put(entry.id, entry);
        }
      }
    } catch (_) {
      // No legacy keyboard session data available; ignore.
    }
  }

  Future<void> _migrateEvaluationFeedbackData(
    Box<EvaluationFeedback> feedbackBox,
  ) async {
    await _migrateFromLegacyFeedbackBox(feedbackBox, _sharedFeedbackBoxName);
    if (_currentUserId != null) {
      await _migrateFromLegacyFeedbackBox(
        feedbackBox,
        'evaluation_feedback_$_currentUserId',
      );
    }
  }

  Future<void> _migrateFromLegacyFeedbackBox(
    Box<EvaluationFeedback> feedbackBox,
    String legacyBoxName,
  ) async {
    try {
      final legacyBox = await Hive.openBox<dynamic>(legacyBoxName);
      for (final key in legacyBox.keys) {
        final dynamic legacyValue = legacyBox.get(key);
        if (legacyValue is EvaluationFeedback) {
          await feedbackBox.put(legacyValue.id, legacyValue);
        }
      }
    } catch (_) {
      // No legacy feedback data available; ignore.
    }
  }

  Future<void> _migrateAudioData(Box<AudioEntry> audioBox) async {
    await _migrateFromLegacyAudioBox(audioBox, _legacyAudioBoxName);
    await _migrateFromLegacyAudioBox(audioBox, _sharedAudioBoxName);
    await _migrateFromLegacyAudioBox(audioBox, 'audio_local-test-user');
    if (_currentUserId != null) {
      await _migrateFromLegacyAudioBox(audioBox, 'audio_$_currentUserId');
    }
  }

  Future<void> _migrateFromLegacyAudioBox(
    Box<AudioEntry> audioBox,
    String legacyBoxName,
  ) async {
    try {
      final legacyBox = await Hive.openBox<dynamic>(legacyBoxName);
      if (legacyBox.isNotEmpty) {
        for (final key in legacyBox.keys) {
          final dynamic legacyValue = legacyBox.get(key);
          final entry = _convertToAudioEntry(legacyValue);
          if (entry != null) {
            await audioBox.put(entry.id, entry);
          }
        }
      }
    } catch (_) {
      // No legacy data available; ignore.
    }
  }

  AudioEntry? _convertToAudioEntry(dynamic value) {
    if (value is AudioEntry) {
      return value;
    }
    if (value is Map) {
      try {
        final map = <String, dynamic>{};
        value.forEach((key, val) {
          if (key != null) {
            map[key.toString()] = val;
          }
        });
        return AudioEntry.fromJson(map);
      } catch (_) {
        return null;
      }
    }
    if (value is String) {
      try {
        final decoded = value.isNotEmpty ? jsonDecode(value) : null;
        if (decoded is Map) {
          final map = <String, dynamic>{};
          decoded.forEach((key, val) {
            if (key != null) {
              map[key.toString()] = val;
            }
          });
          return AudioEntry.fromJson(map);
        }
      } catch (_) {
        try {
          final repaired = value.replaceAll("'", '"');
          final decoded = jsonDecode(repaired);
          if (decoded is Map) {
            final map = <String, dynamic>{};
            decoded.forEach((key, val) {
              if (key != null) {
                map[key.toString()] = val;
              }
            });
            return AudioEntry.fromJson(map);
          }
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  KeyboardSessionEntry? _convertToKeyboardSessionEntry(dynamic value) {
    if (value is KeyboardSessionEntry) {
      return value;
    }
    if (value is Map) {
      try {
        final map = <String, dynamic>{};
        value.forEach((key, val) {
          if (key != null) {
            map[key.toString()] = val;
          }
        });
        return KeyboardSessionEntry.fromJson(map);
      } catch (_) {
        return null;
      }
    }
    if (value is String) {
      try {
        final decoded = value.isNotEmpty ? jsonDecode(value) : null;
        if (decoded is Map) {
          final map = <String, dynamic>{};
          decoded.forEach((key, val) {
            if (key != null) {
              map[key.toString()] = val;
            }
          });
          return KeyboardSessionEntry.fromJson(map);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> syncJournalEntryToCloud(JournalEntry entry) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    _markPending(entry);
    try {
      final canonicalId = await _cloudPersistence.saveJournalEntry(uid, entry);
      entry.id = canonicalId;
      _markSynced(entry);
    } catch (e) {
      _markFailed(entry, e);
      debugPrint('[DataService] Journal cloud sync failed: $e');
    } finally {
      await _saveHiveObject(entry);
    }
  }

  Future<void> syncJournalFeaturesToBackend(
    Box<JournalEntry> journalBox,
  ) async {
    Box<AudioEntry>? audioBox;
    Box<KeyboardSessionEntry>? keyboardBox;
    try {
      audioBox = await getAudioBox();
    } catch (_) {
      audioBox = null;
    }
    try {
      keyboardBox = await getKeyboardSessionBox();
    } catch (_) {
      keyboardBox = null;
    }
    await _syncDailyFeaturesToBackend(
      journalBox,
      audioBox: audioBox,
      keyboardBox: keyboardBox,
    );
  }

  Future<void> syncAudioEntryToCloud(AudioEntry entry) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    _markPending(entry);
    try {
      final canonicalId = await _cloudPersistence.saveAudioEntry(uid, entry);
      entry.id = canonicalId;
      _markSynced(entry);
    } catch (e) {
      _markFailed(entry, e);
      debugPrint('[DataService] Audio cloud sync failed: $e');
    } finally {
      await _saveHiveObject(entry);
    }
  }

  Future<void> saveKeyboardSession(KeyboardSessionEntry entry) async {
    if (!SettingsService.keyboardTrackingEnabled) {
      return;
    }
    final keyboardBox = await getKeyboardSessionBox();
    _markPending(entry);
    await keyboardBox.put(entry.id, entry);
    await syncKeyboardSessionToCloud(entry);
    final journalBox = await getJournalBox();
    await _syncDailyFeaturesToBackend(journalBox, keyboardBox: keyboardBox);
  }

  Future<void> syncKeyboardSessionToCloud(KeyboardSessionEntry entry) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    _markPending(entry);
    try {
      final canonicalId = await _cloudPersistence.saveKeyboardSession(
        uid,
        entry,
      );
      entry.id = canonicalId;
      _markSynced(entry);
    } catch (e) {
      _markFailed(entry, e);
      debugPrint('[DataService] Keyboard session cloud sync failed: $e');
    } finally {
      await _saveHiveObject(entry);
    }
  }

  Future<void> saveEvaluationFeedback(EvaluationFeedback feedback) async {
    final feedbackBox = await getEvaluationFeedbackBox();
    feedback.updatedAt = DateTime.now();
    _markPending(feedback);
    await feedbackBox.put(feedback.id, feedback);
    await syncEvaluationFeedbackToCloud(feedback);
  }

  Future<void> syncEvaluationFeedbackToCloud(
    EvaluationFeedback feedback,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    _markPending(feedback);
    try {
      final canonicalId = await _cloudPersistence.saveEvaluationFeedback(
        uid,
        feedback,
      );
      feedback.id = canonicalId;
      _markSynced(feedback);
    } catch (e) {
      _markFailed(feedback, e);
      debugPrint('[DataService] Evaluation feedback cloud sync failed: $e');
    } finally {
      await _saveHiveObject(feedback);
    }
  }

  Future<void> loadFromCloud() async {
    final journalBox = await getJournalBox();
    final audioBox = await getAudioBox();
    final feedbackBox = await getEvaluationFeedbackBox();
    final keyboardBox = await getKeyboardSessionBox();
    await _loadJournalEntriesFromCloud(journalBox);
    await _loadAudioEntriesFromCloud(audioBox);
    await _loadEvaluationFeedbackFromCloud(feedbackBox);
    await _loadKeyboardSessionsFromCloud(keyboardBox);
  }

  Future<void> syncPrivacyConsentToCloud() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty || !SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      await _cloudPersistence.savePrivacyConsent(
        uid,
        SettingsService.privacyConsentSnapshot(),
      );
    } catch (e) {
      debugPrint('[DataService] Privacy consent cloud sync failed: $e');
    }
  }

  Future<Map<String, dynamic>> exportMyData() async {
    await SettingsService.init();
    final journalBox = await getJournalBox();
    final audioBox = await getAudioBox();
    final feedbackBox = await getEvaluationFeedbackBox();
    final keyboardBox = await getKeyboardSessionBox();
    final uid = _currentUserId;
    Map<String, dynamic>? cloudData;
    Map<String, dynamic>? backendData;

    if (uid != null && uid.isNotEmpty && SettingsService.cloudSyncEnabled) {
      try {
        cloudData = await _cloudPersistence.exportUserData(uid);
      } catch (e) {
        cloudData = {'error': e.toString()};
      }
    }

    try {
      final response = await http.get(
        Uri.parse('${BackendConfig.baseUrl}/data/export'),
        headers: await BackendConfig.getAuthHeaders(),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        backendData = jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        backendData = {'error': 'Backend returned ${response.statusCode}'};
      }
    } catch (e) {
      backendData = {'error': e.toString()};
    }

    return {
      'format': 'navi-personal-data-export-v1',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'userId': uid,
      'settings': SettingsService.privacyConsentSnapshot(),
      'local': {
        'journalEntries': journalBox.values
            .map((entry) => entry.toJson())
            .toList(),
        'audioEntries': audioBox.values.map((entry) => entry.toJson()).toList(),
        'evaluationFeedback': feedbackBox.values
            .map((feedback) => feedback.toJson())
            .toList(),
        'keyboardSessions': keyboardBox.values
            .map((session) => session.toJson())
            .toList(),
      },
      'cloud': cloudData,
      'backend': backendData,
    };
  }

  Future<String> exportMyDataJson() async {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(await exportMyData());
  }

  Future<String> exportEncryptionRecoveryKit(String passphrase) {
    return _encryptionService.exportRecoveryKit(_currentUserId, passphrase);
  }

  Future<void> importEncryptionRecoveryKit(
    String passphrase,
    String recoveryKit,
  ) {
    return _encryptionService.importRecoveryKit(
      _currentUserId,
      passphrase,
      recoveryKit,
    );
  }

  Future<void> deleteMyData() async {
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      try {
        await _cloudPersistence.deleteUserData(uid);
      } catch (e) {
        debugPrint('[DataService] Cloud account data delete failed: $e');
      }
      try {
        await http.delete(
          Uri.parse('${BackendConfig.baseUrl}/data/delete'),
          headers: await BackendConfig.getAuthHeaders(),
        );
      } catch (e) {
        debugPrint('[DataService] Backend account data delete failed: $e');
      }
    }

    final journalBox = await getJournalBox();
    final audioBox = await getAudioBox();
    final feedbackBox = await getEvaluationFeedbackBox();
    final keyboardBox = await getKeyboardSessionBox();
    await journalBox.clear();
    await audioBox.clear();
    await feedbackBox.clear();
    await keyboardBox.clear();
    await SettingsService.resetPrivacyControls();
    _journalCloudInitialized = false;
    _audioCloudInitialized = false;
    _feedbackCloudInitialized = false;
    _keyboardCloudInitialized = false;
  }

  Future<void> deleteJournalEntry(JournalEntry entry) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      await _cloudPersistence.deleteJournalEntry(uid, entry.id);
    } catch (e) {
      debugPrint('[DataService] Journal cloud delete failed: $e');
    }
  }

  Future<void> deleteAudioEntry(AudioEntry entry) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      await _cloudPersistence.deleteAudioEntry(uid, entry.id);
    } catch (e) {
      debugPrint('[DataService] Audio cloud delete failed: $e');
    }
  }

  Future<void> deleteKeyboardSession(KeyboardSessionEntry entry) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      await _cloudPersistence.deleteKeyboardSession(uid, entry.id);
    } catch (e) {
      debugPrint('[DataService] Keyboard session cloud delete failed: $e');
    }
  }

  Future<void> deleteEvaluationFeedback(EvaluationFeedback feedback) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      await _cloudPersistence.deleteEvaluationFeedback(uid, feedback.id);
    } catch (e) {
      debugPrint('[DataService] Evaluation feedback cloud delete failed: $e');
    }
  }

  Future<void> _loadJournalEntriesFromCloud(
    Box<JournalEntry> journalBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      final cloudEntries = await _cloudPersistence.loadJournalEntries(uid);
      final dedupedEntries = _dedupeJournalEntries(cloudEntries);
      for (final entry in dedupedEntries) {
        _markSynced(entry);
        await journalBox.put(entry.id, entry);
      }
      if (dedupedEntries.isNotEmpty) {
        debugPrint(
          '[DataService] Loaded ${dedupedEntries.length} journal entries from cloud',
        );
      }
    } catch (e) {
      debugPrint('[DataService] Journal cloud load skipped: $e');
    }
  }

  Future<void> _loadAudioEntriesFromCloud(Box<AudioEntry> audioBox) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      final cloudEntries = await _cloudPersistence.loadAudioEntries(uid);
      final dedupedEntries = _dedupeAudioEntries(cloudEntries);
      for (final entry in dedupedEntries) {
        _markSynced(entry);
        await audioBox.put(entry.id, entry);
      }
      if (dedupedEntries.isNotEmpty) {
        debugPrint(
          '[DataService] Loaded ${dedupedEntries.length} audio entries from cloud',
        );
      }
    } catch (e) {
      debugPrint('[DataService] Audio cloud load skipped: $e');
    }
  }

  Future<void> _loadEvaluationFeedbackFromCloud(
    Box<EvaluationFeedback> feedbackBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      final cloudFeedback = await _cloudPersistence.loadEvaluationFeedback(uid);
      for (final feedback in cloudFeedback) {
        _markSynced(feedback);
        await feedbackBox.put(feedback.id, feedback);
      }
      if (cloudFeedback.isNotEmpty) {
        debugPrint(
          '[DataService] Loaded ${cloudFeedback.length} evaluation feedback records from cloud',
        );
      }
    } catch (e) {
      debugPrint('[DataService] Evaluation feedback cloud load skipped: $e');
    }
  }

  Future<void> _loadKeyboardSessionsFromCloud(
    Box<KeyboardSessionEntry> keyboardBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      final cloudEntries = await _cloudPersistence.loadKeyboardSessions(uid);
      final dedupedEntries = _dedupeKeyboardSessions(cloudEntries);
      for (final entry in dedupedEntries) {
        _markSynced(entry);
        await keyboardBox.put(entry.id, entry);
      }
      if (dedupedEntries.isNotEmpty) {
        debugPrint(
          '[DataService] Loaded ${dedupedEntries.length} keyboard sessions from cloud',
        );
      }
    } catch (e) {
      debugPrint('[DataService] Keyboard session cloud load skipped: $e');
    }
  }

  Future<void> _retryQueuedJournalSync(Box<JournalEntry> journalBox) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    for (final entry in journalBox.values) {
      if (_shouldRetry(entry.syncStatus, entry.nextRetryAt)) {
        final originalKey = entry.key;
        final originalId = entry.id;
        await syncJournalEntryToCloud(entry);
        if (entry.id != originalId && originalKey != null) {
          await journalBox.put(entry.id, entry);
          await journalBox.delete(originalKey);
        }
      }
    }
  }

  Future<void> _rewriteJournalEntriesToCloud(
    Box<JournalEntry> journalBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty || !SettingsService.cloudSyncEnabled) {
      return;
    }
    for (final entry in journalBox.values) {
      await syncJournalEntryToCloud(entry);
    }
  }

  Future<void> _syncDailyFeaturesToBackend(
    Box<JournalEntry> journalBox, {
    Box<AudioEntry>? audioBox,
    Box<KeyboardSessionEntry>? keyboardBox,
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.researchDataSharingEnabled) {
      return;
    }

    final records = MLExportService.buildDailyFeatureRecords(
      journalBox,
      audioEntries: audioBox?.values ?? const [],
      keyboardSessions: keyboardBox?.values ?? const [],
    );
    if (records.isEmpty) {
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse('${BackendConfig.baseUrl}/ml/daily-features'),
            headers: await BackendConfig.getAuthHeaders(),
            body: jsonEncode({'records': records}),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode >= 400) {
        debugPrint(
          '[DataService] Daily feature sync failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[DataService] Daily feature sync skipped: $e');
    }
  }

  Future<void> _retryQueuedAudioSync(Box<AudioEntry> audioBox) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    for (final entry in audioBox.values) {
      if (_shouldRetry(entry.syncStatus, entry.nextRetryAt)) {
        final originalKey = entry.key;
        final originalId = entry.id;
        await syncAudioEntryToCloud(entry);
        if (entry.id != originalId && originalKey != null) {
          await audioBox.put(entry.id, entry);
          await audioBox.delete(originalKey);
        }
      }
    }
  }

  Future<void> _rewriteAudioEntriesToCloud(Box<AudioEntry> audioBox) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty || !SettingsService.cloudSyncEnabled) {
      return;
    }
    for (final entry in audioBox.values) {
      await syncAudioEntryToCloud(entry);
    }
  }

  Future<void> _retryQueuedKeyboardSessionSync(
    Box<KeyboardSessionEntry> keyboardBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    for (final entry in keyboardBox.values) {
      if (_shouldRetry(entry.syncStatus, entry.nextRetryAt)) {
        final originalKey = entry.key;
        final originalId = entry.id;
        await syncKeyboardSessionToCloud(entry);
        if (entry.id != originalId && originalKey != null) {
          await keyboardBox.put(entry.id, entry);
          await keyboardBox.delete(originalKey);
        }
      }
    }
  }

  Future<void> _rewriteKeyboardSessionsToCloud(
    Box<KeyboardSessionEntry> keyboardBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty || !SettingsService.cloudSyncEnabled) {
      return;
    }
    for (final entry in keyboardBox.values) {
      await syncKeyboardSessionToCloud(entry);
    }
  }

  Future<void> _retryQueuedEvaluationFeedbackSync(
    Box<EvaluationFeedback> feedbackBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (!SettingsService.cloudSyncEnabled) {
      return;
    }
    for (final feedback in feedbackBox.values) {
      if (_shouldRetry(feedback.syncStatus, feedback.nextRetryAt)) {
        final originalKey = feedback.key;
        final originalId = feedback.id;
        await syncEvaluationFeedbackToCloud(feedback);
        if (feedback.id != originalId && originalKey != null) {
          await feedbackBox.put(feedback.id, feedback);
          await feedbackBox.delete(originalKey);
        }
      }
    }
  }

  Future<void> _rewriteEvaluationFeedbackToCloud(
    Box<EvaluationFeedback> feedbackBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty || !SettingsService.cloudSyncEnabled) {
      return;
    }
    for (final feedback in feedbackBox.values) {
      await syncEvaluationFeedbackToCloud(feedback);
    }
  }

  List<JournalEntry> _dedupeJournalEntries(List<JournalEntry> entries) {
    final byKey = <String, JournalEntry>{};
    for (final entry in entries) {
      final existing = byKey[entry.dedupeKey];
      if (existing == null || entry.date.isAfter(existing.date)) {
        byKey[entry.dedupeKey] = entry;
      }
    }
    return byKey.values.toList();
  }

  List<AudioEntry> _dedupeAudioEntries(List<AudioEntry> entries) {
    final byKey = <String, AudioEntry>{};
    for (final entry in entries) {
      final existing = byKey[entry.dedupeKey];
      if (existing == null || entry.date.isAfter(existing.date)) {
        byKey[entry.dedupeKey] = entry;
      }
    }
    return byKey.values.toList();
  }

  List<KeyboardSessionEntry> _dedupeKeyboardSessions(
    List<KeyboardSessionEntry> entries,
  ) {
    final byKey = <String, KeyboardSessionEntry>{};
    for (final entry in entries) {
      final existing = byKey[entry.dedupeKey];
      if (existing == null || entry.endedAt.isAfter(existing.endedAt)) {
        byKey[entry.dedupeKey] = entry;
      }
    }
    return byKey.values.toList();
  }

  bool _shouldRetry(String status, DateTime? nextRetryAt) {
    if (!SyncStatus.canRetry(status)) {
      return false;
    }
    return nextRetryAt == null || !nextRetryAt.isAfter(DateTime.now());
  }

  void _markPending(dynamic entry) {
    entry.syncStatus = SyncStatus.pending;
    entry.lastSyncError = null;
  }

  void _markSynced(dynamic entry) {
    entry.syncStatus = SyncStatus.synced;
    entry.syncAttempts = 0;
    entry.lastSyncError = null;
    entry.lastSyncedAt = DateTime.now();
    entry.nextRetryAt = null;
  }

  void _markFailed(dynamic entry, Object error) {
    final attempts = (entry.syncAttempts as int) + 1;
    final delaySeconds = _retryDelaySeconds(attempts);
    entry.syncStatus = SyncStatus.failed;
    entry.syncAttempts = attempts;
    entry.lastSyncError = error.toString();
    entry.nextRetryAt = DateTime.now().add(Duration(seconds: delaySeconds));
  }

  int _retryDelaySeconds(int attempts) {
    final delay = 30 * (1 << (attempts - 1).clamp(0, 6));
    return delay.clamp(30, 1800);
  }

  Future<void> _saveHiveObject(dynamic entry) async {
    if (entry is HiveObject && entry.isInBox) {
      await entry.save();
    }
  }
}
