import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi_personal/services/today_refresh_flow.dart';

void main() {
  test('prediction waits for successful input sync', () async {
    final gate = Completer<bool>();
    var loaded = false;
    final result = refreshToday<String>(
      enabled: () => true,
      sharingEnabled: () => true,
      syncInputs: () => gate.future,
      load: () async {
        loaded = true;
        return 'fresh';
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(loaded, isFalse);
    gate.complete(true);
    expect(await result, 'fresh');
  });
  test(
    'failed input sync does not load an old prediction as refreshed',
    () async {
      var loaded = false;
      final result = await refreshToday<String>(
        enabled: () => true,
        sharingEnabled: () => true,
        syncInputs: () async => false,
        load: () async {
          loaded = true;
          return 'old';
        },
      );
      expect(result, isNull);
      expect(loaded, isFalse);
    },
  );
  test('sharing off never invokes input sync', () async {
    final result = await refreshToday<String>(
      enabled: () => true,
      sharingEnabled: () => false,
      syncInputs: () async => throw StateError('Must not share'),
      load: () async => 'existing data',
    );
    expect(result, 'existing data');
  });
  test(
    'disabling insights while syncing prevents the prediction request',
    () async {
      var enabled = true;
      var loaded = false;
      final result = await refreshToday<String>(
        enabled: () => enabled,
        sharingEnabled: () => true,
        syncInputs: () async {
          enabled = false;
          return true;
        },
        load: () async {
          loaded = true;
          return 'unwanted';
        },
      );
      expect(result, isNull);
      expect(loaded, isFalse);
    },
  );
}
