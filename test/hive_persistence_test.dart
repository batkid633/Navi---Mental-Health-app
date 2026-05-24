import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:navi_personal/models/audio_entry.dart';
import 'package:navi_personal/models/journal_entry.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('navi_hive_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(JournalEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AudioEntryAdapter());
    }
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('journal entries persist after closing and reopening Hive', () async {
    final firstOpen = await Hive.openBox<JournalEntry>('journal_shared');
    final entry = JournalEntry(
      id: 'journal-1',
      date: DateTime(2026, 1, 2),
      text: 'I felt steady today.',
      sentimentLabel: 'positive',
      sentimentScore: 0.7,
    );

    await firstOpen.put(entry.id, entry);
    await firstOpen.close();

    final secondOpen = await Hive.openBox<JournalEntry>('journal_shared');
    final persisted = secondOpen.get(entry.id);

    expect(persisted, isNotNull);
    expect(persisted!.text, entry.text);
    expect(persisted.sentimentScore, entry.sentimentScore);
    expect(persisted.date, entry.date);
  });

  test('audio entries persist after closing and reopening Hive', () async {
    final firstOpen = await Hive.openBox<AudioEntry>('audio_shared');
    final entry = AudioEntry(
      id: 'audio-1',
      date: DateTime(2026, 1, 3),
      filePath: 'test-recording.wav',
      fileName: 'test-recording.wav',
      duration: 12,
      mode: 'emotional_venting',
      moodLabel: 'calm',
      isTraining: true,
    );

    await firstOpen.put(entry.id, entry);
    await firstOpen.close();

    final secondOpen = await Hive.openBox<AudioEntry>('audio_shared');
    final persisted = secondOpen.get(entry.id);

    expect(persisted, isNotNull);
    expect(persisted!.fileName, entry.fileName);
    expect(persisted.duration, entry.duration);
    expect(persisted.mode, entry.mode);
    expect(persisted.isTraining, isTrue);
  });
}
