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
    _trendsFuture = InsightsApi.fetchTrends(14);
  }
}