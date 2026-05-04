import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';

class AudioAnalysisService {
  static Future<Map<String, dynamic>> analyzeAudio(File audioFile, {String mode = 'emotional_venting'}) async {
    try {
      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${BackendConfig.baseUrl}/audio/analyze'),
      );

      // Add audio file
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          audioFile.path,
          filename: audioFile.path.split('/').last,
        ),
      );

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
        headers: {'Content-Type': 'application/json'},
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