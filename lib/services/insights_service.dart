import 'package:hive/hive.dart';
import '../models/journal_entry.dart';
import 'dart:math';

class InsightsService {
  static Map<DateTime, double> dailyAverageSentiment(
      Box<JournalEntry> box) {
    final Map<DateTime, List<double>> grouped = {};

    for (final entry in box.values) {
      if (entry.sentimentScore == null) continue;

      final day = DateTime(
        entry.date.year,
        entry.date.month,
        entry.date.day,
      );

      grouped.putIfAbsent(day, () => []);
      grouped[day]!.add(entry.sentimentScore!);
    }

    return grouped.map((day, scores) {
      final avg =
          scores.reduce((a, b) => a + b) / scores.length;
      return MapEntry(day, avg);
    });
  }

  static Map<DateTime, double> rollingAverage(
      Map<DateTime, double> dailyAvg,
      int windowSize) {
    final sortedDays = dailyAvg.keys.toList()..sort();

    final Map<DateTime, double> rolling = {};

    for (int i = 0; i < sortedDays.length; i++) {
      final start = (i - windowSize + 1).clamp(0, i);
      final windowDays = sortedDays.sublist(start, i + 1);

      final values = windowDays.map((d) => dailyAvg[d]!);
      final avg =
          values.reduce((a, b) => a + b) / values.length;

      rolling[sortedDays[i]] = avg;
    }

    return rolling;
  }

  static Map<DateTime, double> rollingVolatility(
    Map<DateTime, double> dailyAvg,
    int windowSize) {
  final sortedDays = dailyAvg.keys.toList()..sort();
  final Map<DateTime, double> volatility = {};

  for (int i = 0; i < sortedDays.length; i++) {
    final start = (i - windowSize + 1).clamp(0, i);
    final windowDays = sortedDays.sublist(start, i + 1);

    final values =
        windowDays.map((d) => dailyAvg[d]!).toList();

    final mean =
        values.reduce((a, b) => a + b) / values.length;

    final variance = values
            .map((v) => pow(v - mean, 2))
            .reduce((a, b) => a + b) /
        values.length;

    volatility[sortedDays[i]] = sqrt(variance);
  }

  return volatility;
}
static Map<DateTime, double> rollingMomentum(
    Map<DateTime, double> dailyAvg,
    int windowSize) {
  final sortedDays = dailyAvg.keys.toList()..sort();
  final Map<DateTime, double> momentum = {};

  for (int i = 0; i < sortedDays.length; i++) {
    final start = (i - windowSize + 1).clamp(0, i);
    final windowDays = sortedDays.sublist(start, i + 1);

    if (windowDays.length < 2) {
      momentum[sortedDays[i]] = 0.0;
      continue;
    }

    final y =
        windowDays.map((d) => dailyAvg[d]!).toList();
    final x =
        List.generate(y.length, (i) => i.toDouble());

    final xMean = x.reduce((a, b) => a + b) / x.length;
    final yMean = y.reduce((a, b) => a + b) / y.length;

    double numerator = 0;
    double denominator = 0;

    for (int j = 0; j < x.length; j++) {
      numerator += (x[j] - xMean) * (y[j] - yMean);
      denominator += (x[j] - xMean) * (x[j] - xMean);
    }

    momentum[sortedDays[i]] =
        denominator == 0 ? 0 : numerator / denominator;
  }

  return momentum;
}
static String momentumLabel(double m) {
  if (m > 0.05) return "Improving";
  if (m < -0.05) return "Declining";
  return "Stable";
}

static double dailyDelta({
  required double today,
  required double rollingAvg,
}) {
  return today - rollingAvg;
}

}
