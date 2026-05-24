import 'dart:html' as html;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

Future<http.MultipartFile> platformAudioMultipartFileFromPath(String path) async {
  final response = await html.HttpRequest.request(
    path,
    responseType: 'arraybuffer',
  );
  final buffer = response.response as ByteBuffer;
  final bytes = buffer.asUint8List();
  return http.MultipartFile.fromBytes(
    'file',
    bytes,
    filename: _fileNameFromPath(path),
  );
}

String _fileNameFromPath(String path) {
  final uri = Uri.tryParse(path);
  final lastSegment = uri?.pathSegments.isNotEmpty == true
      ? uri!.pathSegments.last
      : path.split('/').last;
  if (lastSegment.trim().isEmpty || lastSegment.startsWith('blob:')) {
    return 'web-recording.wav';
  }
  return lastSegment;
}
