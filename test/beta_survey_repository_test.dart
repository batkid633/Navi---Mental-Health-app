import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:navi_personal/services/beta_survey_repository.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late BetaSurveyRepository repository;
  late DateTime clock;
  final key = List<int>.generate(32, (i) => i);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('navi_beta_test_');
    Hive.init(directory.path);
    box = await Hive.openBox<dynamic>(
      'beta',
      encryptionCipher: HiveAesCipher(key),
    );
    clock = DateTime(2026, 10, 24, 12);
    repository = BetaSurveyRepository(box, clock: () => clock);
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test(
    'sharing defaults off and enabling does not upload historical answers',
    () async {
      final uploads = <Map<String, dynamic>?>[];
      repository = BetaSurveyRepository(
        box,
        clock: () => clock,
        upload: (s) async {
          uploads.add(s);
        },
      );
      await repository.save(day: repository.today, ease: 1, issue: 'audio');
      expect(repository.sharing, isFalse);
      await repository.sync();
      expect(uploads, isEmpty);
      await repository.setSharing(true);
      await repository.sync();
      expect(uploads, isEmpty);
      clock = clock.add(const Duration(days: 1));
      await repository.save(day: repository.today, ease: 5, issue: 'none');
      expect(uploads.single!['completed'], 1);
      expect(uploads.single!['easeCounts'], [0, 0, 0, 0, 1]);
      expect(
        uploads.single!.keys,
        unorderedEquals([
          'schemaVersion',
          'consentVersion',
          'completed',
          'easeCounts',
          'helpfulnessCounts',
          'issueCounts',
        ]),
      );
    },
  );
  test('failed uploads retry and opt-out cancels pending uploads', () async {
    var fail = true;
    var writes = 0;
    repository = BetaSurveyRepository(
      box,
      clock: () => clock,
      upload: (s) async {
        if (fail) throw StateError('offline');
        writes++;
      },
    );
    await repository.setSharing(true);
    await repository.save(day: repository.today, ease: 4, issue: 'none');
    expect(repository.pending, isTrue);
    fail = false;
    await repository.sync();
    expect(writes, 1);
    expect(repository.pending, isFalse);
    fail = true;
    await repository.save(day: repository.today, ease: 3, issue: 'audio');
    await repository.setSharing(false);
    fail = false;
    await repository.sync();
    expect(writes, 1);
  });
  test(
    'deletion survives failure and prevents re-enabling until confirmed',
    () async {
      var fail = true;
      repository = BetaSurveyRepository(
        box,
        clock: () => clock,
        upload: (s) async {
          expect(s, isNull);
          if (fail) throw StateError('offline');
        },
      );
      await repository.deleteShared();
      expect(repository.deletionPending, isTrue);
      await expectLater(repository.setSharing(true), throwsStateError);
      fail = false;
      await repository.sync();
      expect(repository.deletionPending, isFalse);
      expect(repository.sharing, isFalse);
    },
  );
  test(
    'deletion waits for an in-flight upload then removes the snapshot',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final calls = <Map<String, dynamic>?>[];
      repository = BetaSurveyRepository(
        box,
        clock: () => clock,
        upload: (s) async {
          calls.add(s);
          if (s != null) {
            started.complete();
            await gate.future;
          }
        },
      );
      await repository.setSharing(true);
      final saving = repository.save(
        day: repository.today,
        ease: 4,
        issue: 'none',
      );
      await started.future;
      await repository.deleteShared();
      gate.complete();
      await saving;
      expect(calls.length, 2);
      expect(calls.last, isNull);
      expect(repository.deletionPending, isFalse);
    },
  );
  test('skip suppresses repeat prompts until the next local day', () async {
    expect(repository.due, isTrue);
    await repository.skip(repository.today);
    expect(repository.due, isFalse);
    clock = clock.add(const Duration(days: 1));
    expect(repository.due, isTrue);
    await repository.setEnabled(false);
    expect(repository.due, isFalse);
  });
  test(
    'editing replaces a day and dismissing cannot erase its response',
    () async {
      await repository.save(day: repository.today, ease: 2, issue: 'audio');
      await repository.save(day: repository.today, ease: 4, issue: 'none');
      await repository.skip(repository.today);
      expect(repository.statistics['completed'], 1);
      expect(repository.responseFor(repository.today)?['ease'], 4);
      expect(repository.due, isFalse);
    },
  );
  test('averages exclude unrated answers and exports omit dates', () async {
    await repository.save(day: repository.today, ease: 2, issue: 'audio');
    clock = clock.add(const Duration(days: 1));
    await repository.save(
      day: repository.today,
      ease: 4,
      helpfulness: 5,
      issue: 'none',
    );
    final stats = repository.statistics;
    expect(stats['ease']['mean'], 3);
    expect(stats['ease']['n'], 2);
    expect(stats['helpfulness']['n'], 1);
    expect(stats['helpfulness']['mean'], 5);
    expect(
      repository.aggregateCsv(),
      contains('schema_version,beta-feedback-1'),
    );
    expect(repository.aggregateCsv(), isNot(contains('2026-')));
  });
  test('invalid or stale submissions do not write a response', () async {
    await expectLater(
      repository.save(day: repository.today, ease: 6, issue: 'none'),
      throwsArgumentError,
    );
    await expectLater(
      repository.save(day: '2020-01-01', issue: 'none'),
      throwsStateError,
    );
    await expectLater(
      repository.save(day: repository.today, issue: 'unknown'),
      throwsArgumentError,
    );
    expect(repository.days, isEmpty);
  });
  test(
    'encrypted responses survive reopening and deletion disables prompts',
    () async {
      await repository.save(
        day: repository.today,
        helpfulness: 3,
        issue: 'none',
      );
      await box.close();
      box = await Hive.openBox<dynamic>(
        'beta',
        encryptionCipher: HiveAesCipher(key),
      );
      repository = BetaSurveyRepository(box, clock: () => clock);
      expect(repository.statistics['completed'], 1);
      await box.put('unrelated', 'preserved');
      await repository.deleteResponses();
      expect(repository.days, isEmpty);
      expect(repository.enabled, isFalse);
      expect(box.get('unrelated'), 'preserved');
    },
  );
}
