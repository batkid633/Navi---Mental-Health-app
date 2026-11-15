import 'package:flutter_test/flutter_test.dart';
import 'package:navi_personal/services/export_sections.dart';

void main() {
  test('failed decryption preserves independent export sections', () async {
    final result = await collectExportSections({
      'journal': () async => throw StateError('private error contents'),
      'features': () async => [1, 2],
      'audio': () async => [],
    });
    expect(result['complete'], false);
    expect(result['data'], {
      'features': [1, 2],
      'audio': [],
    });
    expect(result['errors'], {'journal': 'unavailable_or_unreadable'});
  });
  test('empty readable section is distinct from a failed section', () async {
    final result = await collectExportSections({'journal': () async => []});
    expect(result['complete'], true);
    expect(result['errors'], isEmpty);
  });
}
