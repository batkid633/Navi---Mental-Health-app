import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';

class AudioAnalysisService {
  static Future<Map<String, dynamic>> analyzeAudio(
    dynamic audioFile, {
    String mode = 'emotional_venting',
  }) async {
    return {
      'error':
          'Audio analysis requires an on-device model while end-to-end encryption is enabled.',
      'mode': mode,
      'mood_analysis': null,
      'audio_features': null,
      'e2eeLocalOnly': true,
    };
  }

  static Future<Map<String, dynamic>> trainAudioModel(
    String trainingCsvPath,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('${BackendConfig.baseUrl}/audio/train'),
        headers: {
          ...await BackendConfig.getAuthHeaders(),
          'Content-Type': 'application/json',
        },
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
