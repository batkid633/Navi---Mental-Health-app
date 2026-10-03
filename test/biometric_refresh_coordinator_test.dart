import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi_personal/services/biometric_refresh_coordinator.dart';

void main() {
  test(
    'simultaneous readers share one import and refresh is throttled',
    () async {
      var clock = DateTime.utc(2026, 9, 16);
      var calls = 0;
      final completion = Completer<bool>();
      final coordinator = BiometricRefreshCoordinator(
        clock: () => clock,
        refresh: (_) {
          calls++;
          return completion.future;
        },
      );
      final a = coordinator.ensureFresh('account|endpoint');
      final b = coordinator.ensureFresh('account|endpoint');
      completion.complete(true);
      expect(await a, 1);
      expect(await b, 1);
      expect(calls, 1);
      expect(await coordinator.ensureFresh('account|endpoint'), 1);
      expect(calls, 1);
      clock = clock.add(const Duration(minutes: 31));
      expect(await coordinator.ensureFresh('account|endpoint'), 2);
      expect(calls, 2);
    },
  );

  test(
    'failed imports allow insights to proceed and retry after backoff',
    () async {
      var clock = DateTime.utc(2026, 9, 16);
      var calls = 0;
      final coordinator = BiometricRefreshCoordinator(
        clock: () => clock,
        refresh: (_) {
          calls++;
          if (calls == 1) throw StateError('offline');
          return Future.value(true);
        },
      );
      expect(await coordinator.ensureFresh('a'), 0);
      expect(await coordinator.ensureFresh('a'), 0);
      expect(calls, 1);
      clock = clock.add(const Duration(minutes: 6));
      expect(await coordinator.ensureFresh('a'), 1);
      expect(calls, 2);
    },
  );

  test('accounts and backend selections have independent freshness', () async {
    var calls = 0;
    final coordinator = BiometricRefreshCoordinator(
      refresh: (_) async {
        calls++;
        return true;
      },
    );
    await coordinator.ensureFresh('a|production');
    await coordinator.ensureFresh('b|production');
    await coordinator.ensureFresh('a|local');
    expect(calls, 3);
  });

  test('unconnected providers do not signal new prediction data', () async {
    final coordinator = BiometricRefreshCoordinator(
      refresh: (_) async => false,
    );
    expect(await coordinator.ensureFresh('a'), 0);
  });
}
