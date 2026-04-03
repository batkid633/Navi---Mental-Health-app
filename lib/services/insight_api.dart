import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import '../models/insight_trend.dart';

class InsightsApi {
  static Future<List<InsightTrend>> fetchTrends(int days) async {
    // On Android emulators, `127.0.0.1` refers to the emulator itself.
    // Use `10.0.2.2` to reach the host machine. For web/iOS/desktop, use localhost.
    String base;
    if (kIsWeb) {
      base = 'http://127.0.0.1:8000';
    } else {
      try {
        if (Platform.isAndroid) {
          base = 'http://10.0.2.2:8000';
        } else {
          base = 'http://127.0.0.1:8000';
        }
      } catch (e) {
        base = 'http://127.0.0.1:8000';
      }
    }

    final uri = Uri.parse('$base/insights/trends?days=$days');
    final res = await http.get(uri);

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
