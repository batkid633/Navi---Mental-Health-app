import 'package:http/http.dart' as http;

Future<http.MultipartFile> platformAudioMultipartFileFromPath(String path) {
  return http.MultipartFile.fromPath(
    'file',
    path,
    filename: path.split('/').last,
  );
}
