import 'package:flutter_test/flutter_test.dart';
import 'package:navi_personal/models/tomorrow_outlook.dart';

void main() {
  test('missing forecast is not parsed as neutral or zero uncertainty', () {
    final point = TrajectoryPoint.fromJson({
      'horizon_days': 14,
      'status': 'unavailable',
    });
    expect(point.available, false);
    expect(point.predictedMood, isNull);
    expect(point.confidence, isNull);
    expect(point.uncertainty, isNull);
  });
  test('legacy and experimental numeric forecasts remain readable', () {
    final legacy = TrajectoryPoint.fromJson({
      'horizon_days': 3,
      'predicted_mood': 0.0,
      'confidence': .2,
    });
    final experimental = TrajectoryPoint.fromJson({
      'horizon_days': 7,
      'predicted_mood': .3,
      'status': 'available',
      'training_pairs': 12,
    });
    expect(legacy.available, true);
    expect(experimental.available, true);
    expect(experimental.trainingPairs, 12);
    expect(experimental.confidence, isNull);
  });
}
