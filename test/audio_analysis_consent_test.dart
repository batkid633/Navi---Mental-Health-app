import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navi_personal/widgets/audio_analysis_consent.dart';

void main() {
  testWidgets('consent is explicit and is asked again for another attempt', (
    tester,
  ) async {
    final decisions = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => decisions.add(
                await requestAudioAnalysisConsent(
                  context,
                  Uri.parse('https://example.invalid/audio/analyze'),
                ),
              ),
              child: const Text('Analyze'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not end-to-end encrypted'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(decisions, [false]);
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Send this recording'));
    await tester.tap(find.text('Send this recording'));
    await tester.pumpAndSettle();
    expect(decisions, [false, true]);
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();
    expect(find.text('Send this recording'), findsOneWidget);
  });
}
