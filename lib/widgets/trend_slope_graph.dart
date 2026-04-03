import 'package:flutter/material.dart';
import 'longitudinal_line_graph.dart';
import '../models/insight_trend.dart';

class TrendSlopeGraph extends StatelessWidget {
  final List<InsightTrend> trends;

  const TrendSlopeGraph({super.key, required this.trends});

  @override
  Widget build(BuildContext context) {
    return LongitudinalLineGraph(
      trends: trends,
      selector: (t) => t.trendSlope,
      title: "Emotional Trajectory",
      color: Colors.orange,
      minY: -1,
      maxY: 1,
      yAxisLabel: "Slope",
    );
  }
}