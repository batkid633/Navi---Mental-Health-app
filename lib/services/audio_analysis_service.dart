import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';
import '../utils/audio_multipart.dart';

class AudioAnalysisService {
  static Future<Map<String, dynamic>> analyzeAudio(dynamic audioFile, {String mode = 'emotional_venting'}) async {
    try {
      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${BackendConfig.baseUrl}/audio/analyze'),
      );
      request.headers.addAll(await BackendConfig.getAuthHeaders());

      // Add audio file
      final audioPath = audioFile is String ? audioFile : audioFile.path as String;
      request.files.add(await audioMultipartFileFromPath(audioPath));

      // Add mode parameter
      request.fields['mode'] = mode;

      // Send request
      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var jsonResponse = json.decode(responseData);

      if (response.statusCode == 200) {
        return jsonResponse;
      } else {
        throw Exception('Analysis failed: ${jsonResponse['detail'] ?? responseData}');
      }
    } catch (e) {
      return {
        'error': 'Failed to analyze audio: $e',
        'mood_analysis': null,
        'audio_features': null
      };
    }
  }

  static Future<Map<String, dynamic>> trainAudioModel(String trainingCsvPath) async {
    try {
      final response = await http.post(
        Uri.parse('${BackendConfig.baseUrl}/audio/train'),
        headers: await BackendConfig.getAuthHeaders(),
        body: json.encode({'training_csv_path': trainingCsvPath}),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Training failed: ${response.body}');
      }
    } catch (e) {
      return {'error': 'Failed to train model: $e'};
    }
  }
}
