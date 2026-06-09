import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
  static const String algorithmName = 'aes-256-gcm';
  static const String recoveryAlgorithmName = 'pbkdf2-sha256+aes-256-gcm';
  static const int schemaVersion = 1;
  static const int _recoveryIterations = 310000;
  static const int _recoveryKeyBits = 256;

  final FlutterSecureStorage? _secureStorage;
  final Map<String, String>? _memoryStore;
  final AesGcm _algorithm = AesGcm.with256bits();

  EncryptionService({
    FlutterSecureStorage? secureStorage,
    Map<String, String>? memoryStore,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _memoryStore = memoryStore;

  Future<List<int>> hiveKeyForUser(String? uid) {
    return _keyBytes('hive_${_scope(uid)}');
  }

  Future<String> exportRecoveryKit(String? uid, String passphrase) async {
    final normalizedPassphrase = passphrase.trim();
    if (normalizedPassphrase.length < 12) {
      throw ArgumentError('Recovery passphrase must be at least 12 characters');
    }

    final scopedUid = _scope(uid);
    final cloudKey = await _keyBytes('cloud_$scopedUid');
    final salt = _algorithm.newNonce();
    final wrappingKey = await _recoverySecretKey(
      normalizedPassphrase,
      salt: salt,
    );
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      cloudKey,
      secretKey: wrappingKey,
      nonce: nonce,
    );

    return jsonEncode({
      'format': 'navi-e2ee-recovery-kit',
      'schemaVersion': schemaVersion,
      'scope': scopedUid,
      'kdf': {
        'algorithm': 'pbkdf2-sha256',
        'iterations': _recoveryIterations,
        'salt': base64Encode(salt),
        'bits': _recoveryKeyBits,
      },
      'encryption': {
        'algorithm': recoveryAlgorithmName,
        'nonce': base64Encode(secretBox.nonce),
        'ciphertext': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
      },
    });
  }

  Future<void> importRecoveryKit(
    String? uid,
    String passphrase,
    String recoveryKit,
  ) async {
    final decoded = jsonDecode(recoveryKit);
    if (decoded is! Map) {
      throw const FormatException('Recovery kit is not a JSON object');
    }
    final kit = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (kit['format'] != 'navi-e2ee-recovery-kit') {
      throw const FormatException('Unsupported recovery kit format');
    }

    final scopedUid = _scope(uid);
    if (kit['scope']?.toString() != scopedUid) {
      throw const FormatException('Recovery kit belongs to a different user');
    }

    final kdf = kit['kdf'];
    final encryption = kit['encryption'];
    if (kdf is! Map || encryption is! Map) {
      throw const FormatException('Recovery kit is missing key metadata');
    }
    if (kdf['algorithm'] != 'pbkdf2-sha256' ||
        encryption['algorithm'] != recoveryAlgorithmName) {
      throw const FormatException('Unsupported recovery kit algorithm');
    }

    final wrappingKey = await _recoverySecretKey(
      passphrase.trim(),
      salt: base64Decode(kdf['salt']?.toString() ?? ''),
      iterations: _intFromJson(kdf['iterations'], _recoveryIterations),
      bits: _intFromJson(kdf['bits'], _recoveryKeyBits),
    );
    final cloudKey = await _algorithm.decrypt(
      SecretBox(
        base64Decode(encryption['ciphertext']?.toString() ?? ''),
        nonce: base64Decode(encryption['nonce']?.toString() ?? ''),
        mac: Mac(base64Decode(encryption['mac']?.toString() ?? '')),
      ),
      secretKey: wrappingKey,
    );
    if (cloudKey.length != 32) {
      throw const FormatException('Recovery kit key has invalid length');
    }

    await _write('navi_e2ee_key_cloud_$scopedUid', base64Encode(cloudKey));
  }

  Future<Map<String, dynamic>> encryptJson(
    String? uid,
    Map<String, dynamic> payload,
  ) async {
    final secretKey = SecretKey(await _keyBytes('cloud_${_scope(uid)}'));
    final nonce = _algorithm.newNonce();
    final clearText = utf8.encode(jsonEncode(payload));
    final secretBox = await _algorithm.encrypt(
      clearText,
      secretKey: secretKey,
      nonce: nonce,
    );
    return {
      'schemaVersion': schemaVersion,
      'encryption': {
        'algorithm': algorithmName,
        'nonce': base64Encode(secretBox.nonce),
        'ciphertext': base64Encode(secretBox.cipherText),
        'mac': base64Encode(secretBox.mac.bytes),
      },
    };
  }

  Future<Map<String, dynamic>> decryptJson(
    String? uid,
    Map<String, dynamic> encrypted,
  ) async {
    final encryption = encrypted['encryption'];
    if (encryption is! Map) {
      throw const FormatException('Missing encrypted payload');
    }
    if (encryption['algorithm'] != algorithmName) {
      throw const FormatException('Unsupported encryption algorithm');
    }
    final secretKey = SecretKey(await _keyBytes('cloud_${_scope(uid)}'));
    final clearText = await _algorithm.decrypt(
      SecretBox(
        base64Decode(encryption['ciphertext']?.toString() ?? ''),
        nonce: base64Decode(encryption['nonce']?.toString() ?? ''),
        mac: Mac(base64Decode(encryption['mac']?.toString() ?? '')),
      ),
      secretKey: secretKey,
    );
    final decoded = jsonDecode(utf8.decode(clearText));
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('Encrypted payload is not a JSON object');
  }

  Future<List<int>> encryptBytes(String? uid, List<int> bytes) async {
    final secretKey = SecretKey(await _keyBytes('cloud_${_scope(uid)}'));
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      bytes,
      secretKey: secretKey,
      nonce: nonce,
    );
    return utf8.encode(
      jsonEncode({
        'schemaVersion': schemaVersion,
        'encryption': {
          'algorithm': algorithmName,
          'nonce': base64Encode(secretBox.nonce),
          'ciphertext': base64Encode(secretBox.cipherText),
          'mac': base64Encode(secretBox.mac.bytes),
        },
      }),
    );
  }

  Future<List<int>> decryptBytes(String? uid, List<int> encryptedBytes) async {
    final decoded = jsonDecode(utf8.decode(encryptedBytes));
    if (decoded is! Map) {
      throw const FormatException('Encrypted bytes payload is not an object');
    }
    final payload = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final encryption = payload['encryption'];
    if (encryption is! Map) {
      throw const FormatException('Missing encrypted bytes payload');
    }
    if (encryption['algorithm'] != algorithmName) {
      throw const FormatException('Unsupported encryption algorithm');
    }
    final secretKey = SecretKey(await _keyBytes('cloud_${_scope(uid)}'));
    return _algorithm.decrypt(
      SecretBox(
        base64Decode(encryption['ciphertext']?.toString() ?? ''),
        nonce: base64Decode(encryption['nonce']?.toString() ?? ''),
        mac: Mac(base64Decode(encryption['mac']?.toString() ?? '')),
      ),
      secretKey: secretKey,
    );
  }

  Future<List<int>> _keyBytes(String purpose) async {
    final storageKey = 'navi_e2ee_key_$purpose';
    final existing = await _read(storageKey);
    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }

    final secretKey = await _algorithm.newSecretKey();
    final bytes = await secretKey.extractBytes();
    await _write(storageKey, base64Encode(bytes));
    return bytes;
  }

  Future<SecretKey> _recoverySecretKey(
    String passphrase, {
    required List<int> salt,
    int iterations = _recoveryIterations,
    int bits = _recoveryKeyBits,
  }) {
    if (passphrase.length < 12) {
      throw ArgumentError('Recovery passphrase must be at least 12 characters');
    }
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: bits,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  Future<String?> _read(String key) async {
    if (_memoryStore != null) {
      return _memoryStore[key];
    }
    return _secureStorage?.read(key: key);
  }

  Future<void> _write(String key, String value) async {
    if (_memoryStore != null) {
      _memoryStore[key] = value;
      return;
    }
    await _secureStorage?.write(key: key, value: value);
  }

  String _scope(String? uid) {
    final trimmed = uid?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return 'shared';
    }
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }

  int _intFromJson(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
