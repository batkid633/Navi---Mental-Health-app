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

  test('recovery kit exports legacy cloud keys when present', () async {
    final originalDevice = EncryptionService(memoryStore: {});
    final oldEncrypted = await originalDevice.encryptJson('user-1', {
      'text': 'encrypted with the original cloud key',
    });

    final otherDevice = EncryptionService(memoryStore: {});
    final otherDeviceKit = await otherDevice.exportRecoveryKit(
      'user-1',
      'correct horse battery',
    );
    await originalDevice.importRecoveryKit(
      'user-1',
      'correct horse battery',
      otherDeviceKit,
    );
    final newEncrypted = await originalDevice.encryptJson('user-1', {
      'text': 'encrypted with the imported cloud key',
    });

    final keyringKit = await originalDevice.exportRecoveryKit(
      'user-1',
      'new recovery passphrase',
    );
    final restoredDevice = EncryptionService(memoryStore: {});
    await restoredDevice.importRecoveryKit(
      'user-1',
      'new recovery passphrase',
      keyringKit,
    );

    final oldDecrypted = await restoredDevice.decryptJson(
      'user-1',
      oldEncrypted,
    );
    final newDecrypted = await restoredDevice.decryptJson(
      'user-1',
      newEncrypted,
    );
    expect(oldDecrypted['text'], 'encrypted with the original cloud key');
    expect(newDecrypted['text'], 'encrypted with the imported cloud key');
  });

  test(
    'account cloud keyring makes encrypted data portable across devices',
    () async {
      final webDevice = EncryptionService(memoryStore: {});
      final encrypted = await webDevice.encryptJson('user-1', {
        'text': 'portable journal text',
      });
      final accountKeyring = await webDevice.exportCloudKeyringForUser(
        'user-1',
      );

      final mobileDevice = EncryptionService(memoryStore: {});
      await mobileDevice.importCloudKeyringForUser('user-1', accountKeyring);

      final decrypted = await mobileDevice.decryptJson('user-1', encrypted);
      expect(decrypted['text'], 'portable journal text');
    },
  );
}
