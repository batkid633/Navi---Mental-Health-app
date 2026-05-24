import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';

class SentimentService {

  static Future<Map<String, dynamic>> analyze(String text) async {
    try {
      final response = await http.post(
        Uri.parse("${BackendConfig.baseUrl}/sentiment"),
        headers: await BackendConfig.getAuthHeaders(),
        body: jsonEncode({"text": text}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {
      // Fall through to lightweight local scoring so offline/local testing
      // still produces usable journal data.
    }

    return _localFallback(text);
  }

  static Map<String, dynamic> _localFallback(String text) {
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
      return {'compound': 0.0, 'label': 'neutral', 'source': 'local'};
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

    return {'compound': compound, 'label': label, 'source': 'local'};
  }
}
