import 'package:health/health.dart';

/// Pure transformation. No permission requests, storage, or network calls.
class AppleHealthNormalizer {
  static const types = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  ];

  static List<Map<String, dynamic>> dailyRecords(List<HealthDataPoint> points) {
    final sources = <String, List<HealthDataPoint>>{};
    final seen = <String>{};
    for (final p in points) {
      if (!types.contains(p.type) ||
          p.recordingMethod == RecordingMethod.manual) {
        continue;
      }
      final key =
          '${p.sourceId}|${p.uuid}|${p.type}|${p.dateFrom}|${p.dateTo}|${p.value}';
      if (!seen.add(key)) continue;
      sources.putIfAbsent(p.sourceId, () => []).add(p);
    }
    final days = <String, Map<String, Map<String, dynamic>>>{};
    Map<String, dynamic> bucket(String date, String source) => days
        .putIfAbsent(date, () => {})
        .putIfAbsent(source, () => <String, dynamic>{});

    for (final source in sources.keys) {
      final samples = sources[source]!;
      for (final type in [
        HealthDataType.RESTING_HEART_RATE,
        HealthDataType.HEART_RATE_VARIABILITY_SDNN,
      ]) {
        final values = <String, List<double>>{};
        for (final p in samples.where((p) => p.type == type)) {
          final expectedUnit = type == HealthDataType.RESTING_HEART_RATE
              ? HealthDataUnit.BEATS_PER_MINUTE
              : HealthDataUnit.MILLISECOND;
          if (p.unit != expectedUnit || p.value is! NumericHealthValue) {
            continue;
          }
          final value = (p.value as NumericHealthValue).numericValue.toDouble();
          if (!value.isFinite ||
              value < 0 ||
              (type == HealthDataType.RESTING_HEART_RATE &&
                  (value < 1 || value > 300)) ||
              (type == HealthDataType.HEART_RATE_VARIABILITY_SDNN &&
                  value > 2000)) {
            continue;
          }
          values.putIfAbsent(_date(p.dateFrom.toLocal()), () => []).add(value);
        }
        final name = type == HealthDataType.RESTING_HEART_RATE
            ? 'resting_hr'
            : 'hrv_sdnn';
        for (final entry in values.entries) {
          bucket(entry.key, source)[name] =
              entry.value.reduce((a, b) => a + b) / entry.value.length;
          bucket(entry.key, source)['${name}_count'] = entry.value.length;
        }
      }
      final sleep =
          samples
              .where(
                (p) =>
                    p.type != HealthDataType.RESTING_HEART_RATE &&
                    p.type != HealthDataType.HEART_RATE_VARIABILITY_SDNN &&
                    p.dateTo.isAfter(p.dateFrom),
              )
              .toList()
            ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
      // Versioned session rule: gaps <= 3h remain one sleep session. Choose
      // longest measured session per local wake date; naps stay out of totals.
      var session = <HealthDataPoint>[];
      DateTime? end;
      void finish() {
        if (session.isEmpty) return;
        final asleep = _union(
          session.where((p) => p.type != HealthDataType.SLEEP_IN_BED),
        );
        final inBed = _union(
          session.where((p) => p.type == HealthDataType.SLEEP_IN_BED),
        );
        final minutes = _minutes(asleep);
        if (minutes <= 0 || minutes > 1440) return;
        final day = bucket(_date(end!.toLocal()), source);
        if ((day['sleep_hours'] as double? ?? -1) >= minutes / 60) return;
        day['sleep_hours'] = minutes / 60;
        final bedMinutes = _minutes(inBed);
        // Efficiency requires full containment; do not clamp inconsistent data.
        final covered = _intersectionMinutes(asleep, inBed);
        day['sleep_efficiency'] =
            bedMinutes > 0 && (covered - minutes).abs() < 0.001
            ? minutes / bedMinutes * 100
            : null;
      }

      for (final p in sleep) {
        if (end != null && p.dateFrom.difference(end).inMinutes > 180) {
          finish();
          session = [];
          end = null;
        }
        session.add(p);
        if (end == null || p.dateTo.isAfter(end)) end = p.dateTo;
      }
      finish();
    }
    return (days.keys.toList()..sort()).map((date) {
      final candidates = days[date]!;
      final ids = candidates.keys.toList()..sort();
      final record = <String, dynamic>{
        'date': date,
        'normalization_version': '2.0.0',
        'day_policy':
            'sleep_session_local_end_date;other_metrics_local_start_date',
      };
      final provenance = <String, dynamic>{};
      for (final metric in [
        'sleep_hours',
        'sleep_efficiency',
        'resting_hr',
        'hrv_sdnn',
      ]) {
        // Select one writer deterministically; never average across writers.
        // Sleep efficiency must use the same writer as sleep duration.
        final eligible = ids.where(
          (id) =>
              candidates[id]![metric == 'sleep_efficiency'
                  ? 'sleep_hours'
                  : metric] !=
              null,
        );
        final source = eligible.isEmpty ? null : eligible.first;
        record[metric] = source == null ? null : candidates[source]![metric];
        provenance[metric] = {
          'source_id': source,
          'selection': 'lexicographic_source_id_v1',
          'sample_count': source == null
              ? null
              : candidates[source]!['${metric}_count'],
        };
      }
      provenance['aggregation'] =
          'interval_union;longest_session;sample_mean;manual_excluded_v2';
      provenance['alternatives'] = candidates;
      provenance['timezone_basis'] = 'device_local_at_sync';
      record['metric_provenance'] = provenance;
      return record;
    }).toList();
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static List<(DateTime, DateTime)> _union(Iterable<HealthDataPoint> points) {
    final intervals = points.map((p) => (p.dateFrom, p.dateTo)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final result = <(DateTime, DateTime)>[];
    for (final interval in intervals) {
      if (result.isEmpty || interval.$1.isAfter(result.last.$2)) {
        result.add(interval);
      } else if (interval.$2.isAfter(result.last.$2)) {
        result[result.length - 1] = (result.last.$1, interval.$2);
      }
    }
    return result;
  }

  static double _minutes(List<(DateTime, DateTime)> intervals) => intervals
      .fold(0, (sum, p) => sum + p.$2.difference(p.$1).inMilliseconds / 60000);
  static double _intersectionMinutes(
    List<(DateTime, DateTime)> a,
    List<(DateTime, DateTime)> b,
  ) {
    var total = 0.0;
    for (final x in a) {
      for (final y in b) {
        final start = x.$1.isAfter(y.$1) ? x.$1 : y.$1;
        final end = x.$2.isBefore(y.$2) ? x.$2 : y.$2;
        if (end.isAfter(start)) {
          total += end.difference(start).inMilliseconds / 60000;
        }
      }
    }
    return total;
  }
}
