import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../models/navi_beacon_sample.dart';

class NaviBeaconDevice {
  final String id;
  final String name;
  final int? rssi;

  const NaviBeaconDevice({required this.id, required this.name, this.rssi});
}

enum NaviBeaconConnectionState { disconnected, scanning, connecting, connected }

class NaviBeaconBleService {
  static final Uuid serviceUuid = Uuid.parse(
    '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  );
  static final Uuid telemetryUuid = Uuid.parse(
    '6e400003-b5a3-f393-e0a9-e50e24dcca9e',
  );

  final FlutterReactiveBle _ble;
  final _stateController =
      StreamController<NaviBeaconConnectionState>.broadcast();
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _telemetrySub;

  NaviBeaconBleService({FlutterReactiveBle? ble})
    : _ble = ble ?? FlutterReactiveBle() {
    _stateController.add(NaviBeaconConnectionState.disconnected);
  }

  bool get isSupported {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  Stream<NaviBeaconConnectionState> get connectionState =>
      _stateController.stream;

  Stream<NaviBeaconDevice> scan({
    Duration timeout = const Duration(seconds: 8),
  }) {
    if (!isSupported) {
      return Stream.error(
        UnsupportedError('Navi Beacon BLE is not supported on this platform.'),
      );
    }
    final controller = StreamController<NaviBeaconDevice>();
    final seen = <String>{};
    _stateController.add(NaviBeaconConnectionState.scanning);
    _scanSub?.cancel();
    _scanSub = _ble
        .scanForDevices(
          withServices: [serviceUuid],
          scanMode: ScanMode.lowLatency,
        )
        .listen((device) {
          if (seen.add(device.id)) {
            controller.add(
              NaviBeaconDevice(
                id: device.id,
                name: device.name.isEmpty ? 'Navi Beacon' : device.name,
                rssi: device.rssi,
              ),
            );
          }
        }, onError: controller.addError);

    Timer(timeout, () async {
      await _scanSub?.cancel();
      _scanSub = null;
      if (!controller.isClosed) {
        await controller.close();
      }
      _stateController.add(NaviBeaconConnectionState.disconnected);
    });

    return controller.stream;
  }

  Future<void> connectAndListen(
    String deviceId, {
    required Future<void> Function(NaviBeaconSample sample) onSample,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'Navi Beacon BLE is not supported on this platform.',
      );
    }
    await _scanSub?.cancel();
    await _connectionSub?.cancel();
    await _telemetrySub?.cancel();
    _stateController.add(NaviBeaconConnectionState.connecting);

    _connectionSub = _ble.connectToDevice(id: deviceId).listen((update) {
      if (update.connectionState == DeviceConnectionState.connected) {
        _stateController.add(NaviBeaconConnectionState.connected);
        final characteristic = QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: telemetryUuid,
          deviceId: deviceId,
        );
        _telemetrySub?.cancel();
        _telemetrySub = _ble.subscribeToCharacteristic(characteristic).listen((
          bytes,
        ) async {
          final jsonText = utf8.decode(bytes, allowMalformed: true);
          final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
          decoded['sourceDeviceId'] = deviceId;
          decoded['capturedAt'] ??= DateTime.now().toIso8601String();
          final sample = NaviBeaconSample.fromJson(decoded);
          await onSample(sample);
        });
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        _stateController.add(NaviBeaconConnectionState.disconnected);
      }
    }, onError: _stateController.addError);
  }

  Future<void> disconnect() async {
    await _telemetrySub?.cancel();
    await _connectionSub?.cancel();
    await _scanSub?.cancel();
    _telemetrySub = null;
    _connectionSub = null;
    _scanSub = null;
    _stateController.add(NaviBeaconConnectionState.disconnected);
  }
}
