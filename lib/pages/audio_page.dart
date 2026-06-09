import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import '../models/audio_entry.dart';
import '../models/sync_status.dart';
import '../services/analytics_service.dart';
import '../services/audio_analysis_service.dart';
import '../services/data_service.dart';
import '../widgets/evaluation_feedback_card.dart';
import '../utils/file_io.dart'
    if (dart.library.html) '../utils/file_io_web.dart';
import '../utils/recording_path.dart'
    if (dart.library.html) '../utils/recording_path_web.dart';

class AudioPage extends StatefulWidget {
  final DataService dataService;

  const AudioPage({super.key, required this.dataService});

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends State<AudioPage> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  int _recordingDuration = 0;
  final Uuid _uuid = const Uuid();

  // Mode selection
  String _selectedMode =
      'emotional_venting'; // 'emotional_venting' or 'deeper_analysis'
  bool _trainingMode = false;
  String _selectedMoodLabel = 'neutral';

  // Recording state for deeper analysis
  bool _isCalibrationPhase = false;
  bool _isGuidedPhase = false;
  String _currentInstruction = '';

  // Analysis state
  bool _isAnalyzing = false;
  bool _isSyncing = false;
  Map<String, dynamic>? _lastAnalysis;
  AudioEntry? _lastAnalysisEntry;
  String? _boxLoadError;

  Box<AudioEntry>? audioBox;

  @override
  void initState() {
    super.initState();
    _initBox();
  }

  Future<void> _initBox() async {
    try {
      audioBox = await widget.dataService.getAudioBox();
      await AnalyticsService.track(
        'audio_loaded',
        properties: {'entry_count': audioBox?.length ?? 0},
      );
      _boxLoadError = null;
    } catch (e) {
      await AnalyticsService.track('audio_load_failed');
      _boxLoadError = 'Unable to load audio storage right now.';
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _startRecording() async {
    if (audioBox == null) {
      _showSnackBar(
        'Preparing audio storage. Please wait a moment and try again.',
      );
      return;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        await AnalyticsService.track(
          'audio_recording_started',
          properties: {'mode': _selectedMode, 'training_mode': _trainingMode},
        );
        final path = await getRecordingPath(_uuid);

        if (_selectedMode == 'deeper_analysis') {
          // Start with calibration phase
          setState(() {
            _isCalibrationPhase = true;
            _currentInstruction =
                'Please read this calibration sentence clearly:\n\n"The quick brown fox jumps over the lazy dog."';
          });

          // Wait for user to read calibration sentence (5 seconds)
          await Future.delayed(const Duration(seconds: 5));

          setState(() {
            _isCalibrationPhase = false;
            _isGuidedPhase = true;
            _currentInstruction =
                'Now, please speak naturally about how you\'re feeling today for the next 30 seconds.';
          });
        }

        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: path,
        );

        setState(() {
          _isRecording = true;
          _recordingDuration = 0;
        });

        // Start duration counter
        _startDurationTimer();

        // For deeper analysis, auto-stop after guided period
        if (_selectedMode == 'deeper_analysis') {
          Future.delayed(const Duration(seconds: 35), () {
            if (_isRecording) {
              _stopRecording();
            }
          });
        }
      } else {
        await AnalyticsService.track('audio_permission_denied');
        _showSnackBar('Microphone permission denied');
      }
    } catch (e) {
      await AnalyticsService.track('audio_recording_start_failed');
      _showSnackBar('Failed to start recording: $e');
    }
  }

  void _startDurationTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (_isRecording) {
        setState(() {
          _recordingDuration++;
        });
        _startDurationTimer();
      }
    });
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (path != null && audioBox != null) {
        final fileName = _fileNameFromPath(path);
        final now = DateTime.now();
        // Save to Hive
        final audioEntry = AudioEntry(
          id: 'audio_${_uuid.v4()}',
          date: now,
          filePath: path,
          fileName: fileName,
          duration: _recordingDuration,
          mode: _selectedMode,
          moodLabel: _trainingMode ? _selectedMoodLabel : null,
          isTraining: _trainingMode,
        );

        await audioBox!.put(audioEntry.id, audioEntry);
        await AnalyticsService.track(
          'audio_saved_locally',
          properties: {
            'duration_seconds': _recordingDuration,
            'mode': _selectedMode,
            'training_mode': _trainingMode,
          },
        );
        setState(() {
          _isSyncing = true;
        });
        await widget.dataService.syncAudioEntryToCloud(audioEntry);
        await AnalyticsService.track(
          'audio_cloud_sync_finished',
          properties: {'sync_status': audioEntry.syncStatus},
        );
        setState(() {
          _isSyncing = false;
        });

        if (_selectedMode == 'emotional_venting') {
          _showSnackBar(
            'Emotional venting session saved! Duration: ${_formatDuration(_recordingDuration)}',
          );
          _showEmotionalIntervention();
        } else {
          _showSnackBar(
            'Deep analysis session saved! Duration: ${_formatDuration(_recordingDuration)}',
          );
        }
      } else if (path == null) {
        await AnalyticsService.track('audio_recording_empty');
        _showSnackBar('No recording was captured. Please try again.');
      }
    } catch (e) {
      await AnalyticsService.track('audio_recording_save_failed');
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
      _showSnackBar('Failed to save recording: $e');
    }

    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
      _isCalibrationPhase = false;
      _isGuidedPhase = false;
      _currentInstruction = '';
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _fileNameFromPath(String path) {
    final uri = Uri.tryParse(path);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : path.split('/').last;
    if (lastSegment.trim().isEmpty || path.startsWith('blob:')) {
      return 'web-recording-${DateTime.now().millisecondsSinceEpoch}.wav';
    }
    return lastSegment;
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

  Future<void> _retryPendingSync(List<AudioEntry> entries) async {
    setState(() {
      _isSyncing = true;
    });
    for (final entry in entries.where((entry) {
      return SyncStatus.canRetry(entry.syncStatus);
    })) {
      await widget.dataService.syncAudioEntryToCloud(entry);
    }
    await AnalyticsService.track(
      'audio_sync_retry_finished',
      properties: {'entry_count': entries.length},
    );
    if (!mounted) return;
    setState(() {
      _isSyncing = false;
    });
    _showSnackBar('Audio sync retry finished');
  }

  Widget _syncSummary(List<AudioEntry> entries) {
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
        ? 'Syncing audio entries...'
        : '$pending waiting to sync';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                ? 'Recordings are safe on this device. Sync will retry automatically.'
                : 'Recordings are saved locally while cloud sync completes.',
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

  String _audioModelStatusLabel(Map<String, dynamic> moodAnalysis) {
    final status = moodAnalysis['model_status']?.toString();
    final personalized = moodAnalysis['personalized'] == true;
    if (personalized) return 'Personalized audio model';
    if (status == 'global_model') return 'Global audio model';
    if (status == 'heuristic_fallback') return 'Heuristic fallback';
    if (status == 'unavailable') return 'Unavailable';
    return 'Exploratory audio model';
  }

  double? _doubleFromAnalysis(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showEmotionalIntervention() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emotional Support'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Thank you for sharing. Here are some gentle suggestions to help you process your emotions:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text('• Take a few deep breaths'),
            Text('• Write down one thing you\'re grateful for'),
            Text('• Consider talking to a trusted friend'),
            Text('• Remember that emotions are temporary'),
            SizedBox(height: 12),
            Text(
              'You\'re not alone in this. Your feelings are valid.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeAudio(AudioEntry audioEntry) async {
    setState(() {
      _isAnalyzing = true;
      _lastAnalysisEntry = audioEntry;
    });

    try {
      await AnalyticsService.track(
        'audio_analysis_started',
        properties: {'mode': audioEntry.mode},
      );
      final file = kIsWeb ? audioEntry.filePath : getFile(audioEntry.filePath);
      final analysis = await AudioAnalysisService.analyzeAudio(
        file,
        mode: audioEntry.mode,
      );

      setState(() {
        _lastAnalysis = analysis;
        _isAnalyzing = false;
      });

      if (analysis.containsKey('error')) {
        await AnalyticsService.track(
          'audio_analysis_failed',
          properties: {'mode': audioEntry.mode},
        );
        _showSnackBar('Analysis failed: ${analysis['error']}');
      } else {
        final moodAnalysis = analysis['mood_analysis'] as Map<String, dynamic>?;
        final predictedMood = moodAnalysis?['predicted_mood']?.toString();
        if (predictedMood != null && predictedMood.trim().isNotEmpty) {
          audioEntry.moodLabel = predictedMood.trim().toLowerCase();
          await audioEntry.save();
          await widget.dataService.syncAudioEntryToCloud(audioEntry);
          final journalBox = await widget.dataService.getJournalBox();
          await widget.dataService.syncJournalFeaturesToBackend(journalBox);
        }
        await AnalyticsService.track(
          'audio_analysis_succeeded',
          properties: {
            'mode': audioEntry.mode,
            'model_status': moodAnalysis?['model_status']?.toString(),
            'personalized': moodAnalysis?['personalized'] == true,
          },
        );
        _showSnackBar('Audio analyzed successfully!');
      }
    } catch (e) {
      await AnalyticsService.track(
        'audio_analysis_failed',
        properties: {'mode': audioEntry.mode},
      );
      setState(() {
        _isAnalyzing = false;
      });
      _showSnackBar('Analysis error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (audioBox == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Audio Logs'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: _boxLoadError == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 32),
                      const SizedBox(height: 12),
                      Text(_boxLoadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _initBox,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Logs'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      bottomNavigationBar: _isRecording
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.fiber_manual_record, color: Colors.red.shade400),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Recording ${_formatDuration(_recordingDuration)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          // Mode Selection
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Audio Capture Mode',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'emotional_venting',
                      label: Text('Emotional Venting'),
                      icon: Icon(Icons.psychology),
                    ),
                    ButtonSegment(
                      value: 'deeper_analysis',
                      label: Text('Deep Analysis'),
                      icon: Icon(Icons.analytics),
                    ),
                  ],
                  selected: {_selectedMode},
                  onSelectionChanged: (Set<String> selection) {
                    setState(() {
                      _selectedMode = selection.first;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedMode == 'emotional_venting'
                      ? 'Free-form emotional expression with supportive intervention afterwards.'
                      : 'Structured analysis with calibration and guided speech for detailed MFCC processing.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Training mode',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Switch(
                      value: _trainingMode,
                      onChanged: (value) {
                        setState(() {
                          _trainingMode = value;
                        });
                      },
                    ),
                  ],
                ),
                if (_trainingMode) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Select mood label',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        [
                          'neutral',
                          'happy',
                          'sad',
                          'angry',
                          'calm',
                          'anxious',
                        ].map((option) {
                          final selected = option == _selectedMoodLabel;
                          return ChoiceChip(
                            label: Text(
                              option[0].toUpperCase() + option.substring(1),
                            ),
                            selected: selected,
                            onSelected: (_) {
                              setState(() {
                                _selectedMoodLabel = option;
                              });
                            },
                          );
                        }).toList(),
                  ),
                ],
              ],
            ),
          ),

          // Instructions for deeper analysis
          if (_selectedMode == 'deeper_analysis' &&
              (_isCalibrationPhase || _isGuidedPhase))
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                _currentInstruction,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Recording Controls
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  _isRecording
                      ? (_selectedMode == 'deeper_analysis'
                            ? (_isCalibrationPhase
                                  ? 'Calibration Phase'
                                  : 'Guided Speech')
                            : 'Recording...')
                      : 'Ready to Record',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _isRecording ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(height: 10),
                if (_isRecording)
                  Text(
                    _formatDuration(_recordingDuration),
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(
                    _isRecording ? 'Stop Recording' : 'Start Recording',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 15,
                    ),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
                if (kIsWeb)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Chrome may ask for microphone permission. Web recordings are kept as browser blob URLs for this test session.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.yellowAccent),
                    ),
                  ),
              ],
            ),
          ),

          // Analysis Results
          if (_isAnalyzing)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Analyzing audio...', style: TextStyle(fontSize: 16)),
                ],
              ),
            )
          else if (_lastAnalysis != null &&
              !_lastAnalysis!.containsKey('error'))
            Builder(
              builder: (context) {
                final mode =
                    _lastAnalysis!['mode'] as String? ?? 'emotional_venting';
                final moodAnalysis =
                    _lastAnalysis!['mood_analysis'] as Map<String, dynamic>?;
                final audioFeatures =
                    _lastAnalysis!['audio_features'] as Map<String, dynamic>?;
                final intervention =
                    _lastAnalysis!['intervention'] as Map<String, dynamic>?;
                final mfccAnalysis =
                    _lastAnalysis!['mfcc_analysis'] as Map<String, dynamic>?;
                final analysisEntry = _lastAnalysisEntry;

                String formatNumber(dynamic value, {int digits = 1}) {
                  if (value == null) return 'N/A';
                  if (value is num) return value.toStringAsFixed(digits);
                  if (value is String) {
                    final parsed = double.tryParse(value);
                    return parsed != null
                        ? parsed.toStringAsFixed(digits)
                        : value;
                  }
                  return value.toString();
                }

                return Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last Analysis Results',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Mode: ${mode == 'emotional_venting' ? 'Emotional Venting' : 'Deep Analysis'}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (moodAnalysis != null) ...[
                        Text(
                          'Predicted Mood: ${moodAnalysis['predicted_mood'] ?? 'Unknown'}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          'Model: ${_audioModelStatusLabel(moodAnalysis)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                        if (moodAnalysis['confidence'] != null)
                          Text(
                            'Confidence: ${formatNumber((moodAnalysis['confidence'] as num?) ?? 0, digits: 1)}%',
                            style: const TextStyle(fontSize: 16),
                          ),
                        if (moodAnalysis['note'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              moodAnalysis['note'].toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                      if (audioFeatures != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Duration: ${formatNumber(audioFeatures['duration_seconds'])}s',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          'Tempo: ${formatNumber(audioFeatures['tempo_bpm'])} BPM',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                      if (intervention != null &&
                          intervention['suggestions'] is List) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Support Suggestions:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...((intervention['suggestions'] as List)
                                .cast<dynamic>())
                            .map(
                              (suggestion) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  '• $suggestion',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ),
                      ],
                      if (mfccAnalysis != null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Deep MFCC Analysis:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Spectral Centroid: ${formatNumber(mfccAnalysis['spectral_features']?['centroid_mean'], digits: 2)} Hz',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          'Tempo: ${formatNumber(mfccAnalysis['rhythm_features']?['tempo'])} BPM',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                      if (analysisEntry != null) ...[
                        const SizedBox(height: 12),
                        EvaluationFeedbackCard(
                          dataService: widget.dataService,
                          targetType: 'audio_analysis',
                          targetDate: analysisEntry.id,
                          title: 'Rate audio analysis',
                          journalEntryId: null,
                          confidence: _doubleFromAnalysis(
                            moodAnalysis?['confidence'],
                          ),
                          modelVersion: moodAnalysis?['model_status']
                              ?.toString(),
                          insight:
                              'predicted_mood:${moodAnalysis?['predicted_mood'] ?? 'unknown'}',
                          accuracyLabel: 'Audio accuracy',
                          helpfulnessLabel: 'Analysis usefulness',
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

          // Recordings List
          SizedBox(
            height: 360,
            child: ValueListenableBuilder(
              valueListenable: audioBox!.listenable(),
              builder: (context, Box<AudioEntry> box, _) {
                if (box.values.isEmpty) {
                  return const Center(
                    child: Text(
                      'No audio recordings yet.\nTap the mic to start recording!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                final entries = box.values.toList()
                  ..sort((a, b) => b.date.compareTo(a.date));
                return ListView.builder(
                  itemCount: entries.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _syncSummary(entries);
                    }
                    final audioEntry = entries[index - 1];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.audiotrack,
                          color: Colors.blue,
                        ),
                        title: Text(audioEntry.fileName),
                        subtitle: Text(
                          '${audioEntry.date.toString().split(' ')[0]} • ${_formatDuration(audioEntry.duration)} • ${audioEntry.mode == 'emotional_venting' ? 'Venting' : 'Analysis'} • ${audioEntry.syncStatus}${audioEntry.isTraining ? ' • Training (${audioEntry.moodLabel ?? 'label'})' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              audioEntry.syncStatus == SyncStatus.synced
                                  ? Icons.cloud_done
                                  : audioEntry.syncStatus == SyncStatus.failed
                                  ? Icons.cloud_off
                                  : Icons.cloud_upload,
                              color: _syncStatusColor(audioEntry.syncStatus),
                              semanticLabel: _syncStatusLabel(
                                audioEntry.syncStatus,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.analytics,
                                color: Colors.green,
                              ),
                              onPressed: _isAnalyzing
                                  ? null
                                  : () => _analyzeAudio(audioEntry),
                              tooltip: 'Analyze Mood',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                if (!kIsWeb) {
                                  final file = getFile(audioEntry.filePath);
                                  if (await file.exists()) {
                                    await file.delete();
                                  }
                                }
                                await widget.dataService.deleteAudioEntry(
                                  audioEntry,
                                );
                                await box.delete(audioEntry.id);
                                await AnalyticsService.track(
                                  'audio_deleted',
                                  properties: {
                                    'sync_status': audioEntry.syncStatus,
                                  },
                                );
                                _showSnackBar('Recording deleted');
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          // TODO: Implement audio playback
                          _showSnackBar('Playback not implemented yet');
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
