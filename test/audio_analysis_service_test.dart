import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navi_personal/services/audio_analysis_service.dart';

void main() {
  final endpoint = Uri.parse('https://example.invalid/audio/analyze');
  Future<Map<String, String>> auth() async => {
    'Authorization': 'Bearer fixture',
    'Content-Type': 'application/json',
  };
  Future<http.MultipartFile> file(String _) async =>
      http.MultipartFile.fromBytes('file', [
        82,
        73,
        70,
        70,
      ], filename: 'private-name.wav');
  test('no consent means no file, authentication, or network access', () async {
    final result = await AudioAnalysisService.analyzeAudio(
      'private-path',
      authHeaders: () async => throw StateError('Must not authenticate'),
      loadFile: (_) async => throw StateError('Must not read'),
      client: MockClient((_) async => throw StateError('Must not upload')),
    );
    expect(result['error'], contains('Permission'));
  });
  test(
    'consented request uses authenticated multipart, mode and generic filename',
    () async {
      final client = MockClient((request) async {
        expect(request.url, endpoint);
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer fixture');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );
        expect(request.body, contains('deeper_analysis'));
        expect(request.body, contains('filename="recording.wav"'));
        expect(request.body, isNot(contains('private-name')));
        return http.Response(
          jsonEncode({
            'mood_analysis': {
              'predicted_mood': 'neutral',
              'model_status': 'heuristic_fallback',
            },
            'audio_features': {'rms_energy': 0.01},
          }),
          200,
        );
      });
      final result = await AudioAnalysisService.analyzeAudio(
        'fixture',
        consentGranted: true,
        endpoint: endpoint,
        mode: 'deeper_analysis',
        authHeaders: auth,
        loadFile: file,
        client: client,
      );
      expect(result.containsKey('error'), isFalse);
      client.close();
    },
  );
  test(
    'HTTP and malformed success responses never count as successful analysis',
    () async {
      for (final response in [
        http.Response('private server details', 500),
        http.Response('{}', 200),
        http.Response(
          '{"mood_analysis":{"error":"private"},"audio_features":{}}',
          200,
        ),
        http.Response('not json', 200),
      ]) {
        final client = MockClient((_) async => response);
        final result = await AudioAnalysisService.analyzeAudio(
          'fixture',
          consentGranted: true,
          endpoint: endpoint,
          authHeaders: auth,
          loadFile: file,
          client: client,
        );
        expect(result['error'], isA<String>());
        expect(result['error'], isNot(contains('private')));
        client.close();
      }
    },
  );
  test('empty and oversized recordings are rejected before upload', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    for (final size in [0, 25 * 1024 * 1024 + 1]) {
      final result = await AudioAnalysisService.analyzeAudio(
        'fixture',
        consentGranted: true,
        endpoint: endpoint,
        authHeaders: auth,
        client: client,
        loadFile: (_) async =>
            http.MultipartFile('file', const Stream<List<int>>.empty(), size),
      );
      expect(result['error'], isA<String>());
    }
    expect(requests, 0);
    client.close();
  });
  test('timeout reports uncertainty and does not retry', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response('{}', 200);
    });
    final result = await AudioAnalysisService.analyzeAudio(
      'fixture',
      consentGranted: true,
      endpoint: endpoint,
      authHeaders: auth,
      loadFile: file,
      client: client,
      timeout: const Duration(milliseconds: 1),
    );
    expect(result['error'], contains('timed out'));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(requests, 1);
    client.close();
  });
}
