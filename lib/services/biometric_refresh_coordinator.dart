/// Coordinates refreshes without platform APIs, credentials, or network code.
class BiometricRefreshCoordinator {
  final Future<bool> Function(String scope) refresh;
  final DateTime Function() now;
  final Duration successInterval;
  final Duration retryInterval;
  final Map<String, _RefreshState> _states = {};

  BiometricRefreshCoordinator({
    required this.refresh,
    DateTime Function()? clock,
    this.successInterval = const Duration(minutes: 30),
    this.retryInterval = const Duration(minutes: 5),
  }) : now = clock ?? DateTime.now;

  Future<int> ensureFresh(String scope) {
    final state = _states.putIfAbsent(scope, _RefreshState.new);
    if (state.pending != null) return state.pending!;
    if (state.nextAttempt != null && now().isBefore(state.nextAttempt!)) {
      return Future.value(state.revision);
    }
    final future = _run(scope, state);
    state.pending = future;
    return future;
  }

  Future<int> _run(String scope, _RefreshState state) async {
    try {
      final changed = await Future<bool>.sync(() => refresh(scope));
      if (changed) state.revision++;
      state.nextAttempt = now().add(successInterval);
    } catch (_) {
      state.nextAttempt = now().add(retryInterval);
    } finally {
      state.pending = null;
    }
    return state.revision;
  }
}

class _RefreshState {
  Future<int>? pending;
  DateTime? nextAttempt;
  int revision = 0;
}
