import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> saveDataExport(String json) async {
  final directory = await getApplicationDocumentsDirectory();
  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final file = File('${directory.path}/navi-data-export-$timestamp.json');
  await file.writeAsString(json);
  return file.path;
}
