import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../models/journal_entry.dart';
import '../models/audio_entry.dart';
import '../config/backend_config.dart';
import 'cloud_persistence_service.dart';
import 'ml_export_services.dart';
import 'sentiment_service.dart';

class DataService {
  static const _sharedJournalBoxName = 'journal_shared';
  static const _legacyJournalBoxName = 'journal';
  static const _sharedAudioBoxName = 'audio_shared';
  static const _legacyAudioBoxName = 'audio';

  String? _currentUserId;
  final CloudPersistenceService _cloudPersistence = CloudPersistenceService();
  bool _journalCloudInitialized = false;
  bool _audioCloudInitialized = false;

  void setUserId(String userId) {
    if (_currentUserId != userId) {
      _currentUserId = userId;
      _journalCloudInitialized = false;
      _audioCloudInitialized = false;
    }
  }

  void clearUserId() {
    _currentUserId = null;
    _journalCloudInitialized = false;
    _audioCloudInitialized = false;
  }

  // Journal entries - local with user scoping.
  // If the user-specific box is empty, migrate legacy shared entries.
  Future<Box<JournalEntry>> getJournalBox() async {
    final boxName = _currentUserId == null
        ? _sharedJournalBoxName
        : 'journal_$_currentUserId';
    debugPrint(
        '[DataService] Opening journal box: $boxName (userId: $_currentUserId)');
    final journalBox = await Hive.openBox<JournalEntry>(boxName);
    debugPrint(
        '[DataService] Journal box opened with ${journalBox.length} entries');

    // Always attempt migration to recover lost data.
    // This includes both authenticated users and unauthenticated users
    // using the shared journal box.
    await _migrateJournalData(journalBox);
    if (!_journalCloudInitialized) {
      await _loadJournalEntriesFromCloud(journalBox);
    }
    await _importHistoricalTrainingData(journalBox);
    debugPrint(
        '[DataService] After migration: ${journalBox.length} total entries');

    await _scoreMissingSentiment(journalBox);
    if (!_journalCloudInitialized) {
      await _syncExistingJournalEntriesToCloud(journalBox);
      await _syncDailyFeaturesToBackend(journalBox);
      _journalCloudInitialized = true;
    }
    return journalBox;
  }

  Future<void> _migrateJournalData(Box<JournalEntry> journalBox) async {
    await _migrateFromLegacyBox(journalBox, _legacyJournalBoxName);
    await _migrateFromLegacyBox(journalBox, _sharedJournalBoxName);
    await _migrateFromLegacyBox(journalBox, 'journal_local-test-user');
  }

  Future<void> _migrateFromLegacyBox(
    Box<JournalEntry> journalBox,
    String legacyBoxName,
  ) async {
    try {
      final legacyBox = await Hive.openBox<dynamic>(legacyBoxName);
      debugPrint(
          '[DataService] Checking legacy box "$legacyBoxName": ${legacyBox.length} entries');
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
              '[DataService] Migrated $migratedCount entries from "$legacyBoxName"');
        }
      }
    } catch (e) {
      debugPrint(
          '[DataService] Error migrating from "$legacyBoxName": $e');
    }
  }

  Future<void> _importHistoricalTrainingData(Box<JournalEntry> journalBox) async {
    try {
      final response = await http.get(
        Uri.parse('${BackendConfig.baseUrl}/journal/history'),
        headers: await BackendConfig.getAuthHeaders(),
      );
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
          await journalBox.put(entry.id, entry);
          importedCount++;
        }
      }

      if (importedCount > 0) {
        debugPrint(
            '[DataService] Imported $importedCount historical training entries');
      }
    } catch (e) {
      debugPrint('[DataService] Historical training import skipped: $e');
    }
  }

  Future<void> _scoreMissingSentiment(Box<JournalEntry> journalBox) async {
    final entriesToScore = journalBox.values
        .where((entry) =>
            entry.sentimentScore == null && entry.text.trim().isNotEmpty)
        .toList();

    if (entriesToScore.isNotEmpty) {
      debugPrint(
          '[DataService] Scoring sentiment for ${entriesToScore.length} entries');
    }

    for (final entry in entriesToScore) {
      try {
        final sentiment = await SentimentService.analyze(entry.text);
        entry.sentimentScore = (sentiment['compound'] as num).toDouble();
        entry.sentimentLabel = sentiment['label'] as String?;
        await journalBox.put(entry.id, entry);
      } catch (e) {
        debugPrint(
            '[DataService] Sentiment scoring failed for entry ${entry.id}: $e');
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
      'id': map['id']?.toString() ??
          map['entryId']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      'date': dateString,
      'text': map['text']?.toString() ?? '',
      'sentimentLabel': map['sentimentLabel'] ?? map['sentiment_label'],
      'sentimentScore': sentimentScore,
    };
  }

  // Audio entries - local with user scoping.
  // If the user-specific box is empty, try to fall back to a legacy shared box.
  Future<Box<AudioEntry>> getAudioBox() async {
    final boxName = _currentUserId == null
        ? _sharedAudioBoxName
        : 'audio_$_currentUserId';
    final audioBox = await Hive.openBox<AudioEntry>(boxName);

    if (audioBox.isEmpty) {
      await _migrateAudioData(audioBox);
    }
    if (!_audioCloudInitialized) {
      await _loadAudioEntriesFromCloud(audioBox);
      await _syncExistingAudioEntriesToCloud(audioBox);
      _audioCloudInitialized = true;
    }

    return audioBox;
  }

  Future<void> _migrateAudioData(Box<AudioEntry> audioBox) async {
    await _migrateFromLegacyAudioBox(audioBox, _legacyAudioBoxName);
    await _migrateFromLegacyAudioBox(audioBox, _sharedAudioBoxName);
    await _migrateFromLegacyAudioBox(audioBox, 'audio_local-test-user');
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

  Future<void> syncJournalEntryToCloud(JournalEntry entry) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    try {
      await _cloudPersistence.saveJournalEntry(uid, entry);
    } catch (e) {
      debugPrint('[DataService] Journal cloud sync failed: $e');
    }
  }

  Future<void> syncJournalFeaturesToBackend(
    Box<JournalEntry> journalBox,
  ) async {
    await _syncDailyFeaturesToBackend(journalBox);
  }

  Future<void> syncAudioEntryToCloud(AudioEntry entry) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    try {
      await _cloudPersistence.saveAudioEntry(uid, entry);
    } catch (e) {
      debugPrint('[DataService] Audio cloud sync failed: $e');
    }
  }

  Future<void> loadFromCloud() async {
    final journalBox = await getJournalBox();
    final audioBox = await getAudioBox();
    await _loadJournalEntriesFromCloud(journalBox);
    await _loadAudioEntriesFromCloud(audioBox);
  }

  Future<void> deleteJournalEntry(JournalEntry entry) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
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
    try {
      await _cloudPersistence.deleteAudioEntry(uid, entry.id);
    } catch (e) {
      debugPrint('[DataService] Audio cloud delete failed: $e');
    }
  }

  Future<void> _loadJournalEntriesFromCloud(
    Box<JournalEntry> journalBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    try {
      final cloudEntries = await _cloudPersistence.loadJournalEntries(uid);
      for (final entry in cloudEntries) {
        await journalBox.put(entry.id, entry);
      }
      if (cloudEntries.isNotEmpty) {
        debugPrint(
            '[DataService] Loaded ${cloudEntries.length} journal entries from cloud');
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
    try {
      final cloudEntries = await _cloudPersistence.loadAudioEntries(uid);
      for (final entry in cloudEntries) {
        await audioBox.put(entry.id, entry);
      }
      if (cloudEntries.isNotEmpty) {
        debugPrint(
            '[DataService] Loaded ${cloudEntries.length} audio entries from cloud');
      }
    } catch (e) {
      debugPrint('[DataService] Audio cloud load skipped: $e');
    }
  }

  Future<void> _syncExistingJournalEntriesToCloud(
    Box<JournalEntry> journalBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    for (final entry in journalBox.values) {
      await syncJournalEntryToCloud(entry);
    }
  }

  Future<void> _syncDailyFeaturesToBackend(
    Box<JournalEntry> journalBox,
  ) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }

    final records = MLExportService.buildDailyFeatureRecords(journalBox);
    if (records.isEmpty) {
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${BackendConfig.baseUrl}/ml/daily-features'),
        headers: await BackendConfig.getAuthHeaders(),
        body: jsonEncode({'records': records}),
      );
      if (response.statusCode >= 400) {
        debugPrint(
            '[DataService] Daily feature sync failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[DataService] Daily feature sync skipped: $e');
    }
  }

  Future<void> _syncExistingAudioEntriesToCloud(Box<AudioEntry> audioBox) async {
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) {
      return;
    }
    for (final entry in audioBox.values) {
      await syncAudioEntryToCloud(entry);
    }
  }
}
