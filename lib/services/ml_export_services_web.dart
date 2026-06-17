import '../services/insights_service.dart';
import '../models/audio_entry.dart';
import '../models/journal_entry.dart';
import '../models/keyboard_session_entry.dart';
import '../models/navi_beacon_sample.dart';
import '../models/baseline_deviation_model.dart';
import '../legal/legal_content.dart';
import 'package:hive/hive.dart';

class MLExportService {
  static const String researchSchemaName = 'navi_research_daily_features';
  static const String researchSchemaVersion = '1.0.0';

  static Map<DateTime, double> computeNextDayDelta(
    Map<DateTime, double> dailyAvg,
  ) {
    final sortedDays = dailyAvg.keys.toList()..sort();
    final Map<DateTime, double> nextDayDelta = {};

    for (int i = 0; i < sortedDays.length - 1; i++) {
      final today = sortedDays[i];
      final tomorrow = sortedDays[i + 1];
      nextDayDelta[today] = dailyAvg[tomorrow]! - dailyAvg[today]!;
    }

    return nextDayDelta;
  }

  static Future<String?> exportDailyFeatures(
    Box<JournalEntry> journalBox,
  ) async {
    // Web does not support local file export via dart:io.
    return null;
  }

  static List<Map<String, dynamic>> buildDailyFeatureRecords(
    Box<JournalEntry> journalBox, {
    Iterable<AudioEntry> audioEntries = const [],
    Iterable<KeyboardSessionEntry> keyboardSessions = const [],
    Iterable<NaviBeaconSample> beaconSamples = const [],
  }) {
    final dailyAvg = InsightsService.dailyAverageSentiment(journalBox);
    final rolling7 = InsightsService.rollingAverage(dailyAvg, 7);
    final vol7 = InsightsService.rollingVolatility(dailyAvg, 7);
    final mom7 = InsightsService.rollingMomentum(dailyAvg, 7);
    final nextDelta = computeNextDayDelta(dailyAvg);
    final audioByDay = _audioFeatureRecords(audioEntries);
    final keyboardByDay = _keyboardFeatureRecords(keyboardSessions);
    final beaconByDay = _beaconFeatureRecords(beaconSamples);

    final records = <Map<String, dynamic>>[];
    final sortedDays = dailyAvg.keys.toList()..sort();

    for (final date in sortedDays) {
      if (!rolling7.containsKey(date) || !vol7.containsKey(date)) continue;

      final deviation = BaselineDeviationModel.evaluate(
        today: dailyAvg[date]!,
        rollingMean: rolling7[date]!,
        rollingStd: vol7[date]!,
      );
      final generatedAt = DateTime.now().toUtc().toIso8601String();

      records.add({
        'date': date.toIso8601String().substring(0, 10),
        'schema_name': researchSchemaName,
        'schema_version': researchSchemaVersion,
        'generated_at': generatedAt,
        'record_type': 'daily_feature_summary',
        'source_system': 'navi_flutter_app',
        'consent_scope': 'optional_research_sharing',
        'consent_version': LegalContent.consentVersion,
        'privacy_policy_version': LegalContent.privacyPolicyVersion,
        'terms_version': LegalContent.termsVersion,
        'data_classification': 'coded_research_feature',
        'identifiability': 'coded',
        'raw_text_included': false,
        'raw_audio_included': false,
        'research_use_allowed': true,
        'sentiment_today': dailyAvg[date],
        'rolling_mean_7': rolling7[date],
        'volatility_7': vol7[date],
        'momentum_7': mom7[date],
        'z_score': deviation.zScore,
        'is_anomalous': deviation.isAnomalous ? 1 : 0,
        'day_of_week': date.weekday - 1,
        'Next_day_delta': nextDelta[date],
        ...?audioByDay[_dateKey(date)],
        ...?keyboardByDay[_dateKey(date)],
        ...?beaconByDay[_dateKey(date)],
        'missing_journal': 0,
        'missing_biometrics': beaconByDay.containsKey(_dateKey(date)) ? 0 : 1,
        'missing_audio': audioByDay.containsKey(_dateKey(date)) ? 0 : 1,
        'missing_keyboard': keyboardByDay.containsKey(_dateKey(date)) ? 0 : 1,
        'missing_sleep': 1,
        'missing_hrv': 1,
        'missing_recovery': 1,
      });
    }

    return records;
  }

  static Map<String, Map<String, dynamic>> _audioFeatureRecords(
    Iterable<AudioEntry> entries,
  ) {
    final grouped = <String, List<AudioEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(_dateKey(entry.date), () => []).add(entry);
    }

    return grouped.map((date, entries) {
      final labeled = entries
          .map((entry) => entry.moodLabel?.trim().toLowerCase())
          .where((label) => label != null && label.isNotEmpty)
          .cast<String>()
          .toList();
      double ratio(Set<String> labels) {
        if (labeled.isEmpty) return 0.0;
        final count = labeled.where(labels.contains).length;
        return count / labeled.length;
      }

      return MapEntry(date, {
        'audio_session_count': entries.length,
        'audio_total_seconds': entries.fold<int>(
          0,
          (sum, entry) => sum + entry.duration,
        ),
        'audio_negative_ratio': ratio({'sad', 'angry'}),
        'audio_positive_ratio': ratio({'happy'}),
        'audio_anxious_ratio': ratio({'anxious'}),
        'audio_calm_ratio': ratio({'calm', 'neutral'}),
        'audio_training_count': entries
            .where((entry) => entry.isTraining)
            .length,
      });
    });
  }

  static Map<String, Map<String, dynamic>> _keyboardFeatureRecords(
    Iterable<KeyboardSessionEntry> sessions,
  ) {
    final grouped = <String, List<KeyboardSessionEntry>>{};
    for (final session in sessions) {
      grouped.putIfAbsent(_dateKey(session.startedAt), () => []).add(session);
    }

    double average(Iterable<num> values) {
      final list = values.map((value) => value.toDouble()).toList();
      if (list.isEmpty) return 0.0;
      return list.reduce((a, b) => a + b) / list.length;
    }

    return grouped.map((date, sessions) {
      final total = sessions.length;
      final lateNight = sessions.where((session) {
        final hour = session.startedAt.hour;
        return hour >= 22 || hour < 5;
      }).length;
      int platformCount(String platform) {
        return sessions.where((session) => session.platform == platform).length;
      }

      return MapEntry(date, {
        'keyboard_session_count': total,
        'keyboard_active_seconds': sessions.fold<int>(
          0,
          (sum, session) => sum + session.activeSeconds,
        ),
        'keyboard_event_count': sessions.fold<int>(
          0,
          (sum, session) => sum + session.eventCount,
        ),
        'keyboard_chars_estimated': sessions.fold<int>(
          0,
          (sum, session) => sum + session.charsEstimated,
        ),
        'keyboard_backspace_count': sessions.fold<int>(
          0,
          (sum, session) => sum + session.backspaceCount,
        ),
        'keyboard_correction_rate': average(
          sessions.map((session) => session.correctionRate),
        ),
        'keyboard_pause_mean_ms': average(
          sessions.map((session) => session.pauseMeanMs),
        ),
        'keyboard_pause_std_ms': average(
          sessions.map((session) => session.pauseStdMs),
        ),
        'keyboard_burst_count': sessions.fold<int>(
          0,
          (sum, session) => sum + session.burstCount,
        ),
        'keyboard_typing_speed_cpm': average(
          sessions.map((session) => session.typingSpeedCpm),
        ),
        'keyboard_late_night_ratio': total == 0 ? 0.0 : lateNight / total,
        'keyboard_platform_web': total == 0
            ? 0.0
            : platformCount('web') / total,
        'keyboard_platform_mobile': total == 0
            ? 0.0
            : platformCount('mobile') / total,
        'keyboard_platform_desktop': total == 0
            ? 0.0
            : platformCount('desktop') / total,
      });
    });
  }

  static Map<String, Map<String, dynamic>> _beaconFeatureRecords(
    Iterable<NaviBeaconSample> samples,
  ) {
    final grouped = <String, List<NaviBeaconSample>>{};
    for (final sample in samples) {
      grouped.putIfAbsent(_dateKey(sample.capturedAt), () => []).add(sample);
    }

    double average(Iterable<num?> values) {
      final list = values
          .where((value) => value != null)
          .map((value) => value!.toDouble())
          .toList();
      if (list.isEmpty) return 0.0;
      return list.reduce((a, b) => a + b) / list.length;
    }

    int? minInt(Iterable<int?> values) {
      final list = values.whereType<int>().toList();
      if (list.isEmpty) return null;
      list.sort();
      return list.first;
    }

    int? maxInt(Iterable<int?> values) {
      final list = values.whereType<int>().toList();
      if (list.isEmpty) return null;
      list.sort();
      return list.last;
    }

    return grouped.map((date, samples) {
      final total = samples.length;
      double activityRatio(String activity) {
        if (total == 0) return 0.0;
        return samples.where((sample) => sample.activity == activity).length /
            total;
      }

      return MapEntry(date, {
        'beacon_sample_count': total,
        'beacon_hr_avg': average(samples.map((sample) => sample.heartRate)),
        'beacon_hr_min': minInt(samples.map((sample) => sample.heartRate)),
        'beacon_hr_max': maxInt(samples.map((sample) => sample.heartRate)),
        'beacon_temp_c_avg': average(
          samples.map((sample) => sample.temperatureC),
        ),
        'beacon_lux_avg': average(samples.map((sample) => sample.lux)),
        'beacon_motion_avg': average(
          samples.map((sample) => sample.motionMagnitude),
        ),
        'beacon_battery_avg': average(
          samples.map((sample) => sample.batteryPercent),
        ),
        'beacon_activity_still_ratio': activityRatio('still'),
        'beacon_activity_walking_ratio': activityRatio('walking'),
        'beacon_activity_running_ratio': activityRatio('running'),
        'beacon_activity_restless_ratio': activityRatio('restless'),
      });
    });
  }

  static String _dateKey(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String().substring(0, 10);
  }
}
