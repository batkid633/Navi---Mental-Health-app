import 'package:flutter/material.dart';
import '../widgets/mood_trend_chart.dart';
import '../widgets/body_metrics_chart.dart';
import '../widgets/volatility_trend_graph.dart';
import '../widgets/trend_slope_graph.dart';
import '../widgets/metrics_dropdown.dart';
import '../models/insight_trend.dart';
import '../models/model_validation_report.dart';
import '../models/tomorrow_outlook.dart';
import '../services/analytics_service.dart';
import '../services/insight_api.dart';
import '../services/ml_prediction_service.dart';
import '../services/whoop_service.dart';
import '../services/data_service.dart';
import '../services/insights_service.dart';
import '../services/settings_service.dart';

class InsightsPage extends StatefulWidget {
  final DataService dataService;

  const InsightsPage({super.key, required this.dataService});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  static const List<int> _windows = [1, 3, 7, 14];

  late Future<List<InsightTrend>> _trendsFuture;
  late Future<ModelValidationReport?> _validationReportFuture;
  late Future<TomorrowOutlook?> _trajectoryFuture;
  int _selectedWindow = 14;
  bool _isSyncingWhoop = false;
  String? _whoopSyncMessage;

  void _reloadTrends() {
    setState(() {
      _trendsFuture = _loadTrends(14);
      _validationReportFuture = _loadValidationReport();
      _trajectoryFuture = _loadTrajectoryOutlook();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!SettingsService.personalizedInsightsEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text("Insights")),
        body: const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Personalized insights are off. You can turn them back on in Settings.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Insights")),
      body: FutureBuilder<List<InsightTrend>>(
        future: _trendsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      'Error loading insights: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _reloadTrends,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
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
                      'Add journal entries over time to unlock trend charts.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _reloadTrends,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
            );
          }

          final trends = snapshot.data!;
          final latest = trends.last;
          final summaries = _buildWindowSummaries(trends);
          final requestedSummary = summaries.firstWhere(
            (summary) => summary.days == _selectedWindow,
            orElse: () => summaries.lastWhere((summary) => summary.unlocked),
          );
          final selectedSummary = requestedSummary.unlocked
              ? requestedSummary
              : summaries.lastWhere((summary) => summary.unlocked);
          final visibleTrends = _windowedTrends(trends, selectedSummary.days);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InsightOverviewCard(
                latest: latest,
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
              MoodTrendGraph(trends: visibleTrends),
              VolatilityTrendGraph(trends: visibleTrends),
              TrendSlopeGraph(trends: visibleTrends),
              if (_hasBodySignals(visibleTrends))
                BodyMetricsGraph(trends: visibleTrends),
              _WindowSummaryTable(
                summaries: summaries,
                selectedWindow: selectedSummary.days,
                onSelect: (days) {
                  setState(() {
                    _selectedWindow = days;
                  });
                },
              ),
              MetricsDropdown(latest: latest),
              _WhoopSyncCard(
                isSyncing: _isSyncingWhoop,
                message: _whoopSyncMessage,
                onSync: _syncWhoopMetrics,
              ),
              FutureBuilder<TomorrowOutlook?>(
                future: _trajectoryFuture,
                builder: (context, trajectorySnapshot) {
                  final outlook = trajectorySnapshot.data;
                  if (outlook == null || outlook.trajectory.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _PredictionTrajectoryCard(outlook: outlook);
                },
              ),
              FutureBuilder<ModelValidationReport?>(
                future: _validationReportFuture,
                builder: (context, validationSnapshot) {
                  if (!validationSnapshot.hasData) {
                    return const _ValidationReportLoadingCard();
                  }
                  return ModelValidationCard(report: validationSnapshot.data!);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _trendsFuture = _loadTrends(14);
    _validationReportFuture = _loadValidationReport();
    _trajectoryFuture = _loadTrajectoryOutlook();
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

  Future<ModelValidationReport?> _loadValidationReport() async {
    try {
      final report = await InsightsApi.fetchValidationReport();
      await AnalyticsService.track(
        'model_validation_report_loaded',
        properties: {
          'row_count': report.rowCount,
          'study_ready': report.readiness.studyReady,
        },
      );
      return report;
    } catch (_) {
      await AnalyticsService.track('model_validation_report_failed');
      return null;
    }
  }

  Future<TomorrowOutlook?> _loadTrajectoryOutlook() async {
    final outlook = await MLPredictionService.loadTrajectoryOutlook(
      date: DateTime.now().toIso8601String(),
    );
    if (outlook != null) {
      await AnalyticsService.track(
        'insights_trajectory_loaded',
        properties: {
          'point_count': outlook.trajectory.length,
          'confidence': outlook.confidence,
        },
      );
    }
    return outlook;
  }

  Future<void> _syncWhoopMetrics() async {
    setState(() {
      _isSyncingWhoop = true;
      _whoopSyncMessage = null;
    });
    try {
      final result = await WhoopService.syncDailyMetrics(days: 30);
      await AnalyticsService.track(
        'whoop_daily_metrics_sync_requested',
        properties: {
          'fetched': result.fetched,
          'saved': result.saved,
          'durable_saved': result.durableSaved,
        },
      );
      setState(() {
        _whoopSyncMessage =
            result.detail ??
            'Synced ${result.saved} biometric day${result.saved == 1 ? '' : 's'}.';
        _trendsFuture = _loadTrends(14);
        _validationReportFuture = _loadValidationReport();
        _trajectoryFuture = _loadTrajectoryOutlook();
      });
    } catch (error) {
      await AnalyticsService.track('whoop_daily_metrics_sync_failed');
      setState(() {
        _whoopSyncMessage = 'WHOOP sync failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingWhoop = false;
        });
      }
    }
  }

  String _stateForMood(double mood, double slope) {
    if (mood >= 0.25 && slope >= -0.03) return 'Stable Positive';
    if (mood <= -0.25 && slope <= 0.03) return 'Low';
    if (slope > 0.05) return 'Improving';
    if (slope < -0.05) return 'Declining';
    return 'Stable';
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
      final signalStrength = _signalStrength(
        days: days,
        bodyDays: bodyDays,
        avgVolatility: avgVolatility,
      );

      return _WindowSummary(
        days: days,
        unlocked: true,
        direction: delta == null
            ? _moodLabel(latest.mood)
            : _directionLabel(delta),
        delta: delta,
        volatility: avgVolatility,
        dataUsed: bodyDays > 0 ? 'Journal + body' : 'Journal',
        signalStrength: signalStrength,
        state: latest.state,
        daysNeeded: 0,
      );
    }).toList();
  }

  bool _hasBodySignals(List<InsightTrend> trends) {
    return trends.any((trend) => trend.hrv != null || trend.sleepVar != null);
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
  final String state;
  final int daysNeeded;

  const _WindowSummary({
    required this.days,
    required this.unlocked,
    required this.direction,
    required this.delta,
    required this.volatility,
    required this.dataUsed,
    required this.signalStrength,
    required this.state,
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
      state: 'Unknown',
      daysNeeded: daysNeeded,
    );
  }

  String get label => '${days}d';
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

class _WhoopSyncCard extends StatelessWidget {
  final bool isSyncing;
  final String? message;
  final VoidCallback onSync;

  const _WhoopSyncCard({
    required this.isSyncing,
    required this.message,
    required this.onSync,
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
                const Icon(Icons.favorite_outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Biometric model signals',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isSyncing ? null : onSync,
                  icon: isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: const Text('Sync'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Pulls recent WHOOP sleep, HRV, recovery, resting heart rate, and strain into the trajectory model.',
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: const TextStyle(fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _PredictionTrajectoryCard extends StatelessWidget {
  final TomorrowOutlook outlook;

  const _PredictionTrajectoryCard({required this.outlook});

  @override
  Widget build(BuildContext context) {
    final summary = outlook.trajectorySummary;
    final coverage = outlook.modalityCoverage;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, color: outlook.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Prediction trajectory',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text('${(outlook.confidence * 100).round()}%'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(outlook.trajectoryLabel),
            if (summary != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SignalChip(
                    label: 'Trend/day',
                    value: summary.trendPerDay?.toStringAsFixed(2) ?? 'N/A',
                  ),
                  _SignalChip(
                    label: 'Volatility',
                    value: summary.volatility?.toStringAsFixed(2) ?? 'N/A',
                  ),
                  _SignalChip(
                    label: 'Body adj.',
                    value:
                        summary.biometricAdjustment?.toStringAsFixed(2) ??
                        'N/A',
                  ),
                  _SignalChip(
                    label: 'Audio adj.',
                    value: summary.audioAdjustment?.toStringAsFixed(2) ?? 'N/A',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: outlook.trajectory.take(4).map((point) {
                return Expanded(
                  child: Column(
                    children: [
                      Text('${point.horizonDays}d'),
                      Text(
                        point.predictedMood.toStringAsFixed(2),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '±${point.uncertainty.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            if (coverage != null) ...[
              const SizedBox(height: 10),
              Text(
                'Signals used: ${coverage.availableModalities.isEmpty ? 'limited' : coverage.availableModalities.join(', ')}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  final String label;
  final String value;

  const _SignalChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class ModelValidationCard extends StatelessWidget {
  final ModelValidationReport report;

  const ModelValidationCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final readiness = report.readiness;
    final coverage = report.coverage;
    final title = readiness.studyReady
        ? 'Study ready'
        : readiness.multimodalValidationReady
        ? 'Multimodal validation ready'
        : readiness.earlyValidationReady
        ? 'Early validation ready'
        : 'Validation data needed';
    final icon = readiness.studyReady
        ? Icons.verified_outlined
        : readiness.earlyValidationReady
        ? Icons.fact_check_outlined
        : Icons.science_outlined;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ValidationChip(
                  label: 'Daily rows',
                  value: readiness.dailyRows.toString(),
                ),
                _ValidationChip(
                  label: 'Outcome rows',
                  value: readiness.targetRows.toString(),
                ),
                _ValidationChip(
                  label: 'Journal',
                  value: coverage.journalDays.toString(),
                ),
                _ValidationChip(
                  label: 'Audio',
                  value: coverage.audioDays.toString(),
                ),
                _ValidationChip(
                  label: 'Biometric',
                  value: coverage.biometricDays.toString(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (report.horizonMetrics.isNotEmpty)
              _HorizonMetricRow(metrics: report.horizonMetrics),
            if (readiness.blockers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Next data needs',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              ...readiness.blockers
                  .take(3)
                  .map(
                    (blocker) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('- '),
                          Expanded(child: Text(blocker)),
                        ],
                      ),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ValidationReportLoadingCard extends StatelessWidget {
  const _ValidationReportLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading model validation report...'),
          ],
        ),
      ),
    );
  }
}

class _HorizonMetricRow extends StatelessWidget {
  final List<HorizonMetric> metrics;

  const _HorizonMetricRow({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Baseline MAE by horizon',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 6),
        Row(
          children: metrics.take(4).map((metric) {
            return Expanded(
              child: Column(
                children: [
                  Text('${metric.horizonDays}d'),
                  Text(
                    metric.persistenceBaselineMae?.toStringAsFixed(2) ?? 'N/A',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'n=${metric.targetCount}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ValidationChip extends StatelessWidget {
  final String label;
  final String value;

  const _ValidationChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.dataset_outlined, size: 18),
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}
