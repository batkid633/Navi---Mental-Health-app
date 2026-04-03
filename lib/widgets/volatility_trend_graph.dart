import 'package:flutter/material.dart';
import 'longitudinal_line_graph.dart';
import '../models/insight_trend.dart';

class VolatilityTrendGraph extends StatelessWidget {
  final List<InsightTrend> trends;

  const VolatilityTrendGraph({super.key, required this.trends});

  @override
  Widget build(BuildContext context) {
    return LongitudinalLineGraph(
      trends: trends,
      selector: (t) => t.volatility,
      title: "Mood Volatility",
      color: Colors.red,
      minY: 0,
      yAxisLabel: "Volatility",
    );
  }
}