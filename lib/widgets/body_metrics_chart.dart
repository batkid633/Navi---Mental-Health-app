import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/insight_trend.dart';

class BodyMetricsGraph extends StatelessWidget {
  final List<InsightTrend> trends;

  const BodyMetricsGraph({super.key, required this.trends});

  @override
  Widget build(BuildContext context) {
    final sleepPoints = <FlSpot>[];
    final hrvPoints = <FlSpot>[];

    for (int i = 0; i < trends.length; i++) {
      if (trends[i].sleepVar != null) {
        sleepPoints.add(FlSpot(i.toDouble(), trends[i].sleepVar!));
      }
      if (trends[i].hrv != null) {
        hrvPoints.add(FlSpot(i.toDouble(), trends[i].hrv!));
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text("Body Recovery Signals", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: sleepPoints,
                      color: Colors.blue,
                      isCurved: true,
                      dotData: FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: hrvPoints,
                      color: Colors.purple,
                      isCurved: true,
                      dotData: FlDotData(show: false),
                    ),
                  ],
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: true),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(width: 12, height: 2, color: Colors.blue),
                    const SizedBox(width: 4),
                    const Text("Sleep Variance", style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(width: 16),
                Row(
                  children: [
                    Container(width: 12, height: 2, color: Colors.purple),
                    const SizedBox(width: 4),
                    const Text("HRV", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}