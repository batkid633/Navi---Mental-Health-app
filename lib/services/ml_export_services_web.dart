import '../services/insights_service.dart';
import '../models/journal_entry.dart';
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

  static Future<String?> exportDailyFeatures(Box<JournalEntry> journalBox) async {
    // Web does not support local file export via dart:io.
    return null;
  }

  static List<Map<String, dynamic>> buildDailyFeatureRecords(
    Box<JournalEntry> journalBox,
  ) {
    final dailyAvg = InsightsService.dailyAverageSentiment(journalBox);
    final rolling7 = InsightsService.rollingAverage(dailyAvg, 7);
    final vol7 = InsightsService.rollingVolatility(dailyAvg, 7);
    final mom7 = InsightsService.rollingMomentum(dailyAvg, 7);
    final nextDelta = computeNextDayDelta(dailyAvg);

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
      });
    }

    return records;
  }
}
