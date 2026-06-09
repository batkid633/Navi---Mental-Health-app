class SentimentService {
  static Future<Map<String, dynamic>> analyze(String text) async {
    return _localFallback(text, fallbackReason: 'e2ee_local_default');
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
