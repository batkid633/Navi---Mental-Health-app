// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'evaluation_feedback.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EvaluationFeedbackAdapter extends TypeAdapter<EvaluationFeedback> {
  @override
  final int typeId = 2;

  @override
  EvaluationFeedback read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EvaluationFeedback(
      id: fields[0] as String,
      targetType: fields[1] as String,
      targetDate: fields[2] as String,
      journalEntryId: fields[3] as String?,
      predictedDelta: fields[4] as double?,
      confidence: fields[5] as double?,
      modelVersion: fields[6] as String?,
      insight: fields[7] as String?,
      accuracyRating: fields[8] as String?,
      helpfulnessRating: fields[9] as String?,
      actualMoodDirection: fields[10] as String?,
      note: fields[11] as String?,
      createdAt: fields[12] as DateTime?,
      updatedAt: fields[13] as DateTime?,
      syncStatus: fields[14] as String? ?? SyncStatus.pending,
      syncAttempts: fields[15] as int? ?? 0,
      lastSyncError: fields[16] as String?,
      lastSyncedAt: fields[17] as DateTime?,
      nextRetryAt: fields[18] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, EvaluationFeedback obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.targetType)
      ..writeByte(2)
      ..write(obj.targetDate)
      ..writeByte(3)
      ..write(obj.journalEntryId)
      ..writeByte(4)
      ..write(obj.predictedDelta)
      ..writeByte(5)
      ..write(obj.confidence)
      ..writeByte(6)
      ..write(obj.modelVersion)
      ..writeByte(7)
      ..write(obj.insight)
      ..writeByte(8)
      ..write(obj.accuracyRating)
      ..writeByte(9)
      ..write(obj.helpfulnessRating)
      ..writeByte(10)
      ..write(obj.actualMoodDirection)
      ..writeByte(11)
      ..write(obj.note)
      ..writeByte(12)
      ..write(obj.createdAt)
      ..writeByte(13)
      ..write(obj.updatedAt)
      ..writeByte(14)
      ..write(obj.syncStatus)
      ..writeByte(15)
      ..write(obj.syncAttempts)
      ..writeByte(16)
      ..write(obj.lastSyncError)
      ..writeByte(17)
      ..write(obj.lastSyncedAt)
      ..writeByte(18)
      ..write(obj.nextRetryAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvaluationFeedbackAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
