import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tomorrow_outlook.dart';
import '../config/backend_config.dart';

class MLPredictionService {
 static Future<TomorrowOutlook?> loadTomorrowOutlook({
  required String date,
  bool forceReload = false,
}) async {
  final response = await http.post(
    Uri.parse("${BackendConfig.baseUrl}/predict/tomorrow"),
    headers: await BackendConfig.getAuthHeaders(),
    body: jsonEncode({
      "date": date,
      "force_reload": forceReload,
    }),
  );

  if (response.statusCode != 200) return null;
  return TomorrowOutlook.fromJson(jsonDecode(response.body));
}
}
