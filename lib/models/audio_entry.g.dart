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
      mode: fields[6] as String? ?? 'emotional_venting', // Default for existing data
    );
  }

  @override
  void write(BinaryWriter writer, AudioEntry obj) {
    writer
      ..writeByte(7)
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
      ..write(obj.mode);
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
