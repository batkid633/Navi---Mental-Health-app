enum TodayMoodTrend {
  stablePositive,
  stableNeutral,
  stableNegative,
  improving,
  declining,
  volatile
}

class TodayState {
  final DateTime date;

  TodayState({
    required this.date,
  });

  String get dateIso => date.toIso8601String().split('T').first;
}
