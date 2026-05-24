import 'audio_bytes_io.dart'
    if (dart.library.html) 'audio_bytes_web.dart';

Future<List<int>> readAudioBytes(String path) {
  return platformReadAudioBytes(path);
}
