import 'package:flutter/material.dart';

import '../models/insight_trend.dart';
import '../services/analytics_service.dart';
import '../services/data_service.dart';
import '../services/insight_api.dart';
import '../services/insights_service.dart';
import '../services/settings_service.dart';
import '../widgets/mood_trend_chart.dart';

class InsightsPage extends StatefulWidget {
  final DataService dataService;

  const InsightsPage({super.key, required this.dataService});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  static const List<int> _windows = [1, 3, 7, 14];

  late Future<List<InsightTrend>> _trendsFuture;
  int _selectedWindow = 14;

  @override
  void initState() {
    super.initState();
    _trendsFuture = _loadTrends(14);
  }

  void _reloadTrends() {
    setState(() {
      _trendsFuture = _loadTrends(14);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!SettingsService.personalizedInsightsEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Insights')),
        body: const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Personalized insights are off. You can turn them back on in Settings.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: FutureBuilder<List<InsightTrend>>(
        future: _trendsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _InsightsError(
              message: 'Error loading insights: ${snapshot.error}',
              onRetry: _reloadTrends,
            );
          }

          final trends = snapshot.data ?? [];
          if (trends.isEmpty) {
            return _InsightsEmpty(onRefresh: _reloadTrends);
          }

          final summaries = _buildWindowSummaries(trends);
          final selectedSummary = _selectedSummary(summaries);
          final visibleTrends = _windowedTrends(trends, selectedSummary.days);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InsightOverviewCard(
                latest: trends.last,
                summaries: summaries,
                totalDays: trends.length,
              ),
              _WindowSelector(
                windows: _windows,
                selectedWindow: selectedSummary.days,
                totalDays: trends.length,
                onSelected: (days) {
                  setState(() {
                    _selectedWindow = days;
                  });
                },
              ),
              _UnlockProgressCard(totalDays: trends.length),
              _SelectedWindowCard(summary: selectedSummary),
              MoodTrendGraph(trends: visibleTrends),
              _WindowSummaryTable(
                summaries: summaries,
                selectedWindow: selectedSummary.days,
                onSelect: (days) {
                  setState(() {
                    _selectedWindow = days;
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<List<InsightTrend>> _loadTrends(int days) async {
    try {
      final trends = await InsightsApi.fetchTrends(days);
      await AnalyticsService.track(
        'insights_loaded',
        properties: {
          'source': 'backend',
          'days': days,
          'point_count': trends.length,
        },
      );
      return trends;
    } catch (_) {
      await AnalyticsService.track(
        'insights_backend_failed',
        properties: {'days': days},
      );
      final trends = await _loadLocalTrends(days);
      await AnalyticsService.track(
        'insights_loaded',
        properties: {
          'source': 'local',
          'days': days,
          'point_count': trends.length,
        },
      );
      return trends;
    }
  }

  Future<List<InsightTrend>> _loadLocalTrends(int days) async {
    final box = await widget.dataService.getJournalBox();
    final dailyAvg = InsightsService.dailyAverageSentiment(box);
    if (dailyAvg.isEmpty) {
      return [];
    }

    final sortedDays = dailyAvg.keys.toList()..sort();
    final recentDays = sortedDays.length > days
        ? sortedDays.sublist(sortedDays.length - days)
        : sortedDays;
    final recentAvg = {for (final day in recentDays) day: dailyAvg[day]!};
    final volatility = InsightsService.rollingVolatility(recentAvg, 7);
    final momentum = InsightsService.rollingMomentum(recentAvg, 7);

    return recentDays.map((day) {
      final mood = dailyAvg[day] ?? 0.0;
      final slope = momentum[day] ?? 0.0;
      return InsightTrend(
        date: day.toIso8601String(),
        mood: mood,
        volatility: volatility[day],
        trendSlope: slope,
        state: _stateForMood(mood, slope),
      );
    }).toList();
  }

  _WindowSummary _selectedSummary(List<_WindowSummary> summaries) {
    final requested = summaries.firstWhere(
      (summary) => summary.days == _selectedWindow,
      orElse: () => summaries.lastWhere((summary) => summary.unlocked),
    );
    if (requested.unlocked) {
      return requested;
    }
    return summaries.lastWhere((summary) => summary.unlocked);
  }

  List<InsightTrend> _windowedTrends(List<InsightTrend> trends, int days) {
    if (trends.length <= days) {
      return trends;
    }
    return trends.sublist(trends.length - days);
  }

  List<_WindowSummary> _buildWindowSummaries(List<InsightTrend> trends) {
    return _windows.map((days) {
      final unlocked = trends.length >= days;
      final window = unlocked
          ? _windowedTrends(trends, days)
          : <InsightTrend>[];
      if (window.isEmpty) {
        return _WindowSummary.locked(
          days: days,
          daysNeeded: days - trends.length,
        );
      }

      final first = window.first;
      final latest = window.last;
      final double? delta = window.length == 1
          ? null
          : latest.mood - first.mood;
      final volatilityValues = window
          .map((trend) => trend.volatility)
          .whereType<double>()
          .toList();
      final avgVolatility = volatilityValues.isEmpty
          ? null
          : volatilityValues.reduce((a, b) => a + b) / volatilityValues.length;
      final bodyDays = window
          .where((trend) => trend.hrv != null || trend.sleepVar != null)
          .length;

      return _WindowSummary(
        days: days,
        unlocked: true,
        direction: delta == null
            ? _moodLabel(latest.mood)
            : _directionLabel(delta),
        delta: delta,
        volatility: avgVolatility,
        dataUsed: bodyDays > 0 ? 'Journal + body' : 'Journal',
        signalStrength: _signalStrength(
          days: days,
          bodyDays: bodyDays,
          avgVolatility: avgVolatility,
        ),
        daysNeeded: 0,
      );
    }).toList();
  }

  String _stateForMood(double mood, double slope) {
    if (mood >= 0.25 && slope >= -0.03) return 'Stable Positive';
    if (mood <= -0.25 && slope <= 0.03) return 'Low';
    if (slope > 0.05) return 'Improving';
    if (slope < -0.05) return 'Declining';
    return 'Stable';
  }

  String _moodLabel(double mood) {
    if (mood >= 0.35) return 'Positive';
    if (mood >= 0.10) return 'Slightly positive';
    if (mood > -0.10) return 'Neutral';
    if (mood > -0.35) return 'Slightly low';
    return 'Low';
  }

  String _directionLabel(double delta) {
    if (delta >= 0.30) return 'Improving';
    if (delta >= 0.10) return 'Slightly improving';
    if (delta > -0.10) return 'Stable';
    if (delta > -0.30) return 'Slight dip';
    return 'Dipping';
  }

  String _signalStrength({
    required int days,
    required int bodyDays,
    required double? avgVolatility,
  }) {
    var score = 0;
    if (days >= 3) score++;
    if (days >= 7) score++;
    if (days >= 14) score++;
    if (bodyDays >= (days / 2).ceil()) score++;
    if (avgVolatility != null && avgVolatility < 0.35) score++;
    if (score >= 4) return 'Stronger';
    if (score >= 2) return 'Moderate';
    return 'Early';
  }
}

class _WindowSummary {
  final int days;
  final bool unlocked;
  final String direction;
  final double? delta;
  final double? volatility;
  final String dataUsed;
  final String signalStrength;
  final int daysNeeded;

  const _WindowSummary({
    required this.days,
    required this.unlocked,
    required this.direction,
    required this.delta,
    required this.volatility,
    required this.dataUsed,
    required this.signalStrength,
    required this.daysNeeded,
  });

  factory _WindowSummary.locked({required int days, required int daysNeeded}) {
    return _WindowSummary(
      days: days,
      unlocked: false,
      direction: 'Locked',
      delta: null,
      volatility: null,
      dataUsed: 'More logs needed',
      signalStrength: 'Pending',
      daysNeeded: daysNeeded,
    );
  }

  String get label => '${days}D';
}

class _InsightOverviewCard extends StatelessWidget {
  final InsightTrend latest;
  final List<_WindowSummary> summaries;
  final int totalDays;

  const _InsightOverviewCard({
    required this.latest,
    required this.summaries,
    required this.totalDays,
  });

  @override
  Widget build(BuildContext context) {
    final longestUnlocked = summaries.lastWhere((summary) => summary.unlocked);
    final bodyEnabled = summaries.any(
      (summary) => summary.dataUsed == 'Journal + body',
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_graph),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Current pattern',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text(longestUnlocked.signalStrength),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              longestUnlocked.direction,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Based on $totalDays logged day${totalDays == 1 ? '' : 's'}; longest active window is ${longestUnlocked.label}.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _OverviewChip(
                  icon: Icons.mood,
                  label: 'Mood',
                  value: _formatMood(latest.mood),
                ),
                _OverviewChip(
                  icon: Icons.show_chart,
                  label: 'Volatility',
                  value: latest.volatility == null
                      ? 'Not ready'
                      : _formatVolatility(latest.volatility!),
                ),
                _OverviewChip(
                  icon: bodyEnabled
                      ? Icons.favorite_outline
                      : Icons.edit_note_outlined,
                  label: 'Data',
                  value: bodyEnabled ? 'Journal + body' : 'Journal',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatMood(double value) {
    if (value >= 0.35) return 'Positive';
    if (value >= 0.10) return 'Slightly positive';
    if (value > -0.10) return 'Neutral';
    if (value > -0.35) return 'Slightly low';
    return 'Low';
  }

  String _formatVolatility(double value) {
    if (value < 0.12) return 'Very steady';
    if (value < 0.25) return 'Steady';
    if (value < 0.45) return 'Variable';
    return 'Highly variable';
  }
}

class _OverviewChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _OverviewChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _WindowSelector extends StatelessWidget {
  final List<int> windows;
  final int selectedWindow;
  final int totalDays;
  final ValueChanged<int> onSelected;

  const _WindowSelector({
    required this.windows,
    required this.selectedWindow,
    required this.totalDays,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trend window',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: windows.map((days) {
                final unlocked = totalDays >= days;
                final selected = selectedWindow == days;
                return ChoiceChip(
                  label: Text('${days}D'),
                  selected: selected && unlocked,
                  onSelected: unlocked ? (_) => onSelected(days) : null,
                  avatar: unlocked
                      ? null
                      : const Icon(Icons.lock_outline, size: 16),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnlockProgressCard extends StatelessWidget {
  final int totalDays;

  const _UnlockProgressCard({required this.totalDays});

  @override
  Widget build(BuildContext context) {
    int? nextWindow;
    for (final days in _InsightsPageState._windows) {
      if (days > totalDays) {
        nextWindow = days;
        break;
      }
    }
    if (nextWindow == null) {
      return const SizedBox.shrink();
    }

    final remaining = nextWindow - totalDays;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.lock_open_outlined),
        title: Text('Next unlock: ${nextWindow}D trend'),
        subtitle: Text(
          '$remaining more logged day${remaining == 1 ? '' : 's'} will unlock the next window.',
        ),
      ),
    );
  }
}

class _SelectedWindowCard extends StatelessWidget {
  final _WindowSummary summary;

  const _SelectedWindowCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(child: Text(summary.label)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${summary.label} focus',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary.unlocked
                        ? '${summary.direction} | ${summary.dataUsed} | ${summary.signalStrength} signal'
                        : '${summary.daysNeeded} more logged day${summary.daysNeeded == 1 ? '' : 's'} needed',
                  ),
                ],
              ),
            ),
            if (summary.unlocked)
              Text(
                _formatDelta(summary.delta),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDelta(double? value) {
    if (value == null) return 'Today';
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(2)}';
  }
}

class _WindowSummaryTable extends StatelessWidget {
  final List<_WindowSummary> summaries;
  final int selectedWindow;
  final ValueChanged<int> onSelect;

  const _WindowSummaryTable({
    required this.summaries,
    required this.selectedWindow,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_chart_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Window summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...summaries.map((summary) {
              return _WindowSummaryRow(
                summary: summary,
                selected: summary.days == selectedWindow,
                onTap: summary.unlocked ? () => onSelect(summary.days) : null,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _WindowSummaryRow extends StatelessWidget {
  final _WindowSummary summary;
  final bool selected;
  final VoidCallback? onTap;

  const _WindowSummaryRow({
    required this.summary,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = selected
        ? colorScheme.primaryContainer.withValues(alpha: 0.35)
        : Colors.transparent;
    final subtitle = summary.unlocked
        ? '${summary.dataUsed} | ${_formatVolatility(summary.volatility)} | ${summary.signalStrength} signal'
        : '${summary.daysNeeded} more logged day${summary.daysNeeded == 1 ? '' : 's'} needed';

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: CircleAvatar(radius: 18, child: Text(summary.label)),
        title: Text(
          summary.direction,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: summary.unlocked
            ? Text(
                _formatDelta(summary.delta),
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            : const Icon(Icons.lock_outline),
        onTap: onTap,
      ),
    );
  }

  String _formatDelta(double? value) {
    if (value == null) return 'Today';
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(2)}';
  }

  String _formatVolatility(double? value) {
    if (value == null) return 'volatility pending';
    if (value < 0.12) return 'very steady';
    if (value < 0.25) return 'steady';
    if (value < 0.45) return 'variable';
    return 'highly variable';
  }
}

class _InsightsEmpty extends StatelessWidget {
  final VoidCallback onRefresh;

  const _InsightsEmpty({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.query_stats, size: 36),
            const SizedBox(height: 12),
            const Text(
              'No insight data yet.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add journal entries over time to unlock trend windows.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InsightsError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
