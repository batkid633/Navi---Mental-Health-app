import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:navi_personal/models/journal_entry.dart';
import 'package:navi_personal/pages/journal_page.dart';
import 'package:navi_personal/services/data_service.dart';
import 'package:navi_personal/services/settings_service.dart';

// Keep storage loading so these input tests never initialize Firebase or sync.
class _LocalDataService extends DataService {
  final _journal = Completer<Box<JournalEntry>>();

  @override
  Future<Box<JournalEntry>> getJournalBox() => _journal.future;
}

void main() {
  late Directory temporaryDirectory;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'navi_keyboard_',
    );
    Hive.init(temporaryDirectory.path);
    await SettingsService.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> showJournal(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          appBar: AppBar(title: const Text('Navi')),
          body: JournalPage(dataService: _LocalDataService()),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Today'),
              NavigationDestination(
                icon: Icon(Icons.edit),
                label: 'Journal tab',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('hide keyboard preserves the multiline journal draft', (
    tester,
  ) async {
    await showJournal(tester);
    const draft = 'First thought\nSecond thought';
    await tester.enterText(find.byType(TextField), draft);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byTooltip('Hide keyboard'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text(draft), findsOneWidget);

    await tester.showKeyboard(find.byType(TextField));
    await tester.tap(find.text('Journal'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text(draft), findsOneWidget);
  });

  testWidgets('long draft fits with an iPhone-sized keyboard inset', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await showJournal(tester);
    await tester.enterText(
      find.byType(TextField),
      List.filled(30, 'A thought').join('\n'),
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Hide keyboard').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Hide keyboard'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
