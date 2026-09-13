import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:navi_personal/services/apple_health_normalizer.dart';

HealthDataPoint sample(
  String id,
  HealthDataType type,
  String start,
  String end, {
  double value = 0,
  String source = 'a',
  bool manual = false,
}) => HealthDataPoint(
  uuid: id,
  value: NumericHealthValue(numericValue: value),
  type: type,
  unit: type == HealthDataType.RESTING_HEART_RATE
      ? HealthDataUnit.BEATS_PER_MINUTE
      : type == HealthDataType.HEART_RATE_VARIABILITY_SDNN
      ? HealthDataUnit.MILLISECOND
      : HealthDataUnit.MINUTE,
  dateFrom: DateTime.parse(start),
  dateTo: DateTime.parse(end),
  sourcePlatform: HealthPlatformType.appleHealth,
  sourceDeviceId: 'fixture',
  sourceId: source,
  sourceName: source,
  recordingMethod: manual ? RecordingMethod.manual : RecordingMethod.automatic,
);

void main() {
  test(
    'overnight stages, duplicates and overlapping summaries use interval union',
    () {
      final points = [
        sample(
          'bed',
          HealthDataType.SLEEP_IN_BED,
          '2026-09-11T22:00:00',
          '2026-09-12T07:00:00',
        ),
        sample(
          'summary',
          HealthDataType.SLEEP_ASLEEP,
          '2026-09-11T23:00:00',
          '2026-09-12T06:00:00',
        ),
        sample(
          'light',
          HealthDataType.SLEEP_LIGHT,
          '2026-09-11T23:00:00',
          '2026-09-12T02:00:00',
        ),
        sample(
          'deep',
          HealthDataType.SLEEP_DEEP,
          '2026-09-12T02:00:00',
          '2026-09-12T04:00:00',
        ),
        sample(
          'rem',
          HealthDataType.SLEEP_REM,
          '2026-09-12T04:00:00',
          '2026-09-12T06:00:00',
        ),
      ];
      final rows = AppleHealthNormalizer.dailyRecords([...points, ...points]);
      expect(rows, hasLength(1));
      expect(rows.single['date'], '2026-09-12');
      expect(rows.single['sleep_hours'], 7);
      expect(rows.single['sleep_efficiency'], closeTo(7 / 9 * 100, 0.001));
    },
  );
  test(
    'writers stay separate, SDNN stays distinct, manual values excluded',
    () {
      final rows = AppleHealthNormalizer.dailyRecords([
        sample(
          'a',
          HealthDataType.HEART_RATE_VARIABILITY_SDNN,
          '2026-09-12T08:00:00',
          '2026-09-12T08:01:00',
          value: 40,
        ),
        sample(
          'b',
          HealthDataType.HEART_RATE_VARIABILITY_SDNN,
          '2026-09-12T08:00:00',
          '2026-09-12T08:01:00',
          value: 80,
          source: 'b',
        ),
        sample(
          'manual',
          HealthDataType.RESTING_HEART_RATE,
          '2026-09-12T08:00:00',
          '2026-09-12T08:01:00',
          value: 90,
          manual: true,
        ),
      ]);
      expect(rows.single['hrv_sdnn'], 40);
      expect(rows.single.containsKey('hrv_rmssd'), isFalse);
      expect(rows.single['resting_hr'], isNull);
      final provenance = rows.single['metric_provenance'] as Map;
      expect((provenance['alternatives'] as Map).keys, containsAll(['a', 'b']));
    },
  );
  test('inconsistent in-bed coverage does not fabricate efficiency', () {
    final rows = AppleHealthNormalizer.dailyRecords([
      sample(
        'sleep',
        HealthDataType.SLEEP_ASLEEP,
        '2026-09-12T00:00:00',
        '2026-09-12T08:00:00',
      ),
      sample(
        'bed',
        HealthDataType.SLEEP_IN_BED,
        '2026-09-12T01:00:00',
        '2026-09-12T07:00:00',
      ),
    ]);
    expect(rows.single['sleep_hours'], 8);
    expect(rows.single['sleep_efficiency'], isNull);
  });
}
