// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AudioEntryAdapter extends TypeAdapter<AudioEntry> {
  @override
  final int typeId = 1;

  @override
  AudioEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AudioEntry(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      filePath: fields[2] as String,
      fileName: fields[3] as String,
      duration: fields[4] as int,
      transcription: fields[5] as String?,
      mode:
          fields[6] as String? ??
          'emotional_venting', // Default for existing data
      moodLabel: fields[7] as String?,
      isTraining: fields[8] as bool? ?? false,
      syncStatus: fields[9] as String? ?? SyncStatus.pending,
      syncAttempts: fields[10] as int? ?? 0,
      lastSyncError: fields[11] as String?,
      lastSyncedAt: fields[12] as DateTime?,
      nextRetryAt: fields[13] as DateTime?,
      storagePath: fields[14] as String?,
      downloadUrl: fields[15] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AudioEntry obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.filePath)
      ..writeByte(3)
      ..write(obj.fileName)
      ..writeByte(4)
      ..write(obj.duration)
      ..writeByte(5)
      ..write(obj.transcription)
      ..writeByte(6)
      ..write(obj.mode)
      ..writeByte(7)
      ..write(obj.moodLabel)
      ..writeByte(8)
      ..write(obj.isTraining)
      ..writeByte(9)
      ..write(obj.syncStatus)
      ..writeByte(10)
      ..write(obj.syncAttempts)
      ..writeByte(11)
      ..write(obj.lastSyncError)
      ..writeByte(12)
      ..write(obj.lastSyncedAt)
      ..writeByte(13)
      ..write(obj.nextRetryAt)
      ..writeByte(14)
      ..write(obj.storagePath)
      ..writeByte(15)
      ..write(obj.downloadUrl);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
