// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'keyboard_session_entry.dart';

class KeyboardSessionEntryAdapter extends TypeAdapter<KeyboardSessionEntry> {
  @override
  final int typeId = 3;

  @override
  KeyboardSessionEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return KeyboardSessionEntry(
      id: fields[0] as String,
      startedAt: fields[1] as DateTime,
      endedAt: fields[2] as DateTime,
      fieldContext: fields[3] as String,
      platform: fields[4] as String,
      eventCount: fields[5] as int,
      charsEstimated: fields[6] as int,
      backspaceCount: fields[7] as int,
      burstCount: fields[8] as int,
      pauseMeanMs: fields[9] as double,
      pauseStdMs: fields[10] as double,
      activeSeconds: fields[11] as int,
      syncStatus: fields[12] as String? ?? SyncStatus.pending,
      syncAttempts: fields[13] as int? ?? 0,
      lastSyncError: fields[14] as String?,
      lastSyncedAt: fields[15] as DateTime?,
      nextRetryAt: fields[16] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, KeyboardSessionEntry obj) {
    writer
      ..writeByte(17)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.startedAt)
      ..writeByte(2)
      ..write(obj.endedAt)
      ..writeByte(3)
      ..write(obj.fieldContext)
      ..writeByte(4)
      ..write(obj.platform)
      ..writeByte(5)
      ..write(obj.eventCount)
      ..writeByte(6)
      ..write(obj.charsEstimated)
      ..writeByte(7)
      ..write(obj.backspaceCount)
      ..writeByte(8)
      ..write(obj.burstCount)
      ..writeByte(9)
      ..write(obj.pauseMeanMs)
      ..writeByte(10)
      ..write(obj.pauseStdMs)
      ..writeByte(11)
      ..write(obj.activeSeconds)
      ..writeByte(12)
      ..write(obj.syncStatus)
      ..writeByte(13)
      ..write(obj.syncAttempts)
      ..writeByte(14)
      ..write(obj.lastSyncError)
      ..writeByte(15)
      ..write(obj.lastSyncedAt)
      ..writeByte(16)
      ..write(obj.nextRetryAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyboardSessionEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
