import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

/// Direct requests deliberately avoid Firestore's persistent offline write queue:
/// consent is checked in the encrypted local outbox before each request.
class BetaFeedbackCloud {
  final String uid;
  BetaFeedbackCloud(this.uid);
  String get root =>
      'https://firestore.googleapis.com/v1/projects/${Firebase.app().options.projectId}/databases/(default)/documents';

  Future<http.Response> _request(
    String method,
    String path, [
    Object? data,
  ]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) throw StateError('Account changed');
    final token = await user.getIdToken();
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('Account changed');
    }
    final client = http.Client();
    try {
      final request = http.Request(method, Uri.parse('$root/$path'));
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });
      if (data != null) request.body = jsonEncode(data);
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (method == 'DELETE' && response.statusCode == 404) return response;
        throw StateError(
          'Beta feedback request failed (${response.statusCode})',
        );
      }
      return response;
    } finally {
      client.close();
    }
  }

  static Map<String, dynamic> encode(Object value) {
    if (value is int) return {'integerValue': value.toString()};
    if (value is String) return {'stringValue': value};
    if (value is List) {
      return {
        'arrayValue': {
          'values': value.map((v) => encode(v as Object)).toList(),
        },
      };
    }
    throw ArgumentError('Unsupported feedback value');
  }

  static dynamic decode(Map value) {
    if (value.containsKey('integerValue')) {
      return int.parse(value['integerValue'] as String);
    }
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('arrayValue')) {
      return ((value['arrayValue'] as Map)['values'] as List? ?? [])
          .map((v) => decode(v as Map))
          .toList();
    }
    throw FormatException('Unexpected feedback value');
  }

  Future<void> upload(Map<String, dynamic>? snapshot) async {
    final path = 'beta_feedback_snapshots/${Uri.encodeComponent(uid)}';
    if (snapshot == null) {
      await _request('DELETE', path);
    } else {
      await _request('PATCH', path, {
        'fields': snapshot.map((k, v) => MapEntry(k, encode(v as Object))),
      });
    }
  }

  Future<List<Map<String, dynamic>>> ownerSnapshots() async {
    final result = <Map<String, dynamic>>[];
    String? page;
    do {
      final response = await _request(
        'GET',
        'beta_feedback_snapshots?pageSize=100${page == null ? '' : '&pageToken=${Uri.encodeComponent(page)}'}',
      );
      final body = jsonDecode(response.body) as Map;
      for (final doc in body['documents'] as List? ?? []) {
        result.add(
          (doc['fields'] as Map).map(
            (k, v) => MapEntry(k as String, decode(v as Map)),
          ),
        );
      }
      page = body['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty);
    return result;
  }
}
