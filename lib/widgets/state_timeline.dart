import 'package:flutter/material.dart';
import '../models/insight_trend.dart';

class StateTimeline extends StatelessWidget {
  final List<InsightTrend> trends;

  const StateTimeline({super.key, required this.trends});

  Color stateColor(String state) {
    switch (state) {
      case "Stable":
        return Colors.green;
      case "Volatile":
        return Colors.red;
      case "Recovering":
        return Colors.orange;
      case "Declining":
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reverse the trends to show newest first
    final reversedTrends = trends.reversed.toList();
    return Column(
      children: reversedTrends.map((t) {
        return ListTile(
          title: Text(t.date),
          trailing: Chip(
            label: Text(t.state),
            backgroundColor: stateColor(t.state),
          ),
        );
      }).toList(),
    );
  }
}