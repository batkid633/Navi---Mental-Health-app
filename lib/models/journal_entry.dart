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
    return JournalEntry(
      id: json['id'],
      date: DateTime.parse(json['date']),
      text: json['text'],
      sentimentLabel: json['sentimentLabel'],
      sentimentScore: json['sentimentScore']?.toDouble(),
    );
  }
}
