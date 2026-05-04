import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import '../models/audio_entry.dart';
import '../services/audio_analysis_service.dart';
import '../services/data_service.dart';

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
  String _selectedMode = 'emotional_venting'; // 'emotional_venting' or 'deeper_analysis'
  bool _trainingMode = false;
  String _selectedMoodLabel = 'neutral';

  // Recording state for deeper analysis
  bool _isCalibrationPhase = false;
  bool _isGuidedPhase = false;
  String _currentInstruction = '';

  // Analysis state
  bool _isAnalyzing = false;
  Map<String, dynamic>? _lastAnalysis;

  Box<AudioEntry>? audioBox;

  @override
  void initState() {
    super.initState();
    _initBox();
  }

  Future<void> _initBox() async {
    audioBox = await widget.dataService.getAudioBox();
    setState(() {});
  }

  Future<String> _getRecordingPath() async {
    final directory = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${directory.path}/audio');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    final fileName = '${_uuid.v4()}.wav';
    return '${audioDir.path}/$fileName';
  }

  Future<void> _startRecording() async {
    if (audioBox == null) {
      _showSnackBar('Preparing audio storage. Please wait a moment and try again.');
      return;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        final path = await _getRecordingPath();

        if (_selectedMode == 'deeper_analysis') {
          // Start with calibration phase
          setState(() {
            _isCalibrationPhase = true;
            _currentInstruction = 'Please read this calibration sentence clearly:\n\n"The quick brown fox jumps over the lazy dog."';
          });

          // Wait for user to read calibration sentence (5 seconds)
          await Future.delayed(const Duration(seconds: 5));

          setState(() {
            _isCalibrationPhase = false;
            _isGuidedPhase = true;
            _currentInstruction = 'Now, please speak naturally about how you\'re feeling today for the next 30 seconds.';
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
        _showSnackBar('Microphone permission denied');
      }
    } catch (e) {
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
        // Save to Hive
        final audioEntry = AudioEntry(
          id: _uuid.v4(),
          date: DateTime.now(),
          filePath: path,
          fileName: path.split('/').last,
          duration: _recordingDuration,
          mode: _selectedMode,
          moodLabel: _trainingMode ? _selectedMoodLabel : null,
          isTraining: _trainingMode,
        );

        await audioBox!.add(audioEntry);
        await widget.dataService.syncAudioEntryToCloud(audioEntry);

        if (_selectedMode == 'emotional_venting') {
          _showSnackBar('Emotional venting session saved! Duration: ${_formatDuration(_recordingDuration)}');
          _showEmotionalIntervention();
        } else {
          _showSnackBar('Deep analysis session saved! Duration: ${_formatDuration(_recordingDuration)}');
        }
      } else if (path == null) {
        _showSnackBar('No recording was captured. Please try again.');
      }
    } catch (e) {
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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

  Future<void> _analyzeAudio(String audioPath, String mode) async {
    setState(() {
      _isAnalyzing = true;
    });

    try {
      final file = File(audioPath);
      final analysis = await AudioAnalysisService.analyzeAudio(file, mode: mode);

      setState(() {
        _lastAnalysis = analysis;
        _isAnalyzing = false;
      });

      if (analysis.containsKey('error')) {
        _showSnackBar('Analysis failed: ${analysis['error']}');
      } else {
        _showSnackBar('Audio analyzed successfully!');
      }
    } catch (e) {
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
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Logs'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
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
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Training mode', style: TextStyle(fontWeight: FontWeight.w600)),
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
                  const Text('Select mood label', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['neutral', 'happy', 'sad', 'angry', 'calm', 'anxious']
                        .map((option) {
                      final selected = option == _selectedMoodLabel;
                      return ChoiceChip(
                        label: Text(option[0].toUpperCase() + option.substring(1)),
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
          if (_selectedMode == 'deeper_analysis' && (_isCalibrationPhase || _isGuidedPhase))
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
                          ? (_isCalibrationPhase ? 'Calibration Phase' : 'Guided Speech')
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
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isRecording ? _stopRecording : _startRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    textStyle: const TextStyle(fontSize: 18),
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
          else if (_lastAnalysis != null && !_lastAnalysis!.containsKey('error'))
            Builder(
              builder: (context) {
                final mode = _lastAnalysis!['mode'] as String? ?? 'emotional_venting';
                final moodAnalysis = _lastAnalysis!['mood_analysis'] as Map<String, dynamic>?;
                final audioFeatures = _lastAnalysis!['audio_features'] as Map<String, dynamic>?;
                final intervention = _lastAnalysis!['intervention'] as Map<String, dynamic>?;
                final mfccAnalysis = _lastAnalysis!['mfcc_analysis'] as Map<String, dynamic>?;

                String formatNumber(dynamic value, {int digits = 1}) {
                  if (value == null) return 'N/A';
                  if (value is num) return value.toStringAsFixed(digits);
                  if (value is String) {
                    final parsed = double.tryParse(value);
                    return parsed != null ? parsed.toStringAsFixed(digits) : value;
                  }
                  return value.toString();
                }

                return Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Last Analysis Results',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Mode: ${mode == 'emotional_venting' ? 'Emotional Venting' : 'Deep Analysis'}',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      if (moodAnalysis != null) ...[
                        Text(
                          'Predicted Mood: ${moodAnalysis['predicted_mood'] ?? 'Unknown'}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        if (moodAnalysis['confidence'] != null)
                          Text(
                            'Confidence: ${formatNumber((moodAnalysis['confidence'] as num?) ?? 0, digits: 1)}%',
                            style: const TextStyle(fontSize: 16),
                          ),
                      ],
                      if (audioFeatures != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Duration: ${formatNumber(audioFeatures['duration_seconds'])}s',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        Text(
                          'Tempo: ${formatNumber(audioFeatures['tempo_bpm'])} BPM',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                      if (intervention != null && intervention['suggestions'] is List) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Support Suggestions:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        ...((intervention['suggestions'] as List).cast<dynamic>()).map((suggestion) => 
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('• $suggestion', style: const TextStyle(fontSize: 14)),
                          )
                        ),
                      ],
                      if (mfccAnalysis != null) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Deep MFCC Analysis:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Spectral Centroid: ${formatNumber(mfccAnalysis['spectral_features']?['centroid_mean'], digits: 2)} Hz',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        Text(
                          'Tempo: ${formatNumber(mfccAnalysis['rhythm_features']?['tempo'])} BPM',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

          // Recordings List
          Expanded(
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

                return ListView.builder(
                  itemCount: box.values.length,
                  itemBuilder: (context, index) {
                    final audioEntry = box.getAt(index);
                    if (audioEntry == null) return const SizedBox();

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.audiotrack, color: Colors.blue),
                        title: Text(audioEntry.fileName),
                        subtitle: Text(
                          '${audioEntry.date.toString().split(' ')[0]} • ${_formatDuration(audioEntry.duration)} • ${audioEntry.mode == 'emotional_venting' ? 'Venting' : 'Analysis'}${audioEntry.isTraining ? ' • Training (${audioEntry.moodLabel ?? 'label'})' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.analytics, color: Colors.green),
                              onPressed: _isAnalyzing
                                ? null
                                : () => _analyzeAudio(audioEntry.filePath, audioEntry.mode),
                              tooltip: 'Analyze Mood',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                // Delete file from storage
                                final file = File(audioEntry.filePath);
                                if (await file.exists()) {
                                  await file.delete();
                                }
                                // Delete from Hive
                                await box.deleteAt(index);
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
