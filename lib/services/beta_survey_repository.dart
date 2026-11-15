import 'package:hive/hive.dart';

/// Account-scoped encrypted storage; optional transport receives only aggregates.
class BetaSurveyRepository {
  final Box<dynamic> box;
  final DateTime Function() now;
  final Future<void> Function(Map<String, dynamic>? snapshot)? upload;
  bool _syncing = false;
  BetaSurveyRepository(this.box, {DateTime Function()? clock, this.upload})
    : now = clock ?? DateTime.now;
  static const version = 'beta-feedback-1';
  static const issues = [
    'none',
    'navigation',
    'audio',
    'insights',
    'health_sync',
    'other',
  ];
  String get today {
    final d = now().toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  bool get enabled => box.get('enabled', defaultValue: true) == true;
  bool get sharing => box.get('sharing', defaultValue: false) == true;
  bool get pending => box.get('pending', defaultValue: false) == true;
  bool get deletionPending =>
      box.get('deleteShared', defaultValue: false) == true;
  String get sharingStatus => deletionPending
      ? 'Shared deletion pending; reconnect and retry.'
      : pending
      ? 'Saved locally; upload pending.'
      : sharing
      ? 'Sharing enabled. Future saved answers sync automatically.'
      : 'Sharing off. Previously uploaded feedback remains until deleted.';

  Future<void> setSharing(bool value) async {
    if (value && deletionPending) {
      throw StateError('Complete shared deletion first');
    }
    await box.put('sharing', value);
    if (value) {
      await box.put('consentVersion', 'beta-sharing-1');
    } else {
      await box.put('pending', false);
    }
    await box.flush();
  }

  Map<String, dynamic> get sharedSnapshot {
    final rows = box.keys
        .where((k) => k.toString().startsWith('shared:'))
        .map((k) => Map<String, dynamic>.from(box.get(k) as Map))
        .toList();
    return {
      'schemaVersion': version,
      'consentVersion': 'beta-sharing-1',
      'completed': rows.length,
      for (final field in ['ease', 'helpfulness'])
        '${field}Counts': [
          for (var i = 1; i <= 5; i++) rows.where((r) => r[field] == i).length,
        ],
      'issueCounts': [
        for (final issue in issues)
          rows.where((r) => r['issue'] == issue).length,
      ],
    };
  }

  Future<void> deleteShared() async {
    await setSharing(false);
    await box.put('deleteShared', true);
    await box.deleteAll(
      box.keys.where((k) => k.toString().startsWith('shared:')).toList(),
    );
    await box.flush();
    await sync();
  }

  Future<void> sync() async {
    if (_syncing || upload == null) return;
    _syncing = true;
    final wasDeleting = deletionPending;
    try {
      if (deletionPending) {
        await upload!(null);
        await box.put('deleteShared', false);
      } else if (sharing && pending) {
        final snapshot = sharedSnapshot;
        await upload!(snapshot);
        // A save during the request must remain queued for the next retry.
        if (snapshot.toString() == sharedSnapshot.toString()) {
          await box.put('pending', false);
        }
      }
      await box.flush();
    } catch (_) {
      // Retain durable pending state; retry on save, resume, or explicit retry.
    } finally {
      _syncing = false;
    }
    // An opt-out deletion requested during an upload must run after that upload.
    if (deletionPending && !wasDeleting) await sync();
  }

  bool get due => enabled && !box.containsKey('day:$today');
  Map<String, dynamic>? responseFor(String day) {
    final value = box.get('day:$day');
    if (value is! Map || value['status'] != 'completed') return null;
    return Map<String, dynamic>.from(value);
  }

  Future<void> setEnabled(bool enabled) async {
    await box.put('enabled', enabled);
    await box.flush();
  }

  Future<void> skip(String day) async {
    if (!box.containsKey('day:$day')) {
      await box.put('day:$day', {'status': 'skipped', 'version': version});
      await box.flush();
    }
  }

  Future<void> save({
    required String day,
    int? ease,
    int? helpfulness,
    required String issue,
  }) async {
    if (day != today) throw StateError('The day changed. Reopen the survey.');
    for (final rating in [ease, helpfulness]) {
      if (rating != null && (rating < 1 || rating > 5)) {
        throw ArgumentError('Ratings must be 1–5');
      }
    }
    if (!issues.contains(issue)) throw ArgumentError('Unknown issue');
    await box.put('day:$day', {
      'status': 'completed',
      'version': version,
      'ease': ease,
      'helpfulness': helpfulness,
      'issue': issue,
    });
    if (sharing) {
      await box.put('shared:$day', {
        'ease': ease,
        'helpfulness': helpfulness,
        'issue': issue,
      });
      await box.put('pending', true);
    }
    await box.flush();
    await sync();
  }

  List<Map<String, dynamic>> get days =>
      box.keys
          .where((k) => k.toString().startsWith('day:'))
          .map(
            (k) => {
              'date': k.toString().substring(4),
              ...Map<String, dynamic>.from(box.get(k) as Map),
            },
          )
          .toList()
        ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  Map<String, dynamic> get statistics {
    final all = days;
    final responses = all.where((r) => r['status'] == 'completed').toList();
    Map<String, dynamic> rating(String field) {
      final values = responses.map((r) => r[field]).whereType<int>().toList();
      return {
        'n': values.length,
        'mean': values.isEmpty
            ? null
            : values.reduce((a, b) => a + b) / values.length,
        'counts': [
          for (var i = 1; i <= 5; i++) values.where((v) => v == i).length,
        ],
      };
    }

    return {
      'completed': responses.length,
      'skipped': all.length - responses.length,
      'recorded_days': all.length,
      'ease': rating('ease'),
      'helpfulness': rating('helpfulness'),
      'issues': {
        for (final issue in issues)
          issue: responses.where((r) => r['issue'] == issue).length,
      },
    };
  }

  String aggregateCsv() {
    final stats = statistics;
    final lines = ['metric,category,count,mean', 'schema_version,$version,,'];
    for (final field in ['completed', 'skipped', 'recorded_days']) {
      lines.add('$field,total,${stats[field]},');
    }
    for (final field in ['ease', 'helpfulness']) {
      final r = stats[field] as Map;
      lines.add('$field,rated_responses,${r['n']},${r['mean'] ?? ''}');
      for (var i = 1; i <= 5; i++) {
        lines.add('$field,$i,${(r['counts'] as List)[i - 1]},');
      }
    }
    for (final e in (stats['issues'] as Map).entries) {
      lines.add('issues,${e.key},${e.value},');
    }
    return '${lines.join('\n')}\n';
  }

  Future<void> deleteResponses() async {
    await deleteShared();
    await box.deleteAll(
      box.keys.where((k) => k.toString().startsWith('day:')).toList(),
    );
    await setEnabled(false);
  }
}
