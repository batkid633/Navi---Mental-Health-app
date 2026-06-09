import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:navi_personal/models/audio_entry.dart';
import 'package:navi_personal/models/evaluation_feedback.dart';
import 'package:navi_personal/models/journal_entry.dart';
import 'package:navi_personal/models/keyboard_session_entry.dart';
import 'package:navi_personal/services/ml_export_services.dart';

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
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(EvaluationFeedbackAdapter());
    }
    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(KeyboardSessionEntryAdapter());
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

  test(
    'evaluation feedback persists after closing and reopening Hive',
    () async {
      final firstOpen = await Hive.openBox<EvaluationFeedback>(
        'evaluation_feedback_shared',
      );
      final feedback = EvaluationFeedback(
        id: EvaluationFeedback.canonicalId('tomorrow_prediction', '2026-01-04'),
        targetType: 'tomorrow_prediction',
        targetDate: '2026-01-04',
        journalEntryId: 'journal-1',
        predictedDelta: 0.2,
        confidence: 0.4,
        modelVersion: 'model_v056.pkl',
        insight: 'A steady day may be likely.',
        accuracyRating: 'close',
        helpfulnessRating: 'helpful',
        actualMoodDirection: 'better',
      );

      await firstOpen.put(feedback.id, feedback);
      await firstOpen.close();

      final secondOpen = await Hive.openBox<EvaluationFeedback>(
        'evaluation_feedback_shared',
      );
      final persisted = secondOpen.get(feedback.id);

      expect(persisted, isNotNull);
      expect(persisted!.targetType, feedback.targetType);
      expect(persisted.accuracyRating, 'close');
      expect(persisted.helpfulnessRating, 'helpful');
      expect(persisted.actualMoodDirection, 'better');
    },
  );

  test('keyboard sessions persist after closing and reopening Hive', () async {
    final firstOpen = await Hive.openBox<KeyboardSessionEntry>(
      'keyboard_sessions_shared',
    );
    final startedAt = DateTime(2026, 1, 5, 22, 15);
    final entry = KeyboardSessionEntry(
      id: KeyboardSessionEntry.canonicalId(startedAt),
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(seconds: 90)),
      fieldContext: 'journal_entry',
      platform: 'desktop',
      eventCount: 42,
      charsEstimated: 120,
      backspaceCount: 8,
      burstCount: 3,
      pauseMeanMs: 420,
      pauseStdMs: 180,
      activeSeconds: 90,
    );

    await firstOpen.put(entry.id, entry);
    await firstOpen.close();

    final secondOpen = await Hive.openBox<KeyboardSessionEntry>(
      'keyboard_sessions_shared',
    );
    final persisted = secondOpen.get(entry.id);

    expect(persisted, isNotNull);
    expect(persisted!.fieldContext, entry.fieldContext);
    expect(persisted.platform, entry.platform);
    expect(persisted.eventCount, entry.eventCount);
    expect(persisted.correctionRate, closeTo(entry.correctionRate, 0.001));
  });

  test('daily feature export includes keyboard aggregates', () async {
    final journalBox = await Hive.openBox<JournalEntry>('journal_shared');
    final day = DateTime(2026, 1, 6);
    await journalBox.put(
      'journal-keyboard-1',
      JournalEntry(
        id: 'journal-keyboard-1',
        date: day,
        text: 'Steady day',
        sentimentScore: 0.4,
      ),
    );

    final session = KeyboardSessionEntry(
      id: KeyboardSessionEntry.canonicalId(day),
      startedAt: DateTime(2026, 1, 6, 23),
      endedAt: DateTime(2026, 1, 6, 23, 1),
      fieldContext: 'journal_entry',
      platform: 'web',
      eventCount: 10,
      charsEstimated: 20,
      backspaceCount: 2,
      burstCount: 2,
      pauseMeanMs: 300,
      pauseStdMs: 90,
      activeSeconds: 60,
    );

    final records = MLExportService.buildDailyFeatureRecords(
      journalBox,
      keyboardSessions: [session],
    );

    expect(records, hasLength(1));
    expect(records.single['keyboard_session_count'], 1);
    expect(records.single['keyboard_correction_rate'], closeTo(0.1, 0.001));
    expect(records.single['keyboard_late_night_ratio'], 1);
    expect(records.single['keyboard_platform_web'], 1);
    expect(records.single['missing_keyboard'], 0);
  });
}
