import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/insight_trend.dart';
import '../models/model_validation_report.dart';
import '../config/backend_config.dart';

class InsightsApi {
  static Future<List<InsightTrend>> fetchTrends(int days) async {
    final uri = Uri.parse(
      '${BackendConfig.baseUrl}/insights/trends?days=$days',
    );
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

  static Future<ModelValidationReport> fetchValidationReport() async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/model/validation-report');
    final res = await http.get(
      uri,
      headers: await BackendConfig.getAuthHeaders(),
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Failed to load model validation report: HTTP ${res.statusCode}',
      );
    }

    final body = json.decode(res.body) as Map<String, dynamic>;
    return ModelValidationReport.fromJson(body);
  }
}
