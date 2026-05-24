import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

part 'journal_entry.g.dart';

@HiveType(typeId: 0)
class JournalEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime date;

  @HiveField(2)
  String text;

  @HiveField(3)
  String? sentimentLabel;

  @HiveField(4)
  double? sentimentScore;

  JournalEntry({
    required this.id,
    required this.date,
    required this.text,
    this.sentimentLabel,
    this.sentimentScore,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'text': text,
      'sentimentLabel': sentimentLabel,
      'sentimentScore': sentimentScore,
    };
  }

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    final dynamic dateValue = json['date'];
    late final DateTime date;
    if (dateValue is DateTime) {
      date = dateValue;
    } else if (dateValue is int) {
      date = DateTime.fromMillisecondsSinceEpoch(dateValue);
    } else if (dateValue is String) {
      date = DateTime.tryParse(dateValue) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    final dynamic sentimentScoreValue = json['sentimentScore'] ?? json['sentiment_score'];
    final double? sentimentScore = sentimentScoreValue is num
        ? sentimentScoreValue.toDouble()
        : double.tryParse(sentimentScoreValue?.toString() ?? '');

    return JournalEntry(
      id: id,
      date: date,
      text: json['text']?.toString() ?? '',
      sentimentLabel: json['sentimentLabel'] ?? json['sentiment_label'],
      sentimentScore: sentimentScore,
    );
  }
}
