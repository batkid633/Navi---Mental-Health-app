import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tomorrow_outlook.dart';

class MLPredictionService {
 static Future<TomorrowOutlook?> loadTomorrowOutlook({
  required String date,
  bool force_reload = false,
}) async {
  final response = await http.post(
    Uri.parse("http://127.0.0.1:8000/predict/tomorrow"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "date": date,
      "force_reload": force_reload,
    }),
  );

  if (response.statusCode != 200) return null;
  return TomorrowOutlook.fromJson(jsonDecode(response.body));
}
}
