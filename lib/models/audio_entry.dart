import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'audio_entry.g.dart';

@HiveType(typeId: 1)
class AudioEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime date;

  @HiveField(2)
  String filePath;

  @HiveField(3)
  String fileName;

  @HiveField(4)
  int duration; // in seconds

  @HiveField(5)
  String? transcription;

  @HiveField(6)
  String mode; // 'emotional_venting' or 'deeper_analysis'

  @HiveField(7)
  String? moodLabel;

  @HiveField(8)
  bool isTraining;

  AudioEntry({
    required this.id,
    required this.date,
    required this.filePath,
    required this.fileName,
    required this.duration,
    this.transcription,
    required this.mode,
    this.moodLabel,
    this.isTraining = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'filePath': filePath,
      'fileName': fileName,
      'duration': duration,
      'transcription': transcription,
      'mode': mode,
      'moodLabel': moodLabel,
      'isTraining': isTraining,
    };
  }

  factory AudioEntry.fromJson(Map<String, dynamic> json) {
    return AudioEntry(
      id: json['id'],
      date: DateTime.parse(json['date']),
      filePath: json['filePath'],
      fileName: json['fileName'],
      duration: json['duration'],
      transcription: json['transcription'],
      mode: json['mode'],
      moodLabel: json['moodLabel'],
      isTraining: json['isTraining'] ?? false,
    );
  }
}