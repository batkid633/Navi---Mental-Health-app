import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/audio_entry.dart';
import '../models/journal_entry.dart';
import '../utils/audio_bytes.dart';

class CloudPersistenceService {
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CloudPersistenceService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _journalCollection(String uid) {
    return _firestore.collection('users').doc(uid).collection('journal_entries');
  }

  CollectionReference<Map<String, dynamic>> _audioCollection(String uid) {
    return _firestore.collection('users').doc(uid).collection('audio_entries');
  }

  Future<List<JournalEntry>> loadJournalEntries(String uid) async {
    final snapshot = await _journalCollection(uid)
        .orderBy('date', descending: false)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return JournalEntry.fromJson({
        'id': doc.id,
        'date': _dateToIsoString(data['date']),
        'text': data['text'],
        'sentimentLabel': data['sentimentLabel'],
        'sentimentScore': data['sentimentScore'],
      });
    }).toList();
  }

  Future<void> saveJournalEntry(String uid, JournalEntry entry) async {
    await _journalCollection(uid).doc(entry.id).set({
      'date': Timestamp.fromDate(entry.date),
      'text': entry.text,
      'sentimentLabel': entry.sentimentLabel,
      'sentimentScore': entry.sentimentScore,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<List<AudioEntry>> loadAudioEntries(String uid) async {
    final snapshot = await _audioCollection(uid)
        .orderBy('date', descending: false)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      return AudioEntry.fromJson({
        'id': doc.id,
        'date': _dateToIsoString(data['date']),
        'filePath': data['storagePath'] ?? data['filePath'] ?? '',
        'fileName': data['fileName'] ?? '',
        'duration': data['duration'] ?? 0,
        'transcription': data['transcription'],
        'mode': data['mode'] ?? 'emotional_venting',
        'moodLabel': data['moodLabel'],
        'isTraining': data['isTraining'] ?? false,
      });
    }).toList();
  }

  Future<void> saveAudioEntry(String uid, AudioEntry entry) async {
    String? storagePath;
    String? downloadUrl;

    try {
      final bytes = await readAudioBytes(entry.filePath);
      storagePath = 'users/$uid/audio/${entry.id}/${entry.fileName}';
      final ref = _storage.ref(storagePath);
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: 'audio/wav'),
      );
      downloadUrl = await ref.getDownloadURL();
    } catch (_) {
      // Metadata still syncs if the local file/blob is no longer available.
    }

    await _audioCollection(uid).doc(entry.id).set({
      'date': Timestamp.fromDate(entry.date),
      'fileName': entry.fileName,
      'filePath': entry.filePath,
      if (storagePath != null) 'storagePath': storagePath,
      if (downloadUrl != null) 'downloadUrl': downloadUrl,
      'duration': entry.duration,
      'transcription': entry.transcription,
      'mode': entry.mode,
      'moodLabel': entry.moodLabel,
      'isTraining': entry.isTraining,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
}
