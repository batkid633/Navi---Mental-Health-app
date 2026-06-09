import 'package:flutter/material.dart';

class TomorrowOutlook {
  final double predictedDelta;
  final double confidence;
  final String? modelVersion;
  final String? insight;
  final List<TrajectoryPoint> trajectory;
  final TrajectorySummary? trajectorySummary;
  final ModalityCoverage? modalityCoverage;
  final ValidationDiagnostics? validation;

  TomorrowOutlook({
    required this.predictedDelta,
    required this.confidence,
    this.modelVersion,
    this.insight,
    this.trajectory = const [],
    this.trajectorySummary,
    this.modalityCoverage,
    this.validation,
  });

  factory TomorrowOutlook.fromJson(Map<String, dynamic> json) {
    return TomorrowOutlook(
      predictedDelta: (json['predicted_delta'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      modelVersion: json['model_version']?.toString(),
      insight: json['insight'],
      trajectory: (json['trajectory'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => TrajectoryPoint.fromJson(item))
          .toList(),
      trajectorySummary: json['trajectory_summary'] is Map
          ? TrajectorySummary.fromJson(json['trajectory_summary'] as Map)
          : null,
      modalityCoverage: json['modality_coverage'] is Map
          ? ModalityCoverage.fromJson(json['modality_coverage'] as Map)
          : null,
      validation: json['validation'] is Map
          ? ValidationDiagnostics.fromJson(json['validation'] as Map)
          : null,
    );
  }

  String get label {
    if (predictedDelta > 0.3) return "Likely improvement tomorrow";
    if (predictedDelta > 0.1) return "Slightly better tomorrow";
    if (predictedDelta > -0.1) return "Likely stable";
    if (predictedDelta > -0.3) return "Slight dip possible";
    return "Higher risk of a tough day";
  }

  Color get color {
    if (predictedDelta > 0.3) return Colors.green;
    if (predictedDelta > 0.1) return Colors.lightGreen;
    if (predictedDelta > -0.1) return Colors.grey;
    if (predictedDelta > -0.3) return Colors.orange;
    return Colors.redAccent;
  }

  String get trajectoryLabel {
    final direction = trajectorySummary?.direction;
    switch (direction) {
      case 'improving':
        return 'Trajectory improving';
      case 'declining':
        return 'Trajectory dipping';
      case 'variable':
        return 'Trajectory variable';
      case 'stable':
        return 'Trajectory steady';
      default:
        return label;
    }
  }
}

class TrajectoryPoint {
  final int horizonDays;
  final double predictedMood;
  final double predictedDelta;
  final double uncertainty;
  final double confidence;

  TrajectoryPoint({
    required this.horizonDays,
    required this.predictedMood,
    required this.predictedDelta,
    required this.uncertainty,
    required this.confidence,
  });

  factory TrajectoryPoint.fromJson(Map<dynamic, dynamic> json) {
    return TrajectoryPoint(
      horizonDays: (json['horizon_days'] as num?)?.toInt() ?? 1,
      predictedMood: (json['predicted_mood'] as num?)?.toDouble() ?? 0.0,
      predictedDelta: (json['predicted_delta'] as num?)?.toDouble() ?? 0.0,
      uncertainty: (json['uncertainty'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class TrajectorySummary {
  final String? direction;
  final double? baselineMood;
  final double? trendPerDay;
  final double? volatility;
  final double? biometricAdjustment;
  final double? audioAdjustment;
  final double? keyboardAdjustment;
  final String? modelFamily;

  TrajectorySummary({
    this.direction,
    this.baselineMood,
    this.trendPerDay,
    this.volatility,
    this.biometricAdjustment,
    this.audioAdjustment,
    this.keyboardAdjustment,
    this.modelFamily,
  });

  factory TrajectorySummary.fromJson(Map<dynamic, dynamic> json) {
    return TrajectorySummary(
      direction: json['direction']?.toString(),
      baselineMood: _doubleFromJson(json['baseline_mood']),
      trendPerDay: _doubleFromJson(json['trend_per_day']),
      volatility: _doubleFromJson(json['volatility']),
      biometricAdjustment: _doubleFromJson(json['biometric_adjustment']),
      audioAdjustment: _doubleFromJson(json['audio_adjustment']),
      keyboardAdjustment: _doubleFromJson(json['keyboard_adjustment']),
      modelFamily: json['model_family']?.toString(),
    );
  }
}

class ModalityCoverage {
  final bool journal;
  final bool biometric;
  final bool audio;
  final bool keyboard;
  final List<String> availableModalities;
  final double coverageRatio;

  ModalityCoverage({
    required this.journal,
    required this.biometric,
    required this.audio,
    required this.keyboard,
    required this.availableModalities,
    required this.coverageRatio,
  });

  factory ModalityCoverage.fromJson(Map<dynamic, dynamic> json) {
    final modalities = json['modalities'] is Map
        ? json['modalities'] as Map<dynamic, dynamic>
        : const {};
    return ModalityCoverage(
      journal: modalities['journal'] == true,
      biometric: modalities['biometric'] == true,
      audio: modalities['audio'] == true,
      keyboard: modalities['keyboard'] == true,
      availableModalities:
          (json['available_modalities'] as List<dynamic>? ?? [])
              .map((item) => item.toString())
              .toList(),
      coverageRatio: _doubleFromJson(json['coverage_ratio']) ?? 0.0,
    );
  }
}

class ValidationDiagnostics {
  final int sampleCount;
  final bool validationReady;
  final String? reason;
  final double? persistenceBaselineMae;
  final int? targetRows;

  ValidationDiagnostics({
    required this.sampleCount,
    required this.validationReady,
    this.reason,
    this.persistenceBaselineMae,
    this.targetRows,
  });

  factory ValidationDiagnostics.fromJson(Map<dynamic, dynamic> json) {
    return ValidationDiagnostics(
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
      validationReady: json['validation_ready'] == true,
      reason: json['reason']?.toString(),
      persistenceBaselineMae: _doubleFromJson(json['persistence_baseline_mae']),
      targetRows: (json['target_rows'] as num?)?.toInt(),
    );
  }
}

double? _doubleFromJson(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
