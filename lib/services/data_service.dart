import 'package:hive/hive.dart';
import '../models/journal_entry.dart';
import '../models/audio_entry.dart';

class DataService {
  String? _currentUserId;

  void setUserId(String userId) {
    _currentUserId = userId;
  }

  // Journal entries - local with user scoping
  Future<Box<JournalEntry>> getJournalBox() async {
    if (_currentUserId == null) throw Exception('User not authenticated');

    final boxName = 'journal_${_currentUserId}';
    return await Hive.openBox<JournalEntry>(boxName);
  }

  // Audio entries - local with user scoping
  Future<Box<AudioEntry>> getAudioBox() async {
    if (_currentUserId == null) throw Exception('User not authenticated');

    final boxName = 'audio_${_currentUserId}';
    return await Hive.openBox<AudioEntry>(boxName);
  }

  // Local-only for now - no cloud sync
  Future<void> syncJournalEntryToCloud(JournalEntry entry) async {
    // TODO: Implement cloud sync when Firebase is working
  }

  Future<void> syncAudioEntryToCloud(AudioEntry entry) async {
    // TODO: Implement cloud sync when Firebase is working
  }

  // Load from cloud if needed (for new devices)
  Future<void> loadFromCloud() async {
    // TODO: Implement cloud loading when Firebase is working
  }
}