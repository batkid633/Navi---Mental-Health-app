// No unused imports

class BaselineDeviationResult {
  final double zScore;
  final bool isAnomalous;
  final String explanation;

  BaselineDeviationResult({
    required this.zScore,
    required this.isAnomalous,
    required this.explanation,
  });
}

class BaselineDeviationModel {
  /// Computes how unusual today's value is relative to recent history.
  ///
  /// [today]        → today's sentiment value
  /// [rollingMean]  → recent rolling average
  /// [rollingStd]   → recent rolling volatility (std dev)
  static BaselineDeviationResult evaluate({
    required double today,
    required double rollingMean,
    required double rollingStd,
  }) {
    // Guard against divide-by-zero or unstable early data
    if (rollingStd == 0) {
      return BaselineDeviationResult(
        zScore: 0,
        isAnomalous: false,
        explanation: "Not enough variation yet to assess deviation.",
      );
    }

    final z = (today - rollingMean) / rollingStd;
    final absZ = z.abs();

    String explanation;
    bool anomalous = false;

    if (absZ < 0.5) {
      explanation = "Today is well within your normal emotional range.";
    } else if (absZ < 1.0) {
      explanation = "Today shows a mild shift from your recent baseline.";
    } else if (absZ < 1.5) {
      explanation = "Today is noticeably different from your usual pattern.";
      anomalous = true;
    } else {
      explanation =
          "Today is highly unusual compared to your recent emotional baseline.";
      anomalous = true;
    }

    return BaselineDeviationResult(
      zScore: z,
      isAnomalous: anomalous,
      explanation: explanation,
    );
  }
}
