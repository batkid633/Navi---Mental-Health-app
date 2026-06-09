import 'dart:io';
import '../services/insights_service.dart';
import '../models/audio_entry.dart';
import '../models/journal_entry.dart';
import '../models/keyboard_session_entry.dart';
import '../models/baseline_deviation_model.dart';
import 'package:hive/hive.dart';

class MLExportService {
  static Map<DateTime, double> computeNextDayDelta(
    Map<DateTime, double> dailyAvg,
  ) {
    final sortedDays = dailyAvg.keys.toList()..sort();
    final Map<DateTime, double> nextDayDelta = {};

    for (int i = 0; i < sortedDays.length - 1; i++) {
      final today = sortedDays[i];
      final tomorrow = sortedDays[i + 1];
      nextDayDelta[today] = dailyAvg[tomorrow]! - dailyAvg[today]!;
    }

    return nextDayDelta;
  }

  static Future<String> exportDailyFeatures(
    Box<JournalEntry> journalBox,
  ) async {
    final records = buildDailyFeatureRecords(journalBox);

    final fields = records.expand((record) => record.keys).toSet().toList()
      ..sort();
    fields.remove('date');
    fields.insert(0, 'date');

    final buffer = StringBuffer();
    buffer.writeln(fields.join(','));
    for (final record in records) {
      buffer.writeln(fields.map((field) => record[field] ?? '').join(','));
    }

    final dir =
        'C:/Users/coler/Documents/Navi_personal/navi_personal/backend/data';
    final file = File('$dir/daily_features.csv');
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  static List<Map<String, dynamic>> buildDailyFeatureRecords(
    Box<JournalEntry> journalBox, {
    Iterable<AudioEntry> audioEntries = const [],
    Iterable<KeyboardSessionEntry> keyboardSessions = const [],
  }) {
    final dailyAvg = InsightsService.dailyAverageSentiment(journalBox);
    final rolling7 = InsightsService.rollingAverage(dailyAvg, 7);
    final vol7 = InsightsService.rollingVolatility(dailyAvg, 7);
    final mom7 = InsightsService.rollingMomentum(dailyAvg, 7);
    final nextDelta = computeNextDayDelta(dailyAvg);
    final audioByDay = _audioFeatureRecords(audioEntries);
    final keyboardByDay = _keyboardFeatureRecords(keyboardSessions);

    final records = <Map<String, dynamic>>[];
    final sortedDays = dailyAvg.keys.toList()..sort();

    for (final date in sortedDays) {
      if (!rolling7.containsKey(date) || !vol7.containsKey(date)) continue;

      final deviation = BaselineDeviationModel.evaluate(
        today: dailyAvg[date]!,
        rollingMean: rolling7[date]!,
        rollingStd: vol7[date]!,
      );

      records.add({
        'date': date.toIso8601String().substring(0, 10),
        'sentiment_today': dailyAvg[date],
        'rolling_mean_7': rolling7[date],
        'volatility_7': vol7[date],
        'momentum_7': mom7[date],
        'z_score': deviation.zScore,
        'is_anomalous': deviation.isAnomalous ? 1 : 0,
        'day_of_week': date.weekday - 1,
        'Next_day_delta': nextDelta[date],
        ...?audioByDay[_dateKey(date)],
        ...?keyboardByDay[_dateKey(date)],
        'missing_journal': 0,
        'missing_biometrics': 1,
        'missing_audio': audioByDay.containsKey(_dateKey(date)) ? 0 : 1,
        'missing_keyboard': keyboardByDay.containsKey(_dateKey(date)) ? 0 : 1,
        'missing_sleep': 1,
        'missing_hrv': 1,
        'missing_recovery': 1,
      });
    }

    return records;
  }

  static Map<String, Map<String, dynamic>> _audioFeatureRecords(
    Iterable<AudioEntry> entries,
  ) {
    final grouped = <String, List<AudioEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(_dateKey(entry.date), () => []).add(entry);
    }

    return grouped.map((date, entries) {
      final total = entries.length;
      final labeled = entries
          .map((entry) => entry.moodLabel?.trim().toLowerCase())
          .where((label) => label != null && label.isNotEmpty)
          .cast<String>()
          .toList();
      double ratio(Set<String> labels) {
        if (labeled.isEmpty) return 0.0;
        final count = labeled.where(labels.contains).length;
        return count / labeled.length;
      }

      return MapEntry(date, {
        'audio_session_count': total,
        'audio_total_seconds': entries.fold<int>(
          0,
          (sum, entry) => sum + entry.duration,
        ),
        'audio_negative_ratio': ratio({'sad', 'angry'}),
        'audio_positive_ratio': ratio({'happy'}),
        'audio_anxious_ratio': ratio({'anxious'}),
        'audio_calm_ratio': ratio({'calm', 'neutral'}),
        'audio_training_count': entries
            .where((entry) => entry.isTraining)
            .length,
      });
    });
  }

  static Map<String, Map<String, dynamic>> _keyboardFeatureRecords(
    Iterable<KeyboardSessionEntry> sessions,
  ) {
    final grouped = <String, List<KeyboardSessionEntry>>{};
    for (final session in sessions) {
      grouped.putIfAbsent(_dateKey(session.startedAt), () => []).add(session);
    }

    double average(Iterable<num> values) {
      final list = values.map((value) => value.toDouble()).toList();
      if (list.isEmpty) return 0.0;
      return list.reduce((a, b) => a + b) / list.length;
    }

    return grouped.map((date, sessions) {
      final total = sessions.length;
      final lateNight = sessions.where((session) {
        final hour = session.startedAt.hour;
        return hour >= 22 || hour < 5;
      }).length;
      int platformCount(String platform) {
        return sessions.where((session) => session.platform == platform).length;
      }

      return MapEntry(date, {
        'keyboard_session_count': total,
        'keyboard_active_seconds': sessions.fold<int>(
          0,
          (sum, session) => sum + session.activeSeconds,
        ),
        'keyboard_event_count': sessions.fold<int>(
          0,
          (sum, session) => sum + session.eventCount,
        ),
        'keyboard_chars_estimated': sessions.fold<int>(
          0,
          (sum, session) => sum + session.charsEstimated,
        ),
        'keyboard_backspace_count': sessions.fold<int>(
          0,
          (sum, session) => sum + session.backspaceCount,
        ),
        'keyboard_correction_rate': average(
          sessions.map((session) => session.correctionRate),
        ),
        'keyboard_pause_mean_ms': average(
          sessions.map((session) => session.pauseMeanMs),
        ),
        'keyboard_pause_std_ms': average(
          sessions.map((session) => session.pauseStdMs),
        ),
        'keyboard_burst_count': sessions.fold<int>(
          0,
          (sum, session) => sum + session.burstCount,
        ),
        'keyboard_typing_speed_cpm': average(
          sessions.map((session) => session.typingSpeedCpm),
        ),
        'keyboard_late_night_ratio': total == 0 ? 0.0 : lateNight / total,
        'keyboard_platform_web': total == 0
            ? 0.0
            : platformCount('web') / total,
        'keyboard_platform_mobile': total == 0
            ? 0.0
            : platformCount('mobile') / total,
        'keyboard_platform_desktop': total == 0
            ? 0.0
            : platformCount('desktop') / total,
      });
    });
  }

  static String _dateKey(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String().substring(0, 10);
  }
}
