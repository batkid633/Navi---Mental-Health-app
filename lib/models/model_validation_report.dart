class ModelValidationReport {
  final int rowCount;
  final DateRangeSummary dateRange;
  final CoverageSummary coverage;
  final ReadinessSummary readiness;
  final List<HorizonMetric> horizonMetrics;
  final List<String> recommendedValidation;

  ModelValidationReport({
    required this.rowCount,
    required this.dateRange,
    required this.coverage,
    required this.readiness,
    required this.horizonMetrics,
    required this.recommendedValidation,
  });

  factory ModelValidationReport.fromJson(Map<String, dynamic> json) {
    return ModelValidationReport(
      rowCount: (json['row_count'] as num?)?.toInt() ?? 0,
      dateRange: DateRangeSummary.fromJson(
        (json['date_range'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      coverage: CoverageSummary.fromJson(
        (json['coverage'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      readiness: ReadinessSummary.fromJson(
        (json['readiness'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      horizonMetrics: (json['horizon_metrics'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => HorizonMetric.fromJson(item.cast<String, dynamic>()))
          .toList(),
      recommendedValidation:
          (json['recommended_validation'] as List<dynamic>? ?? [])
              .map((item) => item.toString())
              .toList(),
    );
  }
}

class DateRangeSummary {
  final String? start;
  final String? end;

  DateRangeSummary({this.start, this.end});

  factory DateRangeSummary.fromJson(Map<String, dynamic> json) {
    return DateRangeSummary(
      start: json['start']?.toString(),
      end: json['end']?.toString(),
    );
  }
}

class CoverageSummary {
  final int journalDays;
  final int biometricDays;
  final int audioDays;
  final int fullyMultimodalDays;
  final double journalRatio;
  final double biometricRatio;
  final double audioRatio;
  final double fullyMultimodalRatio;

  CoverageSummary({
    required this.journalDays,
    required this.biometricDays,
    required this.audioDays,
    required this.fullyMultimodalDays,
    required this.journalRatio,
    required this.biometricRatio,
    required this.audioRatio,
    required this.fullyMultimodalRatio,
  });

  factory CoverageSummary.fromJson(Map<String, dynamic> json) {
    return CoverageSummary(
      journalDays: (json['journal_days'] as num?)?.toInt() ?? 0,
      biometricDays: (json['biometric_days'] as num?)?.toInt() ?? 0,
      audioDays: (json['audio_days'] as num?)?.toInt() ?? 0,
      fullyMultimodalDays:
          (json['fully_multimodal_days'] as num?)?.toInt() ?? 0,
      journalRatio: _double(json['journal_ratio']),
      biometricRatio: _double(json['biometric_ratio']),
      audioRatio: _double(json['audio_ratio']),
      fullyMultimodalRatio: _double(json['fully_multimodal_ratio']),
    );
  }
}

class ReadinessSummary {
  final int dailyRows;
  final int targetRows;
  final bool earlyValidationReady;
  final bool multimodalValidationReady;
  final bool studyReady;
  final List<String> blockers;

  ReadinessSummary({
    required this.dailyRows,
    required this.targetRows,
    required this.earlyValidationReady,
    required this.multimodalValidationReady,
    required this.studyReady,
    required this.blockers,
  });

  factory ReadinessSummary.fromJson(Map<String, dynamic> json) {
    return ReadinessSummary(
      dailyRows: (json['daily_rows'] as num?)?.toInt() ?? 0,
      targetRows: (json['target_rows'] as num?)?.toInt() ?? 0,
      earlyValidationReady: json['early_validation_ready'] == true,
      multimodalValidationReady: json['multimodal_validation_ready'] == true,
      studyReady: json['study_ready'] == true,
      blockers: (json['blockers'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class HorizonMetric {
  final int horizonDays;
  final int targetCount;
  final double? persistenceBaselineMae;

  HorizonMetric({
    required this.horizonDays,
    required this.targetCount,
    this.persistenceBaselineMae,
  });

  factory HorizonMetric.fromJson(Map<String, dynamic> json) {
    return HorizonMetric(
      horizonDays: (json['horizon_days'] as num?)?.toInt() ?? 0,
      targetCount: (json['target_count'] as num?)?.toInt() ?? 0,
      persistenceBaselineMae: json['persistence_baseline_mae'] == null
          ? null
          : _double(json['persistence_baseline_mae']),
    );
  }
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}
