import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/keyboard_session_entry.dart';
import 'data_service.dart';
import 'settings_service.dart';

class KeyboardTrackingService {
  static const int _sessionIdleTimeoutSeconds = 30;
  static const int _burstPauseMs = 2000;

  final DataService dataService;

  KeyboardTrackingService({required this.dataService});

  KeyboardTextControllerTracker attachTextController({
    required TextEditingController controller,
    required String fieldContext,
  }) {
    final tracker = KeyboardTextControllerTracker(
      dataService: dataService,
      controller: controller,
      fieldContext: fieldContext,
    );
    tracker.start();
    return tracker;
  }
}

class KeyboardTextControllerTracker {
  final DataService dataService;
  final TextEditingController controller;
  final String fieldContext;

  late final VoidCallback _listener;
  DateTime? _startedAt;
  DateTime? _lastEventAt;
  Timer? _idleTimer;
  int _lastLength = 0;
  int _eventCount = 0;
  int _charsEstimated = 0;
  int _backspaceCount = 0;
  int _burstCount = 0;
  final List<int> _pausesMs = [];
  bool _started = false;

  KeyboardTextControllerTracker({
    required this.dataService,
    required this.controller,
    required this.fieldContext,
  });

  void start() {
    if (_started) return;
    _started = true;
    _lastLength = controller.text.length;
    _listener = _handleTextChanged;
    controller.addListener(_listener);
  }

  Future<void> flush() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final session = _buildSession();
    _resetSession(keepLastLength: true);
    if (session == null) return;
    await dataService.saveKeyboardSession(session);
  }

  Future<void> dispose() async {
    if (_started) {
      controller.removeListener(_listener);
      _started = false;
    }
    await flush();
  }

  void resetBaseline() {
    _resetSession(keepLastLength: false);
  }

  void _handleTextChanged() {
    if (!SettingsService.keyboardTrackingEnabled) {
      _resetSession(keepLastLength: false);
      return;
    }

    final now = DateTime.now();
    final currentLength = controller.text.length;
    final delta = currentLength - _lastLength;
    _lastLength = currentLength;
    if (delta == 0) return;

    if (_startedAt == null) {
      _startedAt = now;
      _burstCount = 1;
    }

    final previousEventAt = _lastEventAt;
    if (previousEventAt != null) {
      final pauseMs = now.difference(previousEventAt).inMilliseconds;
      if (pauseMs >= 0) {
        _pausesMs.add(pauseMs);
      }
      if (pauseMs > KeyboardTrackingService._burstPauseMs) {
        _burstCount++;
      }
    }
    _lastEventAt = now;
    _eventCount++;
    if (delta > 0) {
      _charsEstimated += delta;
    } else {
      _backspaceCount += delta.abs();
    }

    _idleTimer?.cancel();
    _idleTimer = Timer(
      const Duration(
        seconds: KeyboardTrackingService._sessionIdleTimeoutSeconds,
      ),
      () {
        unawaited(flush());
      },
    );
  }

  KeyboardSessionEntry? _buildSession() {
    if (_startedAt == null || _lastEventAt == null || _eventCount == 0) {
      return null;
    }
    if (_charsEstimated == 0 && _backspaceCount == 0) {
      return null;
    }

    final startedAt = _startedAt!;
    final endedAt = _lastEventAt!;
    final activeSeconds = max(1, endedAt.difference(startedAt).inSeconds);
    final pauseMean = _pausesMs.isEmpty
        ? 0.0
        : _pausesMs.reduce((a, b) => a + b) / _pausesMs.length;
    final pauseStd = _pausesMs.isEmpty
        ? 0.0
        : sqrt(
            _pausesMs
                    .map((pause) => pow(pause - pauseMean, 2).toDouble())
                    .reduce((a, b) => a + b) /
                _pausesMs.length,
          );

    return KeyboardSessionEntry(
      id: KeyboardSessionEntry.canonicalId(startedAt),
      startedAt: startedAt,
      endedAt: endedAt,
      fieldContext: fieldContext,
      platform: _platformLabel(),
      eventCount: _eventCount,
      charsEstimated: _charsEstimated,
      backspaceCount: _backspaceCount,
      burstCount: _burstCount,
      pauseMeanMs: pauseMean,
      pauseStdMs: pauseStd,
      activeSeconds: activeSeconds,
    );
  }

  void _resetSession({required bool keepLastLength}) {
    _idleTimer?.cancel();
    _idleTimer = null;
    _startedAt = null;
    _lastEventAt = null;
    _eventCount = 0;
    _charsEstimated = 0;
    _backspaceCount = 0;
    _burstCount = 0;
    _pausesMs.clear();
    if (!keepLastLength) {
      _lastLength = controller.text.length;
    }
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 'mobile';
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return 'desktop';
      case TargetPlatform.fuchsia:
        return 'unknown';
    }
  }
}
