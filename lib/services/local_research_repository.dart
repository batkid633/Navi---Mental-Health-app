import 'dart:convert';
import 'dart:math';

import 'package:hive/hive.dart';

import '../models/audio_entry.dart';
import '../models/journal_entry.dart';
import '../models/keyboard_session_entry.dart';
import '../models/navi_beacon_sample.dart';

/// Encrypted by the caller. Contains no network or analytics operations.
/// Coded longitudinal data is not anonymous or certified deidentified.
class LocalResearchRepository {
  static const schema = 'navi_local_research_v1';
  final Box<dynamic> box;
  final DateTime Function() now;
  static final Map<String, Future<void>> _queues = {};

  LocalResearchRepository(this.box, {DateTime Function()? clock})
    : now = clock ?? DateTime.now;

  Future<T> _serial<T>(Future<T> Function() action) {
    final pending = _queues[box.name] ?? Future<void>.value();
    final result = pending.then((_) => action());
    _queues[box.name] = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Map<String, dynamic> get _state => Map<String, dynamic>.from(box.get('state', defaultValue: <String, dynamic>{}) as Map);
  bool get enabled => _state['enabled'] == true;
  int get rowCount => (_state['rows'] as Map? ?? {}).length;
  String? get lastCollectedAt => _state['last_collected_at'] as String?;

  Future<void> setEnabled(bool value) => _serial(() async {
    final state = _state;
    if ((state['enabled'] == true) == value) return;
    final instant = now().toUtc().toIso8601String();
    final intervals = List<dynamic>.from(state['intervals'] as List? ?? []);
    if (value) {
      state['participant_code'] ??= base64UrlEncode(List<int>.generate(24, (_) => Random.secure().nextInt(256)));
      state['enrolled_at'] ??= instant;
      intervals.add({'start': instant, 'end': null});
    } else if (intervals.isNotEmpty) {
      intervals[intervals.length - 1] = {...Map<String, dynamic>.from(intervals.last as Map), 'end': instant};
    }
    state['enabled'] = value;
    state['intervals'] = intervals;
    state['consent_version'] = 'local-research-1';
    await box.put('state', state);
    await box.flush();
  });

  Future<void> deleteResearchCopy() => _serial(() async {
    await box.delete('state');
    await box.flush();
  });

  Future<void> collect({
    Iterable<JournalEntry>? journals,
    Iterable<AudioEntry>? audio,
    Iterable<KeyboardSessionEntry>? keyboard,
    Iterable<NaviBeaconSample>? beacon,
  }) => _serial(() async {
    final state = _state;
    if (state['enabled'] != true) return;
    final collectedAt = now().toUtc();
    final enrollment = DateTime.parse(state['enrolled_at'] as String).toUtc();
    final origin = DateTime.utc(enrollment.year, enrollment.month, enrollment.day);
    final intervals = (state['intervals'] as List).cast<Map>();
    bool eligible(DateTime date) {
      final t = date.toUtc();
      return !t.isAfter(collectedAt) && intervals.any((i) =>
        !t.isBefore(DateTime.parse(i['start'] as String)) &&
        (i['end'] == null || t.isBefore(DateTime.parse(i['end'] as String))));
    }
    int day(DateTime date) {
      final t = date.toUtc();
      return DateTime.utc(t.year, t.month, t.day).difference(origin).inDays;
    }
    final rows = <String, Map<String, dynamic>>{
      for (final e in (state['rows'] as Map? ?? {}).entries)
        e.key.toString(): Map<String, dynamic>.from(e.value as Map),
    };
    Map<String, dynamic> row(int index) => rows.putIfAbsent('$index', () => {
      'day_index': index,
      'journal_count': null, 'audio_count': null, 'audio_seconds': null,
      'keyboard_count': null, 'keyboard_active_seconds': null,
      'beacon_count': null, 'beacon_heart_rate_mean': null,
      'sleep_hours': null, 'hrv_rmssd': null, 'hrv_sdnn': null,
    });
    void clearFields(List<String> fields) {
      for (final r in rows.values) {
        for (final field in fields) { r[field] = null; }
      }
    }
    if (journals != null) {
      clearFields(['journal_count']);
      final seen = <String>{};
      for (final e in journals.where((e) => eligible(e.date))) {
        if (!seen.add(e.id)) continue;
        final r = row(day(e.date));
        r['journal_count'] = (r['journal_count'] as int? ?? 0) + 1;
      }
    }
    if (audio != null) {
      clearFields(['audio_count', 'audio_seconds']);
      final seen = <String>{};
      for (final e in audio.where((e) => eligible(e.date))) {
        if (!seen.add(e.id) || e.duration < 0) continue;
        final r = row(day(e.date));
        r['audio_count'] = (r['audio_count'] as int? ?? 0) + 1;
        r['audio_seconds'] = (r['audio_seconds'] as int? ?? 0) + e.duration;
      }
    }
    if (keyboard != null) {
      clearFields(['keyboard_count', 'keyboard_active_seconds']);
      final seen = <String>{};
      for (final e in keyboard.where((e) => eligible(e.startedAt) && eligible(e.endedAt))) {
        if (!seen.add(e.id) || e.activeSeconds < 0) continue;
        final r = row(day(e.startedAt));
        r['keyboard_count'] = (r['keyboard_count'] as int? ?? 0) + 1;
        r['keyboard_active_seconds'] = (r['keyboard_active_seconds'] as int? ?? 0) + e.activeSeconds;
      }
    }
    if (beacon != null) {
      clearFields(['beacon_count', 'beacon_heart_rate_mean']);
      final seen = <String>{};
      final heartRates = <int, List<int>>{};
      for (final e in beacon.where((e) => eligible(e.capturedAt))) {
        if (!seen.add(e.id)) continue;
        final index = day(e.capturedAt);
        final r = row(index);
        r['beacon_count'] = (r['beacon_count'] as int? ?? 0) + 1;
        final hr = e.heartRate;
        if (hr != null && hr > 0 && hr <= 300) {
          heartRates.putIfAbsent(index, () => []).add(hr);
        }
      }
      for (final e in heartRates.entries) {
        row(e.key)['beacon_heart_rate_mean'] = e.value.reduce((a, b) => a + b) / e.value.length;
      }
    }
    rows.removeWhere((_, r) => ['journal_count', 'audio_count', 'keyboard_count', 'beacon_count'].every((key) => r[key] == null));
    state['rows'] = rows;
    state['last_collected_at'] = collectedAt.toIso8601String();
    await box.put('state', state);
    await box.flush();
  });

  /// Explicit allowlist; internal consent timestamps and account linkage stay local.
  Map<String, dynamic> reviewPacket() {
    const fields = ['day_index', 'journal_count', 'audio_count', 'audio_seconds',
      'keyboard_count', 'keyboard_active_seconds', 'beacon_count',
      'beacon_heart_rate_mean', 'sleep_hours', 'hrv_rmssd', 'hrv_sdnn'];
    final state = _state;
    final records = (state['rows'] as Map? ?? {}).values.map((value) {
      final r = Map<String, dynamic>.from(value as Map);
      return {for (final key in fields) key: r[key]};
    }).toList()..sort((a, b) => (a['day_index'] as int).compareTo(b['day_index'] as int));
    return {
      'schema': schema, 'participant_code': state['participant_code'],
      'classification': 'coded_sensitive_not_anonymous',
      'consent_version': state['consent_version'], 'collection_enabled': enabled,
      'day_basis': 'UTC_calendar_days_since_local_enrollment',
      'raw_text_included': false, 'raw_audio_included': false,
      'health_provider_collection': 'not_connected_to_local_repository',
      'record_count': records.length, 'records': records,
    };
  }
}
