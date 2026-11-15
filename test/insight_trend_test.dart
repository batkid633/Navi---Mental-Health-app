import 'package:flutter_test/flutter_test.dart';
import 'package:navi_personal/models/insight_trend.dart';

void main() {
  test('missing or invalid sentiment is not fabricated neutral', () {
    for (final value in [null, double.nan, double.infinity, 4, 'invalid']) {
      final trend = InsightTrend.fromJson({
        'date': '2026-10-31',
        'mood': value,
        'hrv': 42,
      });
      expect(trend.mood, isNull);
      expect(trend.hrv, 42);
    }
  });
  test('zero is valid neutral and negative sentiment remains negative', () {
    for (final value in [0, -0.8, 0.9]) {
      expect(
        InsightTrend.fromJson({'date': '2026-10-31', 'mood': value}).mood,
        value,
      );
    }
  });
}
