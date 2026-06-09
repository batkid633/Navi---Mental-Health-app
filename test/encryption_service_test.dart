import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:navi_personal/services/encryption_service.dart';

void main() {
  test('encryptJson round trips with the same user key', () async {
    final service = EncryptionService(memoryStore: {});
    final encrypted = await service.encryptJson('user-1', {
      'text': 'private journal text',
      'sentimentScore': 0.4,
    });

    expect(encrypted['encryption'], isA<Map>());
    expect(encrypted.toString(), isNot(contains('private journal text')));

    final decrypted = await service.decryptJson('user-1', encrypted);
    expect(decrypted['text'], 'private journal text');
    expect(decrypted['sentimentScore'], 0.4);
  });

  test('decryptJson fails with a different user key', () async {
    final service = EncryptionService(memoryStore: {});
    final encrypted = await service.encryptJson('user-1', {
      'text': 'private journal text',
    });

    expect(
      () => service.decryptJson('user-2', encrypted),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('hiveKeyForUser is stable and user scoped', () async {
    final service = EncryptionService(memoryStore: {});

    final first = await service.hiveKeyForUser('user-1');
    final second = await service.hiveKeyForUser('user-1');
    final other = await service.hiveKeyForUser('user-2');

    expect(first, second);
    expect(first, isNot(other));
    expect(first.length, 32);
  });

  test('recovery kit restores cloud decryption on another device', () async {
    final firstDevice = EncryptionService(memoryStore: {});
    final encrypted = await firstDevice.encryptJson('user-1', {
      'text': 'recoverable private journal text',
    });
    final recoveryKit = await firstDevice.exportRecoveryKit(
      'user-1',
      'correct horse battery',
    );

    final secondDevice = EncryptionService(memoryStore: {});
    await secondDevice.importRecoveryKit(
      'user-1',
      'correct horse battery',
      recoveryKit,
    );

    final decrypted = await secondDevice.decryptJson('user-1', encrypted);
    expect(decrypted['text'], 'recoverable private journal text');
  });

  test('recovery kit rejects the wrong passphrase', () async {
    final firstDevice = EncryptionService(memoryStore: {});
    final recoveryKit = await firstDevice.exportRecoveryKit(
      'user-1',
      'correct horse battery',
    );
    final secondDevice = EncryptionService(memoryStore: {});

    expect(
      () => secondDevice.importRecoveryKit(
        'user-1',
        'incorrect horse battery',
        recoveryKit,
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
