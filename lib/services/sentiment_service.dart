import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/backend_config.dart';

class SentimentService {

  static Future<Map<String, dynamic>> analyze(String text) async {
    final response = await http.post(
      Uri.parse("${BackendConfig.baseUrl}/sentiment"),
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
