import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

    final allYValues = <double>[
      ...sleepPoints.map((point) => point.y),
      ...hrvPoints.map((point) => point.y),
    ];
    final minY = allYValues.isEmpty ? 0.0 : allYValues.reduce(min);
    final maxY = allYValues.isEmpty ? 1.0 : allYValues.reduce(max);
    final yRange = maxY - minY;
    final displayMinY = min(0.0, minY - yRange * 0.1);
    final displayMaxY = maxY + yRange * 0.1;
    final interval = _niceInterval(displayMinY, displayMaxY);

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
                  minX: 0,
                  maxX: max(0, trends.length - 1).toDouble(),
                  minY: displayMinY,
                  maxY: displayMaxY,
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
                      axisNameWidget: const Text('Value', style: TextStyle(fontSize: 12)),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: interval,
                        getTitlesWidget: (value, meta) {
                          final label = value % 1 == 0
                              ? value.toInt().toString()
                              : value.toStringAsFixed(1);
                          return Text(label, style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: interval,
                        getTitlesWidget: (value, meta) {
                          final label = value % 1 == 0
                              ? value.toInt().toString()
                              : value.toStringAsFixed(1);
                          return Text(label, style: const TextStyle(fontSize: 10));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: trends.length > 7 ? (trends.length / 7).ceil().toDouble() : 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < trends.length) {
                            try {
                              final date = DateTime.parse(trends[index].date);
                              final formatter = DateFormat('MM/dd');
                              return Text(
                                formatter.format(date),
                                style: const TextStyle(fontSize: 10),
                              );
                            } catch (_) {
                              return Text(
                                '${index + 1}',
                                style: const TextStyle(fontSize: 10),
                              );
                            }
                          }
                          return const SizedBox.shrink();
                        },
                      ),
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

  double _niceInterval(double minY, double maxY) {
    final range = maxY - minY;
    if (range <= 0) return 1;
    final magnitude = pow(10, (log(range) / ln10).floor()).toDouble();
    final normalized = range / magnitude;
    if (normalized <= 1) {
      return magnitude / 5;
    } else if (normalized <= 2) {
      return magnitude / 2;
    } else if (normalized <= 5) {
      return magnitude;
    }
    return magnitude * 2;
  }
}