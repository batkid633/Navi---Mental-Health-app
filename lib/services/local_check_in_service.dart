import 'package:flutter/services.dart';

/// Schedules the iPhone reminder through UserNotifications, without a server.
class LocalCheckInService {
  static const channel = MethodChannel('navi/local_check_in');
  Future<void> _pending = Future<void>.value();

  Future<Map<String, dynamic>> configure({
    required bool enabled,
    required int timeMinutes,
  }) {
    if (timeMinutes < 0 || timeMinutes >= 24 * 60) {
      throw ArgumentError.value(timeMinutes, 'timeMinutes');
    }
    // Keep rapid toggle/time changes in order, including permission prompts.
    final operation = _pending.then((_) async {
      final result = await channel.invokeMapMethod<String, dynamic>(
        'configure',
        {'enabled': enabled, 'timeMinutes': timeMinutes},
      );
      if (result == null) {
        throw StateError('No reminder scheduling result was returned.');
      }
      return result;
    });
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
