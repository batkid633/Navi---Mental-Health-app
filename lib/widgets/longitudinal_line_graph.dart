import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/insight_trend.dart';

class LongitudinalLineGraph extends StatelessWidget {
  final List<InsightTrend> trends;
  final double? Function(InsightTrend) selector;
  final String title;
  final Color color;
  final double? minY;
  final double? maxY;
  final String? yAxisLabel;

  const LongitudinalLineGraph({
    super.key,
    required this.trends,
    required this.selector,
    required this.title,
    this.color = Colors.blue,
    this.minY,
    this.maxY,
    this.yAxisLabel,
  });

  @override
  Widget build(BuildContext context) {
    final points = <FlSpot>[];

    for (int i = 0; i < trends.length; i++) {
      final val = selector(trends[i]);
      if (val != null) {
        points.add(FlSpot(i.toDouble(), val));
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: trends.length.toDouble(),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: points,
                      isCurved: true,
                      color: color,
                      dotData: FlDotData(show: false),
                    )
                  ],
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      axisNameWidget: yAxisLabel != null ? Text(yAxisLabel!, style: TextStyle(fontSize: 12)) : null,
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: null,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}