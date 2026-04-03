import 'dart:convert';
import 'package:http/http.dart' as http;

class SentimentService {
  static const String _baseUrl = "http://127.0.0.1:8000";

  static Future<Map<String, dynamic>> analyze(String text) async {
    final response = await http.post(
      Uri.parse("$_baseUrl/sentiment"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"text": text}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Sentiment analysis failed");
    }
  }
}
