import 'package:flutter/material.dart';
import '../widgets/mood_trend_chart.dart';
import '../widgets/body_metrics_chart.dart';
import '../widgets/volatility_trend_graph.dart';
import '../widgets/trend_slope_graph.dart';
import '../widgets/state_timeline.dart';
import '../widgets/metrics_dropdown.dart';
import '../models/insight_trend.dart';
import '../services/insight_api.dart';
import '../services/data_service.dart';
import '../services/insights_service.dart';

class InsightsPage extends StatefulWidget {
  final DataService dataService;

  const InsightsPage({super.key, required this.dataService});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  late Future<List<InsightTrend>> _trendsFuture;

  @override
    
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Insights")),
      body: FutureBuilder<List<InsightTrend>>(
        future: _trendsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error loading insights: ${snapshot.error}"));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No insight data yet"));
          }

          final trends = snapshot.data!;
          final latest = trends.last;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MoodTrendGraph(trends: trends),
              VolatilityTrendGraph(trends: trends),
              TrendSlopeGraph(trends: trends),
              BodyMetricsGraph(trends: trends),
              StateTimeline(trends: trends),
              MetricsDropdown(latest: latest),
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
  }

  Future<List<InsightTrend>> _loadTrends(int days) async {
    try {
      return await InsightsApi.fetchTrends(days);
    } catch (_) {
      return _loadLocalTrends(days);
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
    final recentAvg = {
      for (final day in recentDays) day: dailyAvg[day]!,
    };
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

  String _stateForMood(double mood, double slope) {
    if (mood >= 0.25 && slope >= -0.03) return 'Stable Positive';
    if (mood <= -0.25 && slope <= 0.03) return 'Low';
    if (slope > 0.05) return 'Improving';
    if (slope < -0.05) return 'Declining';
    return 'Stable';
  }
}
