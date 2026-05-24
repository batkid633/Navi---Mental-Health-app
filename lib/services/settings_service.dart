import 'package:hive/hive.dart';

class SettingsService {
  static const String _boxName = 'settings';
  static const String _keyUseWiFi = 'useWiFi';
  static const String _keyWiFiIP = 'wiFiIP';
  static const String _keyBackendUrl = 'backendUrl';
  static const int defaultPort = 8000;

  static Box<dynamic>? _box;

  static Future<void> init() async {
    _box ??= await Hive.openBox<dynamic>(_boxName);
  }

  static bool get useWiFi {
    return _box?.get(_keyUseWiFi, defaultValue: false) as bool;
  }

  static String get wiFiIP {
    return _box?.get(_keyWiFiIP, defaultValue: '') as String;
  }

  static String get backendUrl {
    return _box?.get(_keyBackendUrl, defaultValue: '') as String;
  }

  static bool get hasCustomBackendUrl {
    return backendUrl.trim().isNotEmpty;
  }

  static String get effectiveBaseUrl {
    final customUrl = backendUrl.trim();
    if (customUrl.isNotEmpty) {
      return _normalizeUrl(customUrl);
    }

    final ip = wiFiIP.trim();
    if (useWiFi && ip.isNotEmpty) {
      return 'http://$ip:$defaultPort';
    }

    return 'http://127.0.0.1:$defaultPort';
  }

  static Future<void> saveUseWiFi(bool value) async {
    await _ensureInitialized();
    await _box?.put(_keyUseWiFi, value);
  }

  static Future<void> saveWiFiIP(String value) async {
    await _ensureInitialized();
    await _box?.put(_keyWiFiIP, value.trim());
  }

  static Future<void> saveBackendUrl(String value) async {
    await _ensureInitialized();
    await _box?.put(_keyBackendUrl, _normalizeUrl(value));
  }

  static Future<void> resetToDefaults() async {
    await _ensureInitialized();
    await _box?.put(_keyUseWiFi, false);
    await _box?.put(_keyWiFiIP, '');
    await _box?.put(_keyBackendUrl, '');
  }

  static Future<void> _ensureInitialized() async {
    if (_box == null) {
      await init();
    }
  }

  static String _normalizeUrl(String value) {
    var trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    // Fix common malformed URL inputs.
    trimmed = trimmed.replaceAll('\\', '/');
    if (trimmed.startsWith('http:/') && !trimmed.startsWith('http://')) {
      trimmed = 'http://${trimmed.substring(6)}';
    } else if (trimmed.startsWith('https:/') && !trimmed.startsWith('https://')) {
      trimmed = 'https://${trimmed.substring(7)}';
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      // Remove repeated slashes after scheme if present.
      trimmed = trimmed.replaceFirst(RegExp(r'^(https?:)/+'), r'$1//');
    } else {
      trimmed = 'http://$trimmed';
    }

    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }

    return trimmed;
  }
}
