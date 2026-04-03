import 'package:flutter/material.dart';
import '../models/insight_trend.dart';

class MetricsDropdown extends StatefulWidget {
  final InsightTrend latest;

  const MetricsDropdown({
    super.key,
    required this.latest,
  });

  @override
  State<MetricsDropdown> createState() => _MetricsDropdownState();
}

class _MetricsDropdownState extends State<MetricsDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.latest;

    return Card(
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            title: const Text(
              "Numeric details",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),

          if (_expanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  _row("Mood", t.mood),
                  _row("Volatility", t.volatility),
                  _row("Trend slope", t.trendSlope),
                  _row("Sleep variability", t.sleepVar),
                  _row("HRV", t.hrv),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, num? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value != null ? value.toStringAsFixed(2) : "—",
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
