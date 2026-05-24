import 'dart:io';

Future<List<int>> platformReadAudioBytes(String path) {
  return File(path).readAsBytes();
}
