import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/journal_entry.dart';
import '../models/sync_status.dart';
import '../pages/journal_detail_page.dart';
import '../services/analytics_service.dart';
import '../services/data_service.dart';
import '../services/keyboard_tracking_service.dart';
import '../services/ml_export_services.dart';
import '../services/sentiment_service.dart';

class JournalPage extends StatefulWidget {
  final DataService dataService;

  const JournalPage({super.key, required this.dataService});

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _error;
  String? _saveMessage;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _journalFocus = FocusNode();
  final DateFormat _dateFormat = DateFormat('MMM d, yyyy h:mm a');
  final Uuid _uuid = const Uuid();
  KeyboardTextControllerTracker? _keyboardTracker;
  Box<JournalEntry>? journalBox;

  @override
  void initState() {
    super.initState();
    _keyboardTracker = KeyboardTrackingService(dataService: widget.dataService)
        .attachTextController(
          controller: _controller,
          fieldContext: 'journal_entry',
        );
    _initBox();
  }

  Future<void> _initBox() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _saveMessage = null;
    });

    try {
      journalBox = await widget.dataService.getJournalBox();
      try {
        await widget.dataService
            .refreshJournalEntriesFromCloud(journalBox!)
            .timeout(const Duration(seconds: 12));
      } catch (e) {
        debugPrint('Journal foreground cloud refresh skipped: $e');
      }
      await AnalyticsService.track(
        'journal_loaded',
        properties: {'entry_count': journalBox?.length ?? 0},
      );
    } catch (e) {
      await AnalyticsService.track('journal_load_failed');
      _error = 'Unable to load your journal right now.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_keyboardTracker?.dispose());
    _controller.dispose();
    _journalFocus.dispose();
    super.dispose();
  }

  Future<void> _addEntry() async {
    final text = _controller.text.trim();
    if (text.isEmpty || journalBox == null) return;

    _journalFocus.unfocus();

    setState(() {
      _isLoading = true;
      _error = null;
      _saveMessage = null;
    });

    try {
      await AnalyticsService.track('journal_save_attempted');
      final sentiment = await SentimentService.analyze(text);
      final now = DateTime.now();
      final entry = JournalEntry(
        id: 'journal_${_uuid.v4()}',
        date: now,
        text: text,
        sentimentScore: (sentiment["compound"] as num).toDouble(),
        sentimentLabel: sentiment["label"] as String,
        sentimentSource: sentiment["source"]?.toString(),
        sentimentFallbackReason: sentiment["fallbackReason"]?.toString(),
      );

      await journalBox!.put(entry.id, entry);
      await AnalyticsService.track('journal_saved_locally');
      await _keyboardTracker?.flush();
      _controller.clear();
      _keyboardTracker?.resetBaseline();
      setState(() {
        _saveMessage = _saveMessageForSentiment(entry);
      });

      unawaited(_syncAfterLocalSave(entry));
    } catch (e) {
      await AnalyticsService.track('journal_save_failed');
      setState(() {
        _error = 'Failed to save journal entry.';
        _saveMessage = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _syncAfterLocalSave(JournalEntry entry) async {
    if (mounted) {
      setState(() {
        _isSyncing = true;
      });
    }

    try {
      await widget.dataService
          .syncJournalEntryToCloud(entry)
          .timeout(const Duration(seconds: 10));
      await AnalyticsService.track(
        'journal_cloud_sync_finished',
        properties: {'sync_status': entry.syncStatus},
      );
    } catch (e) {
      await AnalyticsService.track('journal_cloud_sync_timeout');
      debugPrint('Journal cloud sync skipped after local save: $e');
    }

    final currentBox = journalBox;
    if (currentBox == null) return;

    try {
      await widget.dataService
          .syncJournalFeaturesToBackend(currentBox)
          .timeout(const Duration(seconds: 10));
      await AnalyticsService.track('journal_features_sync_finished');
    } catch (e) {
      await AnalyticsService.track('journal_features_sync_failed');
      debugPrint('Journal feature sync skipped after local save: $e');
    }

    try {
      final filePath = await MLExportService.exportDailyFeatures(
        currentBox,
      ).timeout(const Duration(seconds: 10));
      debugPrint('ML export saved to: $filePath');
    } catch (e) {
      debugPrint('ML export skipped after local save: $e');
    }

    if (!mounted) return;
    setState(() {
      _isSyncing = false;
      _saveMessage = entry.syncStatus == SyncStatus.synced
          ? 'Saved and synced.'
          : entry.syncStatus == SyncStatus.failed
          ? 'Saved locally. Cloud sync will retry when available.'
          : 'Saved locally. Waiting to sync.';
    });
  }

  Future<void> _retryPendingSync(List<JournalEntry> entries) async {
    if (journalBox == null) return;
    setState(() {
      _isSyncing = true;
      _error = null;
      _saveMessage = 'Retrying journal sync...';
    });

    for (final entry in entries.where((entry) {
      return SyncStatus.canRetry(entry.syncStatus);
    })) {
      await widget.dataService.syncJournalEntryToCloud(entry);
    }
    await AnalyticsService.track(
      'journal_sync_retry_finished',
      properties: {'entry_count': entries.length},
    );

    if (!mounted) return;
    setState(() {
      _isSyncing = false;
      _saveMessage = 'Sync retry finished.';
    });
  }

  Color _sentimentColor(String label) {
    switch (label.toLowerCase()) {
      case 'positive':
        return Colors.green.shade600;
      case 'negative':
        return Colors.red.shade600;
      case 'neutral':
      default:
        return Colors.blueGrey.shade500;
    }
  }

  String _saveMessageForSentiment(JournalEntry entry) {
    if (entry.sentimentSource == 'local_fallback') {
      return 'Saved locally. Sentiment analyzed on this device for privacy.';
    }
    return 'Saved locally. Sentiment analyzed by backend. Syncing in the background...';
  }

  String _sentimentTooltip(JournalEntry entry) {
    final score = entry.sentimentScore?.toStringAsFixed(3) ?? 'unknown';
    if (entry.sentimentSource == 'local_fallback') {
      final reason = entry.sentimentFallbackReason ?? 'unknown reason';
      return 'Sentiment: ${entry.sentimentLabel} ($score). Local fallback used: $reason';
    }
    final source = entry.sentimentSource ?? 'unknown source';
    return 'Sentiment: ${entry.sentimentLabel} ($score). Source: $source';
  }

  String _sentimentChipLabel(JournalEntry entry) {
    final label = entry.sentimentLabel ?? 'unknown';
    if (entry.sentimentSource == 'local_fallback') {
      return '$label local';
    }
    return label;
  }

  Color _syncStatusColor(String status) {
    switch (status) {
      case SyncStatus.synced:
        return Colors.green.shade700;
      case SyncStatus.failed:
        return Colors.red.shade700;
      case SyncStatus.pending:
      default:
        return Colors.orange.shade700;
    }
  }

  IconData _syncStatusIcon(String status) {
    switch (status) {
      case SyncStatus.synced:
        return Icons.cloud_done;
      case SyncStatus.failed:
        return Icons.cloud_off;
      case SyncStatus.pending:
      default:
        return Icons.cloud_upload;
    }
  }

  String _syncStatusLabel(String status) {
    switch (status) {
      case SyncStatus.synced:
        return 'Synced';
      case SyncStatus.failed:
        return 'Sync failed';
      case SyncStatus.pending:
      default:
        return 'Pending sync';
    }
  }

  Widget _statusMessage() {
    final message = _error ?? _saveMessage;
    if (message == null) return const SizedBox.shrink();
    final isError = _error != null;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isError
              ? colorScheme.errorContainer.withValues(alpha: 0.5)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? colorScheme.error : colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _syncSummary(List<JournalEntry> entries) {
    final pending = entries
        .where((entry) => entry.syncStatus == SyncStatus.pending)
        .length;
    final failed = entries
        .where((entry) => entry.syncStatus == SyncStatus.failed)
        .length;
    if (pending == 0 && failed == 0 && !_isSyncing) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final hasFailed = failed > 0;
    final label = hasFailed
        ? '$failed failed, $pending pending'
        : _isSyncing
        ? 'Syncing journal entries...'
        : '$pending waiting to sync';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: hasFailed
            ? colorScheme.errorContainer.withValues(alpha: 0.45)
            : colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          leading: _isSyncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  hasFailed ? Icons.cloud_off : Icons.cloud_upload,
                  color: hasFailed ? colorScheme.error : colorScheme.primary,
                ),
          title: Text(label),
          subtitle: Text(
            hasFailed
                ? 'Your entries are safe on this device. Sync will retry automatically.'
                : 'Your entries are saved locally while cloud sync completes.',
          ),
          trailing: hasFailed
              ? TextButton(
                  onPressed: _isSyncing
                      ? null
                      : () => _retryPendingSync(entries),
                  child: const Text('Retry'),
                )
              : null,
        ),
      ),
    );
  }

  Widget _journalBody() {
    if (_isLoading && journalBox == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (journalBox == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 32),
              const SizedBox(height: 12),
              Text(
                _error ?? 'Unable to open journal storage.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _initBox,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    return ValueListenableBuilder<Box<JournalEntry>>(
      valueListenable: journalBox!.listenable(),
      builder: (context, box, _) {
        final entries = box.values.toList()
          ..sort((a, b) => b.date.compareTo(a.date));

        if (entries.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note, size: 36),
                  SizedBox(height: 12),
                  Text(
                    'No journal entries yet.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Write a few thoughts above to start building your local history.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            _syncSummary(entries),
            Expanded(
              child: ListView.builder(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];

                  return ListTile(
                    title: Text(
                      entry.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_dateFormat.format(entry.date)),
                        if (entry.lastSyncError != null)
                          Text(
                            'Last sync error: ${entry.lastSyncError}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        Tooltip(
                          message: _syncStatusLabel(entry.syncStatus),
                          child: Chip(
                            avatar: Icon(
                              _syncStatusIcon(entry.syncStatus),
                              color: Colors.white,
                              size: 18,
                            ),
                            label: Text(
                              _syncStatusLabel(entry.syncStatus),
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: _syncStatusColor(entry.syncStatus),
                          ),
                        ),
                        if (entry.sentimentLabel != null)
                          Tooltip(
                            message: _sentimentTooltip(entry),
                            child: Chip(
                              avatar: entry.sentimentSource == 'local_fallback'
                                  ? const Icon(
                                      Icons.warning_amber,
                                      color: Colors.white,
                                      size: 18,
                                    )
                                  : null,
                              label: Text(
                                _sentimentChipLabel(entry),
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: _sentimentColor(
                                entry.sentimentLabel!,
                              ),
                            ),
                          ),
                      ],
                    ),
                    onTap: () {
                      _journalFocus.unfocus();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => JournalDetailPage(
                            entryId: entry.id,
                            journalBox: journalBox!,
                            dataService: widget.dataService,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // NaviHome already resizes around the keyboard; avoid resizing twice.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Journal'),
        actions: [
          IconButton(
            tooltip: 'Hide keyboard',
            onPressed: _journalFocus.unfocus,
            icon: const Icon(Icons.keyboard_hide),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _controller,
              focusNode: _journalFocus,
              onTapOutside: (_) => _journalFocus.unfocus(),
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: 'Write your thoughts...',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          _statusMessage(),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: (_isLoading || journalBox == null) ? null : _addEntry,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Entry'),
          ),
          const Divider(),
          Expanded(child: _journalBody()),
        ],
      ),
    );
  }
}
