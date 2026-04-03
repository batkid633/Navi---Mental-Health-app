import 'package:flutter/material.dart';
import 'longitudinal_line_graph.dart';
import '../models/insight_trend.dart';

class MoodTrendGraph extends StatelessWidget {
  final List<InsightTrend> trends;

  const MoodTrendGraph({super.key, required this.trends});

  @override
  Widget build(BuildContext context) {
    return LongitudinalLineGraph(
      trends: trends,
      selector: (t) => t.mood,
      title: "Mood Trend",
      color: Colors.green,
      minY: -1,
      maxY: 1,
      yAxisLabel: "Sentiment Score",
    );
  }
}