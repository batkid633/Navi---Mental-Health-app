import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/backend_config.dart';

class SentimentService {
  static Future<Map<String, dynamic>> analyze(String text) async {
    try {
      final response = await http
          .post(
            Uri.parse('${BackendConfig.baseUrl}/sentiment'),
            headers: await BackendConfig.getAuthHeaders(),
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final compound = _doubleFrom(body['compound'] ?? body['sentiment']);
          final label = body['label']?.toString() ?? _labelFrom(compound);
          return {
            ...body,
            'compound': compound,
            'label': label,
            'source': body['source']?.toString() ?? 'backend',
          };
        }
      }

      return _localFallback(
        text,
        fallbackReason: 'backend_status_${response.statusCode}',
        backendStatusCode: response.statusCode,
      );
    } on TimeoutException {
      return _localFallback(text, fallbackReason: 'backend_timeout');
    } catch (e) {
      return _localFallback(
        text,
        fallbackReason: 'backend_error:${e.runtimeType}',
      );
    }
  }

  static double _doubleFrom(dynamic value) {
    if (value is num) {
      return value.toDouble().clamp(-1.0, 1.0).toDouble();
    }
    return (double.tryParse(value?.toString() ?? '') ?? 0.0)
        .clamp(-1.0, 1.0)
        .toDouble();
  }

  static String _labelFrom(double compound) {
    if (compound >= 0.05) {
      return 'positive';
    }
    if (compound <= -0.05) {
      return 'negative';
    }
    return 'neutral';
  }

  static Map<String, dynamic> _localFallback(
    String text, {
    required String fallbackReason,
    int? backendStatusCode,
  }) {
    const positiveWords = {
      'good',
      'great',
      'happy',
      'calm',
      'hopeful',
      'better',
      'grateful',
      'proud',
      'relieved',
      'peaceful',
      'excited',
      'love',
      'safe',
    };
    const negativeWords = {
      'bad',
      'sad',
      'angry',
      'anxious',
      'worse',
      'awful',
      'hopeless',
      'tired',
      'scared',
      'stressed',
      'overwhelmed',
      'lonely',
      'hate',
    };

    final words = RegExp(r"[a-zA-Z']+")
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0) ?? '')
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      final result = {
        'compound': 0.0,
        'label': 'neutral',
        'source': 'local_fallback',
        'fallbackReason': fallbackReason,
      };
      if (backendStatusCode != null) {
        result['backendStatusCode'] = backendStatusCode;
      }
      return result;
    }

    var score = 0;
    for (final word in words) {
      if (positiveWords.contains(word)) score++;
      if (negativeWords.contains(word)) score--;
    }

    final compound = (score / words.length).clamp(-1.0, 1.0);
    final label = compound > 0.05
        ? 'positive'
        : compound < -0.05
        ? 'negative'
        : 'neutral';

    final result = {
      'compound': compound,
      'label': label,
      'source': 'local_fallback',
      'fallbackReason': fallbackReason,
    };
    if (backendStatusCode != null) {
      result['backendStatusCode'] = backendStatusCode;
    }
    return result;
  }
}
