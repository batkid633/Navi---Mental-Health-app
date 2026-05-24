import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

Future<String> getRecordingPath(Uuid uuid) async {
  final baseDirectory = await _getBaseDirectory();
  final audioDir = Directory('${baseDirectory.path}/audio');
  if (!await audioDir.exists()) {
    await audioDir.create(recursive: true);
  }
  final fileName = '${uuid.v4()}.wav';
  return '${audioDir.path}/$fileName';
}

Future<Directory> _getBaseDirectory() async {
  try {
    return await getApplicationDocumentsDirectory();
  } catch (_) {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return await getTemporaryDirectory();
    }
  }
}
