// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'navi_beacon_sample.dart';

class NaviBeaconSampleAdapter extends TypeAdapter<NaviBeaconSample> {
  @override
  final int typeId = 4;

  @override
  NaviBeaconSample read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NaviBeaconSample(
      id: fields[0] as String,
      capturedAt: fields[1] as DateTime,
      heartRate: fields[2] as int?,
      temperatureC: fields[3] as double?,
      lux: fields[4] as double?,
      activity: fields[5] as String? ?? 'still',
      batteryPercent: fields[6] as int?,
      accelerationX: fields[7] as double?,
      accelerationY: fields[8] as double?,
      accelerationZ: fields[9] as double?,
      motionMagnitude: fields[10] as double?,
      signalQuality: fields[11] as int?,
      sourceDeviceId: fields[12] as String? ?? 'navi_beacon',
      syncStatus: fields[13] as String? ?? SyncStatus.pending,
      syncAttempts: fields[14] as int? ?? 0,
      lastSyncError: fields[15] as String?,
      lastSyncedAt: fields[16] as DateTime?,
      nextRetryAt: fields[17] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, NaviBeaconSample obj) {
    writer
      ..writeByte(18)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.capturedAt)
      ..writeByte(2)
      ..write(obj.heartRate)
      ..writeByte(3)
      ..write(obj.temperatureC)
      ..writeByte(4)
      ..write(obj.lux)
      ..writeByte(5)
      ..write(obj.activity)
      ..writeByte(6)
      ..write(obj.batteryPercent)
      ..writeByte(7)
      ..write(obj.accelerationX)
      ..writeByte(8)
      ..write(obj.accelerationY)
      ..writeByte(9)
      ..write(obj.accelerationZ)
      ..writeByte(10)
      ..write(obj.motionMagnitude)
      ..writeByte(11)
      ..write(obj.signalQuality)
      ..writeByte(12)
      ..write(obj.sourceDeviceId)
      ..writeByte(13)
      ..write(obj.syncStatus)
      ..writeByte(14)
      ..write(obj.syncAttempts)
      ..writeByte(15)
      ..write(obj.lastSyncError)
      ..writeByte(16)
      ..write(obj.lastSyncedAt)
      ..writeByte(17)
      ..write(obj.nextRetryAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NaviBeaconSampleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
