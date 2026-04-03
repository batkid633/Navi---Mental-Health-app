import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../models/journal_entry.dart';
import '../models/today_state.dart';
import '../models/baseline_deviation_model.dart';
import '../services/insights_service.dart';
import '../services/today_intelligence_service.dart';
import '../services/ml_prediction_service.dart';
import '../models/tomorrow_outlook.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late Future<TomorrowOutlook?> _outlookFuture;

  @override
  void initState() {
    super.initState();
    _loadOutlook();
  }

  void _loadOutlook({bool force = false}) {
    _outlookFuture = MLPredictionService.loadTomorrowOutlook(
      date: DateTime.now().toIso8601String(),
      force_reload: force,
    );
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<JournalEntry>('journal');
    final dailyAvg = InsightsService.dailyAverageSentiment(box);

    // Guard: not enough data yet
    if (dailyAvg.isEmpty) {
      return const Center(
        child: Text("Not enough data yet."),
      );
    }

    // 2️⃣ Compute metrics

    final rolling7 = InsightsService.rollingAverage(dailyAvg, 7);
    final vol7 = InsightsService.rollingVolatility(dailyAvg, 7);
    final mom7 = InsightsService.rollingMomentum(dailyAvg, 7);

    final volLabel =
        TodayIntelligenceService.volatilityLabel(vol7.values.last);

    final momLabel =
        TodayIntelligenceService.momentumLabel(mom7.values.last);

    // Adding delta calculation
    final delta = InsightsService.dailyDelta(
      today: dailyAvg.values.last,
      rollingAvg: rolling7.values.last,
    );

    final deviation = BaselineDeviationModel.evaluate(
      today: dailyAvg.values.last,
      rollingMean: rolling7.values.last,
      rollingStd: vol7.values.last,
    );

    // 3️⃣ Classify today (variable name must be lowercase)
    final todayMoodTrend = TodayIntelligenceService.classify(
      today: dailyAvg.values.last,
      rollingAvg: rolling7.values.last,
      volatility: vol7.values.last,
      momentum: mom7.values.last,
    );

    // ignore: unused_local_variable
    final todayState = TodayState(date: DateTime.now());

    String insightText;

    if (delta > 0.5) {
      insightText = "You're feeling noticeably better than your recent average.";
    } else if (delta > 0.1) {
      insightText = "You're slightly above your recent average.";
    } else if (delta > -0.1) {
      insightText = "You're about where you usually are.";
    } else if (delta > -0.5) {
      insightText = "You're slightly below your recent average.";
    } else {
      insightText = "You're feeling noticeably worse than your recent average.";
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Today")),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  TodayIntelligenceService.insightText(todayMoodTrend),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Icon(
                  Icons.circle,
                  color: TodayIntelligenceService.stateColor(todayMoodTrend),
                  size: 24,
                ),
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      insightText,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text("Volatility"),
                    subtitle: Text(volLabel),
                    trailing: Icon(
                      Icons.circle,
                      color: TodayIntelligenceService.volatilityColor(vol7.values.last),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text("Momentum"),
                    subtitle: Text(momLabel),
                    trailing: Icon(
                      Icons.arrow_circle_right,
                      color: TodayIntelligenceService.momentumColor(mom7.values.last),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    title: const Text(
                      "Baseline Deviation",
                    ),
                    subtitle: Text(deviation.explanation),
                    trailing: Text(
                      "z-score: ${deviation.zScore.toStringAsFixed(2)}",
                      style: TextStyle(
                        color: deviation.isAnomalous ? Colors.redAccent : Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Place FutureBuilder as a child widget, not a return inside the list.
                FutureBuilder<TomorrowOutlook?>(
                  future: _outlookFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text("Loading...");
                    } else if (snapshot.hasError) {
                      return const Text("Error loading prediction.");
                    } else if (!snapshot.hasData) {
                      return const Text("No data available.");
                    }

                    final outlook = snapshot.data!;
                    return Card(
                      margin: const EdgeInsets.only(top: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              outlook.label,
                              style: TextStyle(
                                color: outlook.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text("Reload Insight"),
                              onPressed: () {
                                setState(() {
                                  _loadOutlook(force: true); // rebuilds FutureBuilder
                                });
                              },
                            ),
                            if (outlook.insight != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                outlook.insight!,
                                style: const TextStyle(fontSize: 13, color: Colors.white),
                              ),
                            ]
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}