import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:navi_personal/models/journal_entry.dart';
import 'package:navi_personal/services/local_research_repository.dart';

void main() {
  late Directory temporary;
  late Box<dynamic> box;
  late LocalResearchRepository repository;
  late DateTime clock;
  final key = List<int>.generate(32, (i) => i);
  JournalEntry journal(String id, DateTime date) =>
      JournalEntry(id: id, date: date, text: 'PRIVATE FIXTURE TEXT');

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('navi_research_test_');
    Hive.init(temporary.path);
    box = await Hive.openBox<dynamic>(
      'research_fixture',
      encryptionCipher: HiveAesCipher(key),
    );
    clock = DateTime.utc(2026, 9, 13, 12);
    repository = LocalResearchRepository(box, clock: () => clock);
  });
  tearDown(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });

  test('default off does not capture or create consent', () async {
    await repository.collect(journals: [journal('private-id', clock)]);
    expect(repository.enabled, isFalse);
    expect(repository.rowCount, 0);
    expect(box.containsKey('state'), isFalse);
  });

  test(
    'consent excludes history and packet contains no source identifiers or text',
    () async {
      final old = journal('old', clock.subtract(const Duration(days: 1)));
      await repository.setEnabled(true);
      clock = clock.add(const Duration(minutes: 1));
      await repository.collect(journals: [old, journal('private-id', clock)]);
      final packet = repository.reviewPacket();
      expect((packet['records'] as List).single['journal_count'], 1);
      final encoded = jsonEncode(packet);
      expect(encoded, isNot(contains('PRIVATE FIXTURE TEXT')));
      expect(encoded, isNot(contains('private-id')));
      expect(encoded, isNot(contains('2026-09')));
    },
  );

  test('pause and resume never backfill the paused interval', () async {
    await repository.setEnabled(true);
    final first = journal('first', clock);
    clock = clock.add(const Duration(hours: 1));
    await repository.setEnabled(false);
    final paused = journal('paused', clock.add(const Duration(minutes: 1)));
    clock = clock.add(const Duration(hours: 1));
    await repository.collect(journals: [first, paused]);
    expect(repository.rowCount, 0);
    await repository.setEnabled(true);
    final resumed = journal('resumed', clock);
    await repository.collect(journals: [first, paused, resumed]);
    expect(
      (repository.reviewPacket()['records'] as List).single['journal_count'],
      2,
    );
  });

  test('collection is idempotent and survives encrypted reopen', () async {
    await repository.setEnabled(true);
    final event = journal('one', clock);
    await repository.collect(journals: [event, event]);
    await repository.collect(journals: [event]);
    final before = repository.reviewPacket();
    await box.close();
    box = await Hive.openBox<dynamic>(
      'research_fixture',
      encryptionCipher: HiveAesCipher(key),
    );
    repository = LocalResearchRepository(box, clock: () => clock);
    expect(repository.reviewPacket(), before);
    expect((before['records'] as List).single['journal_count'], 1);
  });

  test(
    'delete pauses collection and leaves unrelated storage intact',
    () async {
      final unrelated = await Hive.openBox<String>('original_fixture');
      await unrelated.put('journal', 'keep');
      await repository.setEnabled(true);
      await repository.collect(journals: [journal('one', clock)]);
      await repository.deleteResearchCopy();
      expect(repository.rowCount, 0);
      expect(repository.enabled, isFalse);
      expect(repository.reviewPacket()['participant_code'], isNull);
      expect(unrelated.get('journal'), 'keep');
    },
  );
}
