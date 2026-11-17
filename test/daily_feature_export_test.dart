import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:navi_personal/models/journal_entry.dart';
import 'package:navi_personal/models/audio_entry.dart';
import 'package:navi_personal/services/ml_export_services_io.dart' as native;
import 'package:navi_personal/services/ml_export_services_web.dart' as web;

void main() {
  test('next-day labels exclude calendar gaps on both platforms', () {
    final scores = {
      DateTime(2026, 1, 1): .2,
      DateTime(2026, 1, 3): .8,
      DateTime(2026, 1, 4): .5,
    };
    for (final result in [
      native.MLExportService.computeNextDayDelta(scores),
      web.MLExportService.computeNextDayDelta(scores),
    ]) {
      expect(result.containsKey(DateTime(2026, 1, 1)), false);
      expect(result[DateTime(2026, 1, 3)], closeTo(-.3, .00001));
    }
  });
  test(
    'numeric export includes available audio without journal text',
    () async {
      final dir = await Directory.systemTemp.createTemp('navi-export-test');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(JournalEntryAdapter());
      }
      final box = await Hive.openBox<JournalEntry>('fixture');
      try {
        final day = DateTime(2026, 1, 1);
        await box.put(
          'j',
          JournalEntry(
            id: 'j',
            date: day,
            text: 'PRIVATE FIXTURE',
            sentimentScore: .4,
          ),
        );
        final audio = AudioEntry(
          id: 'a',
          date: day,
          filePath: '',
          fileName: '',
          duration: 10,
          mode: 'emotional_venting',
          moodLabel: 'happy',
        );
        for (final rows in [
          native.MLExportService.buildDailyFeatureRecords(
            box,
            audioEntries: [audio],
          ),
          web.MLExportService.buildDailyFeatureRecords(
            box,
            audioEntries: [audio],
          ),
        ]) {
          expect(rows, hasLength(1));
          expect(rows.single['audio_session_count'], 1);
          expect(rows.single['missing_audio'], 0);
          expect(rows.toString().contains('PRIVATE FIXTURE'), false);
        }
      } finally {
        await box.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
