import 'dart:html';
import 'package:uuid/uuid.dart';

Future<String> getRecordingPath(Uuid uuid) async {
  // Use a browser-safe pseudo-path for recording metadata storage.
  // Actual media capture is handled through the browser APIs and `record`.
  return 'web_recording_${uuid.v4()}.wav';
}
