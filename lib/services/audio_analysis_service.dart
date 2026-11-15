import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';
import '../utils/audio_multipart.dart';

class AudioAnalysisService {
  static Future<Map<String, dynamic>> analyzeAudio(
    String audioPath, {
    String mode = 'emotional_venting',
    bool consentGranted = false,
    Uri? endpoint,
    http.Client? client,
    Future<Map<String, String>> Function()? authHeaders,
    Future<http.MultipartFile> Function(String)? loadFile,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    // No file access, authentication, or networking before explicit consent.
    if (!consentGranted) {
      return {'error': 'Permission is required for this recording.'};
    }
    if (!['emotional_venting', 'deeper_analysis'].contains(mode)) {
      return {'error': 'Unsupported analysis mode.'};
    }
    final uri = endpoint ?? Uri.parse('${BackendConfig.baseUrl}/audio/analyze');
    if (uri.scheme != 'https') {
      return {'error': 'Audio analysis requires a secure HTTPS backend.'};
    }
    final transport = client ?? http.Client();
    try {
      final headers = await (authHeaders ?? BackendConfig.getAuthHeaders)();
      if (!(headers['Authorization'] ?? '').startsWith('Bearer ')) {
        return {'error': 'Sign in again before analyzing this recording.'};
      }
      final file = await (loadFile ?? audioMultipartFileFromPath)(audioPath);
      if (file.length == 0) return {'error': 'This recording is empty.'};
      if (file.length > 25 * 1024 * 1024) {
        return {
          'error':
              'This recording exceeds the 25 MB analysis limit. Try a shorter recording.',
        };
      }
      final request = http.MultipartRequest('POST', uri)
        ..followRedirects = false
        ..fields['mode'] = mode
        ..headers.addAll(
          Map.fromEntries(
            headers.entries.where((e) => e.key.toLowerCase() != 'content-type'),
          ),
        )
        ..files.add(
          http.MultipartFile(
            'file',
            file.finalize(),
            file.length,
            filename: 'recording.wav',
            contentType: file.contentType,
          ),
        );
      // No automatic retries: every new attempt requires fresh UI consent.
      final response = await transport
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (response.statusCode != 200) {
        return {
          'error': switch (response.statusCode) {
            401 ||
            403 => 'Your session is not authorized. Sign in again and retry.',
            413 =>
              'The backend rejected the recording size. Try a shorter recording.',
            415 => 'The backend does not support this recording format.',
            429 => 'Too many requests. Wait before trying again.',
            _ =>
              'Audio analysis is unavailable (HTTP ${response.statusCode}). Your recording is still saved.',
          },
        };
      }
      final result = jsonDecode(response.body);
      if (result is! Map<String, dynamic> ||
          result.containsKey('error') ||
          result['mood_analysis'] is! Map ||
          result['audio_features'] is! Map ||
          (result['mood_analysis'] as Map).containsKey('error') ||
          (result['audio_features'] as Map).containsKey('error')) {
        return {
          'error':
              'The backend could not analyze this recording. It remains saved.',
        };
      }
      return result;
    } on TimeoutException {
      return {
        'error':
            'Analysis timed out. The server may still finish processing. Your recording remains saved; retrying requires permission again.',
      };
    } catch (_) {
      return {
        'error':
            'Could not read or analyze this recording. Check its availability and your connection.',
      };
    } finally {
      if (client == null) transport.close();
    }
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
