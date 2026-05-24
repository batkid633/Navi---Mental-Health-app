import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/insight_trend.dart';
import '../config/backend_config.dart';

class InsightsApi {
  static Future<List<InsightTrend>> fetchTrends(int days) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/insights/trends?days=$days');
    final res = await http.get(
      uri,
      headers: await BackendConfig.getAuthHeaders(),
    );

    if (res.statusCode != 200) {
      throw Exception('Failed to load insight trends: HTTP ${res.statusCode}');
    }

    final body = json.decode(res.body);

    // Check if the response contains an error
    if (body.containsKey('error')) {
      throw Exception('Backend error: ${body['error']}');
    }

    final List data = body['data'];

    return data.map((e) => InsightTrend.fromJson(e)).toList();
  }
}
