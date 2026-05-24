import 'dart:html' as html;
import 'dart:typed_data';

Future<List<int>> platformReadAudioBytes(String path) async {
  final response = await html.HttpRequest.request(
    path,
    responseType: 'arraybuffer',
  );
  final buffer = response.response as ByteBuffer;
  return buffer.asUint8List();
}
