import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/journal_entry.dart';
import '../models/evaluation_feedback.dart';
import '../models/sync_status.dart';
import '../models/baseline_deviation_model.dart';
import '../services/insights_service.dart';
import '../services/today_intelligence_service.dart';
import '../services/ml_prediction_service.dart';
import '../models/tomorrow_outlook.dart';
import '../services/analytics_service.dart';
import '../services/data_service.dart';
import '../services/settings_service.dart';

class TodayPage extends StatefulWidget {
  final DataService dataService;

  const TodayPage({super.key, required this.dataService});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late Future<TomorrowOutlook?> _outlookFuture;
  Box<JournalEntry>? journalBox;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _initBox();
    _loadOutlook();
  }

  Future<void> _initBox() async {
    try {
      journalBox = await widget.dataService.getJournalBox();
      _loadError = null;
    } catch (e) {
      _loadError = 'Unable to load Today data right now.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _loadOutlook({bool force = false}) {
    _outlookFuture = MLPredictionService.loadTomorrowOutlook(
      date: DateTime.now().toIso8601String(),
      forceReload: force,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!SettingsService.personalizedInsightsEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Today')),
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

    if (_isLoading || journalBox == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Today')),
        body: _loadError == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 32),
                      const SizedBox(height: 12),
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _loadError = null;
                          });
                          _initBox();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }

    return ValueListenableBuilder<Box<JournalEntry>>(
      valueListenable: journalBox!.listenable(),
      builder: (context, box, _) {
        final dailyAvg = InsightsService.dailyAverageSentiment(box);
        final todayKey = DateTime.now().toIso8601String().substring(0, 10);
        final latestJournalEntryId = _latestEntryIdForDate(box, todayKey);

        // Guard: not enough data yet
        if (dailyAvg.isEmpty) {
          final entryCount = box.values.length;
          return Scaffold(
            appBar: AppBar(title: const Text('Today')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insights, size: 36),
                    const SizedBox(height: 12),
                    Text(
                      entryCount == 0
                          ? 'Not enough data yet.'
                          : 'Sentiment scores are still being prepared.',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entryCount == 0
                          ? 'Add a journal entry to begin tracking your mood.'
                          : 'Your journal entries are saved. If this persists, check backend connectivity in Settings.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // 2️⃣ Compute metrics

        final rolling7 = InsightsService.rollingAverage(dailyAvg, 7);
        final vol7 = InsightsService.rollingVolatility(dailyAvg, 7);
        final mom7 = InsightsService.rollingMomentum(dailyAvg, 7);

        final volLabel = TodayIntelligenceService.volatilityLabel(
          vol7.values.last,
        );

        final momLabel = TodayIntelligenceService.momentumLabel(
          mom7.values.last,
        );

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

        String insightText;

        if (delta > 0.5) {
          insightText =
              "You're feeling noticeably better than your recent average.";
        } else if (delta > 0.1) {
          insightText = "You're slightly above your recent average.";
        } else if (delta > -0.1) {
          insightText = "You're about where you usually are.";
        } else if (delta > -0.5) {
          insightText = "You're slightly below your recent average.";
        } else {
          insightText =
              "You're feeling noticeably worse than your recent average.";
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
                      color: TodayIntelligenceService.stateColor(
                        todayMoodTrend,
                      ),
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
                          color: TodayIntelligenceService.volatilityColor(
                            vol7.values.last,
                          ),
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        title: const Text("Momentum"),
                        subtitle: Text(momLabel),
                        trailing: Icon(
                          Icons.arrow_circle_right,
                          color: TodayIntelligenceService.momentumColor(
                            mom7.values.last,
                          ),
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        title: const Text("Baseline Deviation"),
                        subtitle: Text(deviation.explanation),
                        trailing: Text(
                          "z-score: ${deviation.zScore.toStringAsFixed(2)}",
                          style: TextStyle(
                            color: deviation.isAnomalous
                                ? Colors.redAccent
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Place FutureBuilder as a child widget, not a return inside the list.
                    FutureBuilder<TomorrowOutlook?>(
                      future: _outlookFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
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
                                  outlook.trajectoryLabel,
                                  style: TextStyle(
                                    color: outlook.color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (outlook.trajectory.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _TrajectoryStrip(outlook: outlook),
                                ],
                                if (outlook.modalityCoverage != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Signals: ${_modalityLabel(outlook.modalityCoverage!)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                                if (outlook.validation != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Validation data: ${outlook.validation!.sampleCount} daily rows',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: const Text("Reload Insight"),
                                  onPressed: () {
                                    setState(() {
                                      _loadOutlook(
                                        force: true,
                                      ); // rebuilds FutureBuilder
                                    });
                                  },
                                ),
                                if (outlook.insight != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    outlook.insight!,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                _EvaluationFeedbackControl(
                                  dataService: widget.dataService,
                                  targetDate: todayKey,
                                  journalEntryId: latestJournalEntryId,
                                  outlook: outlook,
                                ),
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
      },
    );
  }

  String? _latestEntryIdForDate(Box<JournalEntry> box, String dateKey) {
    final entriesForDay = box.values.where((entry) {
      return entry.date.toIso8601String().substring(0, 10) == dateKey;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));
    return entriesForDay.isEmpty ? null : entriesForDay.first.id;
  }

  String _modalityLabel(ModalityCoverage coverage) {
    if (coverage.availableModalities.isEmpty) {
      return 'limited';
    }
    return coverage.availableModalities
        .map((item) => item[0].toUpperCase() + item.substring(1))
        .join(', ');
  }
}

class _TrajectoryStrip extends StatelessWidget {
  final TomorrowOutlook outlook;

  const _TrajectoryStrip({required this.outlook});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: outlook.trajectory.take(4).map((point) {
        final positive = point.predictedDelta > 0.05;
        final negative = point.predictedDelta < -0.05;
        final color = positive
            ? Colors.greenAccent
            : negative
            ? Colors.orangeAccent
            : Colors.white70;
        return Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${point.horizonDays}d',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
              const SizedBox(height: 2),
              Text(
                point.predictedMood.toStringAsFixed(2),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                '${(point.confidence * 100).round()}%',
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _EvaluationFeedbackControl extends StatefulWidget {
  final DataService dataService;
  final String targetDate;
  final String? journalEntryId;
  final TomorrowOutlook outlook;

  const _EvaluationFeedbackControl({
    required this.dataService,
    required this.targetDate,
    required this.journalEntryId,
    required this.outlook,
  });

  @override
  State<_EvaluationFeedbackControl> createState() =>
      _EvaluationFeedbackControlState();
}

class _EvaluationFeedbackControlState
    extends State<_EvaluationFeedbackControl> {
  late Future<Box<EvaluationFeedback>> _feedbackBoxFuture;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _feedbackBoxFuture = widget.dataService.getEvaluationFeedbackBox();
  }

  String get _feedbackId {
    return EvaluationFeedback.canonicalId(
      'tomorrow_prediction',
      widget.targetDate,
    );
  }

  Future<void> _saveRating({
    required EvaluationFeedback? existing,
    String? accuracyRating,
    String? helpfulnessRating,
  }) async {
    final now = DateTime.now();
    final feedback =
        existing ??
        EvaluationFeedback(
          id: _feedbackId,
          targetType: 'tomorrow_prediction',
          targetDate: widget.targetDate,
          journalEntryId: widget.journalEntryId,
          predictedDelta: widget.outlook.predictedDelta,
          confidence: widget.outlook.confidence,
          modelVersion: widget.outlook.modelVersion,
          insight: widget.outlook.insight,
          createdAt: now,
        );

    feedback.journalEntryId = widget.journalEntryId;
    feedback.predictedDelta = widget.outlook.predictedDelta;
    feedback.confidence = widget.outlook.confidence;
    feedback.modelVersion = widget.outlook.modelVersion;
    feedback.insight = widget.outlook.insight;
    feedback.updatedAt = now;

    if (accuracyRating != null) {
      feedback.accuracyRating = accuracyRating;
    }
    if (helpfulnessRating != null) {
      feedback.helpfulnessRating = helpfulnessRating;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await widget.dataService.saveEvaluationFeedback(feedback);
      await AnalyticsService.track(
        'evaluation_feedback_saved',
        properties: {
          'target_type': feedback.targetType,
          'accuracy': feedback.accuracyRating,
          'helpfulness': feedback.helpfulnessRating,
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Box<EvaluationFeedback>>(
      future: _feedbackBoxFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<Box<EvaluationFeedback>>(
          valueListenable: snapshot.data!.listenable(),
          builder: (context, box, _) {
            final feedback = box.get(_feedbackId);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Evaluate this prediction',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_isSaving)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                _FeedbackSegmentedControl(
                  label: 'Accuracy',
                  selected: feedback?.accuracyRating,
                  options: const {
                    'accurate': 'Accurate',
                    'close': 'Close',
                    'off': 'Off',
                  },
                  onChanged: (value) =>
                      _saveRating(existing: feedback, accuracyRating: value),
                ),
                const SizedBox(height: 8),
                _FeedbackSegmentedControl(
                  label: 'Helpful',
                  selected: feedback?.helpfulnessRating,
                  options: const {
                    'helpful': 'Helpful',
                    'neutral': 'Neutral',
                    'unhelpful': 'Unhelpful',
                  },
                  onChanged: (value) =>
                      _saveRating(existing: feedback, helpfulnessRating: value),
                ),
                if (feedback?.syncStatus == SyncStatus.failed &&
                    feedback?.lastSyncError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Feedback saved locally. Sync will retry.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _FeedbackSegmentedControl extends StatelessWidget {
  final String label;
  final String? selected;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _FeedbackSegmentedControl({
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          segments: [
            for (final option in options.entries)
              ButtonSegment(value: option.key, label: Text(option.value)),
          ],
          selected: selected == null ? <String>{} : {selected!},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onChanged(selection.first);
            }
          },
        ),
      ],
    );
  }
}
