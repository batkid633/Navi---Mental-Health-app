import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:navi_personal/services/local_check_in_service.dart';
import 'package:navi_personal/services/notification_service.dart';
import 'package:navi_personal/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('navi_notifications_');
    Hive.init(directory.path);
    await SettingsService.init();
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    await Hive.box<dynamic>('settings').put('cloudSyncEnabled', false);
    messenger.setMockMethodCallHandler(LocalCheckInService.channel, (
      call,
    ) async {
      calls.add(call);
      return {
        'scheduled': call.arguments['enabled'],
        'permissionStatus': 'authorized',
      };
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(LocalCheckInService.channel, null);
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('iPhone schedules locally without Firebase or cloud sync', () async {
    await SettingsService.saveCheckInNotificationSettings(
      enabled: true,
      timeMinutes: 1234,
    );
    final result = await NotificationService.instance.configureForUser(
      'local-test-user',
    );
    expect(result.enabled, isTrue);
    expect(result.permissionGranted, isTrue);
    expect(calls.single.method, 'configure');
    expect(calls.single.arguments, {'enabled': true, 'timeMinutes': 1234});
  });

  test(
    'changing time, disabling, and signing out update local reminder',
    () async {
      await SettingsService.saveCheckInNotificationSettings(
        enabled: true,
        timeMinutes: 480,
      );
      await NotificationService.instance.configureForUser('local-test-user');
      await SettingsService.saveCheckInNotificationSettings(
        enabled: true,
        timeMinutes: 600,
      );
      await NotificationService.instance.configureForUser('local-test-user');
      await SettingsService.saveCheckInNotificationSettings(
        enabled: false,
        timeMinutes: 600,
      );
      await NotificationService.instance.configureForUser('local-test-user');
      await SettingsService.saveCheckInNotificationSettings(
        enabled: true,
        timeMinutes: 600,
      );
      final signedOut = await NotificationService.instance.configureForUser(
        null,
      );
      expect(calls.map((call) => call.arguments['enabled']), [
        true,
        true,
        false,
        false,
      ]);
      expect(calls[1].arguments['timeMinutes'], 600);
      expect(signedOut.enabled, isFalse);
      expect(signedOut.permissionStatus, 'signed_out');
    },
  );

  test('denied permission is not reported as a scheduled reminder', () async {
    messenger.setMockMethodCallHandler(
      LocalCheckInService.channel,
      (_) async => {'scheduled': false, 'permissionStatus': 'denied'},
    );
    await SettingsService.saveCheckInNotificationSettings(
      enabled: true,
      timeMinutes: 600,
    );
    final result = await NotificationService.instance.configureForUser(
      'local-test-user',
    );
    expect(result.enabled, isFalse);
    expect(result.permissionGranted, isFalse);
    expect(result.permissionStatus, 'denied');
  });

  test(
    'disable waits for pending permission request and errors do not block retries',
    () async {
      final first = Completer<Map<String, dynamic>>();
      messenger.setMockMethodCallHandler(LocalCheckInService.channel, (
        call,
      ) async {
        calls.add(call);
        if (calls.length == 1) return first.future;
        return {'scheduled': false, 'permissionStatus': 'disabled'};
      });
      final service = LocalCheckInService();
      final enable = service.configure(enabled: true, timeMinutes: 600);
      final disable = service.configure(enabled: false, timeMinutes: 600);
      final failure = expectLater(enable, throwsA(isA<PlatformException>()));
      await Future<void>.delayed(Duration.zero);
      expect(calls.length, 1);
      first.completeError(PlatformException(code: 'permission_error'));
      await failure;
      expect((await disable)['scheduled'], isFalse);
      expect(calls.length, 2);
      expect(calls.last.arguments['enabled'], isFalse);
    },
  );
}
