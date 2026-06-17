import '../models/navi_beacon_sample.dart';

class NaviBeaconDevice {
  final String id;
  final String name;
  final int? rssi;

  const NaviBeaconDevice({required this.id, required this.name, this.rssi});
}

enum NaviBeaconConnectionState { disconnected, scanning, connecting, connected }

class NaviBeaconBleService {
  bool get isSupported => false;

  Stream<NaviBeaconConnectionState> get connectionState async* {
    yield NaviBeaconConnectionState.disconnected;
  }

  Stream<NaviBeaconDevice> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async* {}

  Future<void> connectAndListen(
    String deviceId, {
    required Future<void> Function(NaviBeaconSample sample) onSample,
  }) async {
    throw UnsupportedError(
      'Navi Beacon BLE is not supported on this platform.',
    );
  }

  Future<void> disconnect() async {}
}
