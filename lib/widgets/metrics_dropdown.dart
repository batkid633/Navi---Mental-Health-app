import 'package:flutter/material.dart';

import '../models/insight_trend.dart';

class MetricsDropdown extends StatefulWidget {
  final InsightTrend latest;

  const MetricsDropdown({super.key, required this.latest});

  @override
  State<MetricsDropdown> createState() => _MetricsDropdownState();
}

class _MetricsDropdownState extends State<MetricsDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final trend = widget.latest;
    final hasBodyMetrics = trend.sleepVar != null || trend.hrv != null;

    return Card(
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.summarize_outlined),
            title: const Text(
              'Latest insight summary',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(_dateLabel(trend.date)),
            trailing: IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              tooltip: _expanded ? 'Hide details' : 'Show details',
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  icon: Icons.mood,
                  label: 'Mood',
                  value: _formatMood(trend.mood),
                  tooltip:
                      'Average journal sentiment for the latest available day.',
                ),
                if (trend.trendSlope != null)
                  _MetricChip(
                    icon: _trendIcon(trend.trendSlope!),
                    label: 'Trend',
                    value: _formatTrend(trend.trendSlope!),
                    tooltip:
                        'Recent direction of your journal sentiment trend.',
                  ),
                if (trend.volatility != null)
                  _MetricChip(
                    icon: Icons.show_chart,
                    label: 'Stability',
                    value: _formatVolatility(trend.volatility!),
                    tooltip:
                        'How much your recent mood scores are moving around.',
                  ),
                if (trend.state.trim().isNotEmpty &&
                    trend.state.toLowerCase() != 'unknown')
                  _MetricChip(
                    icon: Icons.flag_outlined,
                    label: 'State',
                    value: trend.state,
                    tooltip: 'Current classification from your trend data.',
                  ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _explanation(
                    'Mood',
                    '${_formatMood(trend.mood)} (${trend.mood.toStringAsFixed(2)})',
                    'Scores above zero lean positive, below zero lean negative, and near zero are neutral.',
                  ),
                  if (trend.volatility != null)
                    _explanation(
                      'Stability',
                      '${_formatVolatility(trend.volatility!)} (${trend.volatility!.toStringAsFixed(2)})',
                      'Lower values mean recent entries are more consistent; higher values mean more day-to-day movement.',
                    ),
                  if (trend.trendSlope != null)
                    _explanation(
                      'Trend',
                      '${_formatTrend(trend.trendSlope!)} (${_signed(trend.trendSlope!)})',
                      'Positive means the recent direction is improving; negative means it is drifting lower.',
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Body metrics',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  if (hasBodyMetrics) ...[
                    if (trend.hrv != null)
                      _compactRow('HRV', '${trend.hrv!.toStringAsFixed(1)} ms'),
                    if (trend.sleepVar != null)
                      _compactRow(
                        'Sleep variability',
                        trend.sleepVar!.toStringAsFixed(2),
                      ),
                  ] else
                    const Text(
                      'No WHOOP/body metric trend data is available for this day yet.',
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _explanation(String label, String value, String helpText) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 3),
          Text(helpText, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _compactRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _dateLabel(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return rawDate;
    return 'Latest data: ${parsed.month}/${parsed.day}/${parsed.year}';
  }

  String _formatMood(double value) {
    if (value >= 0.35) return 'Positive';
    if (value >= 0.10) return 'Slightly positive';
    if (value > -0.10) return 'Neutral';
    if (value > -0.35) return 'Slightly low';
    return 'Low';
  }

  String _formatTrend(double value) {
    if (value >= 0.08) return 'Improving';
    if (value >= 0.02) return 'Slightly improving';
    if (value > -0.02) return 'Steady';
    if (value > -0.08) return 'Slightly declining';
    return 'Declining';
  }

  String _formatVolatility(double value) {
    if (value < 0.12) return 'Very steady';
    if (value < 0.25) return 'Steady';
    if (value < 0.45) return 'Variable';
    return 'Highly variable';
  }

  IconData _trendIcon(double value) {
    if (value > 0.02) return Icons.trending_up;
    if (value < -0.02) return Icons.trending_down;
    return Icons.trending_flat;
  }

  String _signed(double value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(2)}';
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String tooltip;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Chip(
        avatar: Icon(icon, size: 18),
        label: Text('$label: $value'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
