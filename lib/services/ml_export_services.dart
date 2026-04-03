import 'dart:io';
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

    nextDayDelta[today] =
        dailyAvg[tomorrow]! - dailyAvg[today]!;
  }

  return nextDayDelta;
}

  static Future<File> exportDailyFeatures() async {
    final box = Hive.box<JournalEntry>('journal');
    final dailyAvg = InsightsService.dailyAverageSentiment(box);

    final rolling7 = InsightsService.rollingAverage(dailyAvg, 7);
    final vol7 = InsightsService.rollingVolatility(dailyAvg, 7);
    final mom7 = InsightsService.rollingMomentum(dailyAvg, 7);

    final nextDelta = computeNextDayDelta(dailyAvg);

    final buffer = StringBuffer();
    buffer.writeln(
      'date,sentiment_today,rolling_mean_7,volatility_7,momentum_7,z_score,is_anomalous,day_of_week,Next_day_delta',
    );

    for (final date in dailyAvg.keys) {
      if (!rolling7.containsKey(date) || !vol7.containsKey(date)) continue;

      final deviation = BaselineDeviationModel.evaluate(
        today: dailyAvg[date]!,
        rollingMean: rolling7[date]!,
        rollingStd: vol7[date]!,
      );

      buffer.writeln([
        date.toIso8601String().substring(0, 10),
        dailyAvg[date],
        rolling7[date],
        vol7[date],
        mom7[date],
        deviation.zScore,
        deviation.isAnomalous ? 1 : 0,
        date.weekday - 1,
        nextDelta[date],
      ].join(','));
    }

    final dir = 'C:/Users/coler/Documents/Navi_personal/navi_personal/backend/data';
    final file = File('$dir/daily_features.csv');
    return file.writeAsString(buffer.toString());
  }
}
