class InsightTrend {
  final String date;
  final double mood;
  final double? volatility;
  final double? trendSlope;
  final double? sleepVar;
  final double? hrv;
  final String state;

  InsightTrend({
    required this.date,
    required this.mood,
    this.volatility,
    this.trendSlope,
    this.sleepVar,
    this.hrv,
    required this.state,
  });

  factory InsightTrend.fromJson(Map<String, dynamic> json) {
    return InsightTrend(
      date: json['date'],
      mood: (json['mood'] ?? 0).toDouble(),
      volatility: json['volatility']?.toDouble(),
      trendSlope: json['trend_slope']?.toDouble(),
      sleepVar: json['sleep_var']?.toDouble(),
      hrv: json['hrv']?.toDouble(),
      state: json['state'] ?? "Unknown",
    );
  }
}