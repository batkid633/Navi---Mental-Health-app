import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/evaluation_feedback.dart';
import '../models/sync_status.dart';
import '../services/analytics_service.dart';
import '../services/data_service.dart';

class EvaluationFeedbackCard extends StatefulWidget {
  final DataService dataService;
  final String targetType;
  final String targetDate;
  final String title;
  final String? journalEntryId;
  final double? predictedDelta;
  final double? confidence;
  final String? modelVersion;
  final String? insight;
  final bool showAccuracy;
  final bool showHelpfulness;
  final String accuracyLabel;
  final String helpfulnessLabel;

  const EvaluationFeedbackCard({
    super.key,
    required this.dataService,
    required this.targetType,
    required this.targetDate,
    required this.title,
    this.journalEntryId,
    this.predictedDelta,
    this.confidence,
    this.modelVersion,
    this.insight,
    this.showAccuracy = true,
    this.showHelpfulness = true,
    this.accuracyLabel = 'Accuracy',
    this.helpfulnessLabel = 'Helpful',
  });

  @override
  State<EvaluationFeedbackCard> createState() => _EvaluationFeedbackCardState();
}

class _EvaluationFeedbackCardState extends State<EvaluationFeedbackCard> {
  late Future<Box<EvaluationFeedback>> _feedbackBoxFuture;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _feedbackBoxFuture = widget.dataService.getEvaluationFeedbackBox();
  }

  String get _feedbackId {
    return EvaluationFeedback.canonicalId(widget.targetType, widget.targetDate);
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
          targetType: widget.targetType,
          targetDate: widget.targetDate,
          journalEntryId: widget.journalEntryId,
          predictedDelta: widget.predictedDelta,
          confidence: widget.confidence,
          modelVersion: widget.modelVersion,
          insight: widget.insight,
          createdAt: now,
        );

    feedback.journalEntryId = widget.journalEntryId;
    feedback.predictedDelta = widget.predictedDelta;
    feedback.confidence = widget.confidence;
    feedback.modelVersion = widget.modelVersion;
    feedback.insight = widget.insight;
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
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                    if (widget.showAccuracy) ...[
                      const SizedBox(height: 8),
                      _FeedbackSegmentedControl(
                        label: widget.accuracyLabel,
                        selected: feedback?.accuracyRating,
                        options: const {
                          'accurate': 'Accurate',
                          'close': 'Close',
                          'off': 'Off',
                        },
                        onChanged: (value) => _saveRating(
                          existing: feedback,
                          accuracyRating: value,
                        ),
                      ),
                    ],
                    if (widget.showHelpfulness) ...[
                      const SizedBox(height: 8),
                      _FeedbackSegmentedControl(
                        label: widget.helpfulnessLabel,
                        selected: feedback?.helpfulnessRating,
                        options: const {
                          'helpful': 'Helpful',
                          'neutral': 'Neutral',
                          'unhelpful': 'Unhelpful',
                        },
                        onChanged: (value) => _saveRating(
                          existing: feedback,
                          helpfulnessRating: value,
                        ),
                      ),
                    ],
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
                ),
              ),
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
