import 'audio_multipart_io.dart'
    if (dart.library.html) 'audio_multipart_web.dart';
import 'package:http/http.dart' as http;

Future<http.MultipartFile> audioMultipartFileFromPath(String path) {
  return platformAudioMultipartFileFromPath(path);
}
