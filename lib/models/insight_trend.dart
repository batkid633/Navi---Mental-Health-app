class InsightTrend {
  final String date;
  final double? mood;
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
      mood: _finite(json['mood']),
      volatility: json['volatility']?.toDouble(),
      trendSlope: json['trend_slope']?.toDouble(),
      sleepVar: json['sleep_var']?.toDouble(),
      hrv: json['hrv']?.toDouble(),
      state: json['state'] ?? "Unknown",
    );
  }
  static double? _finite(dynamic value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return number != null && number.isFinite && number >= -1 && number <= 1
        ? number
        : null;
  }
}
