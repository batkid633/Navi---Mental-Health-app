import 'package:flutter/material.dart';

class TomorrowOutlook {
  final double predictedDelta;
  final double confidence;
  final String? insight;

  TomorrowOutlook({
    required this.predictedDelta,
    required this.confidence,
    this.insight,
  });

  factory TomorrowOutlook.fromJson(Map<String, dynamic> json) {
    return TomorrowOutlook(
      predictedDelta: (json['predicted_delta'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      insight: json['insight'],
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
}
