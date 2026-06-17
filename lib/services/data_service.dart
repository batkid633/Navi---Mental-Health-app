import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../models/journal_entry.dart';
import '../models/audio_entry.dart';
import '../models/evaluation_feedback.dart';
import '../models/keyboard_session_entry.dart';
import '../models/navi_beacon_sample.dart';
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
  static const _sharedBeaconBoxName = 'navi_beacon_samples_shared';

  String? _currentUserId;
  final EncryptionService _encryptionService = EncryptionService();
  late final CloudPersistenceService _cloudPersistence =
      CloudPersistenceService(encryptionService: _encryptionService);
  bool _journalCloudInitialized = false;
  bool _audioCloudInitialized = false;
  bool _feedbackCloudInitialized = false;
  bool _keyboardCloudInitialized = false;
  bool _beaconInitialized = false;
  String? _accountCloudKeyInitializedForUid;

  void setUserId(String userId) {
    if (_currentUserId != userId) {
      _currentUserId = userId;
      _journalCloudInitialized = false;
      _audioCloudInitialized = false;
      _feedbackCloudInitialized = false;
      _keyboardCloudInitialized = false;
      _beaconInitialized = false;
      _accountCloudKeyInitializedForUid = null;
    }
  }

  void clearUserId() {
    _currentUserId = null;
    _journalCloudInitialized = false;
    _audioCloudInitialized = false;
    _feedbackCloudInitialized = false;
    _keyboardCloudInitialized = false;
    _beaconInitialized = false;
    _accountCloudKeyInitializedForUid = null;
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

  Future<void> refreshJournalEntriesFromCloud(
    Box<JournalEntry> journalBox,
  ) async {
    await _removeHistoricalTrainingEntries(journalBox);
    await _loadJournalEntriesFromCloud(journalBox);
    await _retryQueuedJournalSync(journalBox);
  }

  Future<CloudJournalInventory?> cloudJournalInventory({
    bool forceCloudRead = false,
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return null;
    }
    if (!forceCloudRead && !SettingsService.cloudSyncEnabled) {
      return null;
    }
    await _ensureAccountCloudKey();
    return _cloudPersistence.journalInventory(uid);
  }

  Future<void> _ensureAccountCloudKey() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    if (_accountCloudKeyInitializedForUid == uid) {
      return;
    }
    final localKeys = await _encryptionService.exportCloudKeyringForUser(uid);
    final accountKeys = await _cloudPersistence.ensureAccountCloudKeyring(
      uid,
      localKeys,
    );
    await _encryptionService.importCloudKeyringForUser(uid, accountKeys);
    _accountCloudKeyInitializedForUid = uid;
  }

  Future<void> _publishCurrentCloudKeyring() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    final localKeys = await _encryptionService.exportCloudKeyringForUser(uid);
    final accountKeys = await _cloudPersistence.publishAccountCloudKeyring(
      uid,
      localKeys,
    );
    await _encryptionService.importCloudKeyringForUser(uid, accountKeys);
    _accountCloudKeyInitializedForUid = uid;
  }

  Future<void> _initializeJournalDataInBackground(
    Box<JournalEntry> journalBox,
  ) async {
    try {
      await _removeHistoricalTrainingEntries(journalBox);
      await _loadJournalEntriesFromCloud(
        journalBox,
      ).timeout(const Duration(seconds: 10));
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

  Future<Box<NaviBeaconSample>> getNaviBeaconSampleBox() async {
    final boxName = _currentUserId == null
        ? '${_sharedBeaconBoxName}_secure'
        : 'navi_beacon_samples_secure_$_currentUserId';
    final beaconBox = await Hive.openBox<NaviBeaconSample>(
      boxName,
      encryptionCipher: HiveAesCipher(
        await _encryptionService.hiveKeyForUser(_currentUserId),
      ),
    );

    await _migrateNaviBeaconSamples(beaconBox);
    _beaconInitialized = true;
    return beaconBox;
  }

  Future<void> _migrateNaviBeaconSamples(
    Box<NaviBeaconSample> beaconBox,
  ) async {
    if (_beaconInitialized) {
      return;
    }
    await _migrateFromLegacyBeaconBox(beaconBox, _sharedBeaconBoxName);
    if (_currentUserId != null) {
      await _migrateFromLegacyBeaconBox(
        beaconBox,
        'navi_beacon_samples_$_currentUserId',
      );
    }
  }

  Future<void> _migrateFromLegacyBeaconBox(
    Box<NaviBeaconSample> beaconBox,
    String legacyBoxName,
  ) async {
    try {
      final legacyBox = await Hive.openBox<dynamic>(legacyBoxName);
      for (final key in legacyBox.keys) {
        final dynamic legacyValue = legacyBox.get(key);
        final entry = _convertToNaviBeaconSample(legacyValue);
        if (entry != null) {
          await beaconBox.put(entry.id, entry);
        }
      }
    } catch (_) {
      // No legacy beacon data available; ignore.
    }
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

  NaviBeaconSample? _convertToNaviBeaconSample(dynamic value) {
    if (value is NaviBeaconSample) {
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
        return NaviBeaconSample.fromJson(map);
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
          return NaviBeaconSample.fromJson(map);
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
      await _ensureAccountCloudKey();
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
    Box<NaviBeaconSample>? beaconBox;
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
    try {
      beaconBox = await getNaviBeaconSampleBox();
    } catch (_) {
      beaconBox = null;
    }
    await _syncDailyFeaturesToBackend(
      journalBox,
      audioBox: audioBox,
      keyboardBox: keyboardBox,
      beaconBox: beaconBox,
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
      await _ensureAccountCloudKey();
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

  Future<void> saveNaviBeaconSample(NaviBeaconSample sample) async {
    final beaconBox = await getNaviBeaconSampleBox();
    _markPending(sample);
    await beaconBox.put(sample.id, sample);
    final journalBox = await getJournalBox();
    await _syncDailyFeaturesToBackend(journalBox, beaconBox: beaconBox);
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
      await _ensureAccountCloudKey();
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
      await _ensureAccountCloudKey();
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

  Future<CloudLoadResult> loadFromCloud({bool forceCloudRead = false}) async {
    final journalBox = await getJournalBox();
    final audioBox = await getAudioBox();
    final feedbackBox = await getEvaluationFeedbackBox();
    final keyboardBox = await getKeyboardSessionBox();
    final beforeJournalCount = journalBox.length;
    final journalLoaded = await _loadJournalEntriesFromCloud(
      journalBox,
      forceCloudRead: forceCloudRead,
    );
    final audioLoaded = await _loadAudioEntriesFromCloud(
      audioBox,
      forceCloudRead: forceCloudRead,
    );
    final feedbackLoaded = await _loadEvaluationFeedbackFromCloud(
      feedbackBox,
      forceCloudRead: forceCloudRead,
    );
    final keyboardLoaded = await _loadKeyboardSessionsFromCloud(
      keyboardBox,
      forceCloudRead: forceCloudRead,
    );
    return CloudLoadResult(
      beforeJournalCount: beforeJournalCount,
      afterJournalCount: journalBox.length,
      journalLoaded: journalLoaded,
      audioLoaded: audioLoaded,
      feedbackLoaded: feedbackLoaded,
      keyboardLoaded: keyboardLoaded,
    );
  }

  Future<void> syncPrivacyConsentToCloud() async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty || !SettingsService.cloudSyncEnabled) {
      return;
    }
    try {
      await _ensureAccountCloudKey();
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
    final beaconBox = await getNaviBeaconSampleBox();
    final uid = _currentUserId;
    Map<String, dynamic>? cloudData;
    Map<String, dynamic>? backendData;

    if (uid != null && uid.isNotEmpty && SettingsService.cloudSyncEnabled) {
      try {
        await _ensureAccountCloudKey();
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
        'naviBeaconSamples': beaconBox.values
            .map((sample) => sample.toJson())
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

  Future<String> exportEncryptionRecoveryKit(String passphrase) async {
    await _ensureAccountCloudKey();
    return _encryptionService.exportRecoveryKit(_currentUserId, passphrase);
  }

  Future<void> importEncryptionRecoveryKit(
    String passphrase,
    String recoveryKit,
  ) async {
    await _encryptionService.importRecoveryKit(
      _currentUserId,
      passphrase,
      recoveryKit,
    );
    await _publishCurrentCloudKeyring();
  }

  Future<void> deleteMyData() async {
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      try {
        await _ensureAccountCloudKey();
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
    final beaconBox = await getNaviBeaconSampleBox();
    await journalBox.clear();
    await audioBox.clear();
    await feedbackBox.clear();
    await keyboardBox.clear();
    await beaconBox.clear();
    await SettingsService.resetPrivacyControls();
    _journalCloudInitialized = false;
    _audioCloudInitialized = false;
    _feedbackCloudInitialized = false;
    _keyboardCloudInitialized = false;
    _beaconInitialized = false;
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
      await _ensureAccountCloudKey();
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
      await _ensureAccountCloudKey();
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
      await _ensureAccountCloudKey();
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
      await _ensureAccountCloudKey();
      await _cloudPersistence.deleteEvaluationFeedback(uid, feedback.id);
    } catch (e) {
      debugPrint('[DataService] Evaluation feedback cloud delete failed: $e');
    }
  }

  Future<int> _loadJournalEntriesFromCloud(
    Box<JournalEntry> journalBox, {
    bool forceCloudRead = false,
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return 0;
    }
    if (!forceCloudRead && !SettingsService.cloudSyncEnabled) {
      return 0;
    }
    try {
      await _ensureAccountCloudKey();
      final cloudEntries = await _cloudPersistence.loadJournalEntries(uid);
      final userEntries = <JournalEntry>[];
      for (final entry in cloudEntries) {
        if (_isHistoricalTrainingEntry(entry)) {
          unawaited(_cloudPersistence.deleteJournalEntry(uid, entry.id));
          continue;
        }
        userEntries.add(entry);
      }
      final dedupedEntries = _dedupeJournalEntries(userEntries);
      for (final entry in dedupedEntries) {
        _markSynced(entry);
        await journalBox.put(entry.id, entry);
      }
      if (dedupedEntries.isNotEmpty) {
        debugPrint(
          '[DataService] Loaded ${dedupedEntries.length} journal entries from cloud',
        );
      }
      return dedupedEntries.length;
    } catch (e) {
      debugPrint('[DataService] Journal cloud load skipped: $e');
      return 0;
    }
  }

  Future<void> _removeHistoricalTrainingEntries(
    Box<JournalEntry> journalBox,
  ) async {
    final keysToDelete = <dynamic>[];
    for (final key in journalBox.keys) {
      final entry = journalBox.get(key);
      if (entry != null && _isHistoricalTrainingEntry(entry)) {
        keysToDelete.add(key);
      }
    }
    if (keysToDelete.isEmpty) {
      return;
    }
    await journalBox.deleteAll(keysToDelete);
    debugPrint(
      '[DataService] Removed ${keysToDelete.length} historical training journal rows',
    );
  }

  Future<int> _loadAudioEntriesFromCloud(
    Box<AudioEntry> audioBox, {
    bool forceCloudRead = false,
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return 0;
    }
    if (!forceCloudRead && !SettingsService.cloudSyncEnabled) {
      return 0;
    }
    try {
      await _ensureAccountCloudKey();
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
      return dedupedEntries.length;
    } catch (e) {
      debugPrint('[DataService] Audio cloud load skipped: $e');
      return 0;
    }
  }

  Future<int> _loadEvaluationFeedbackFromCloud(
    Box<EvaluationFeedback> feedbackBox, {
    bool forceCloudRead = false,
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return 0;
    }
    if (!forceCloudRead && !SettingsService.cloudSyncEnabled) {
      return 0;
    }
    try {
      await _ensureAccountCloudKey();
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
      return cloudFeedback.length;
    } catch (e) {
      debugPrint('[DataService] Evaluation feedback cloud load skipped: $e');
      return 0;
    }
  }

  Future<int> _loadKeyboardSessionsFromCloud(
    Box<KeyboardSessionEntry> keyboardBox, {
    bool forceCloudRead = false,
  }) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return 0;
    }
    if (!forceCloudRead && !SettingsService.cloudSyncEnabled) {
      return 0;
    }
    try {
      await _ensureAccountCloudKey();
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
      return dedupedEntries.length;
    } catch (e) {
      debugPrint('[DataService] Keyboard session cloud load skipped: $e');
      return 0;
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
    Box<NaviBeaconSample>? beaconBox,
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
      beaconSamples: beaconBox?.values ?? const [],
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

  bool _isHistoricalTrainingEntry(JournalEntry entry) {
    return entry.id.startsWith('historical-') ||
        entry.text.startsWith('Historical mood sample imported');
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

class CloudLoadResult {
  final int beforeJournalCount;
  final int afterJournalCount;
  final int journalLoaded;
  final int audioLoaded;
  final int feedbackLoaded;
  final int keyboardLoaded;

  const CloudLoadResult({
    required this.beforeJournalCount,
    required this.afterJournalCount,
    required this.journalLoaded,
    required this.audioLoaded,
    required this.feedbackLoaded,
    required this.keyboardLoaded,
  });

  int get journalAdded => afterJournalCount - beforeJournalCount;
}
