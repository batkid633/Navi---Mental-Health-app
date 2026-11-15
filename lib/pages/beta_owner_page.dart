import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/beta_feedback_cloud.dart';
import '../services/beta_survey_repository.dart';

class BetaOwnerPage extends StatefulWidget {
  const BetaOwnerPage({super.key});
  @override
  State<BetaOwnerPage> createState() => _BetaOwnerPageState();
}

class _BetaOwnerPageState extends State<BetaOwnerPage> {
  List<Map<String, dynamic>>? rows;
  String? error;
  bool loading = false;
  StreamSubscription<User?>? _authSubscription;
  String? _loadedUid;
  @override
  void initState() {
    super.initState();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (mounted && user?.uid != _loadedUid) setState(() => rows = null);
    });
    load();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      rows = null;
      error = null;
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _loadedUid = uid;
    try {
      if (uid == null) throw StateError('Sign in');
      final result = await BetaFeedbackCloud(uid).ownerSnapshots();
      if (mounted && FirebaseAuth.instance.currentUser?.uid == uid) {
        setState(() => rows = result);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Owner access is required. If your account is authorized, check connectivity and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = rows ?? [];
    final completed = data.fold<int>(
      0,
      (sum, r) => sum + (r['completed'] as int),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Owner beta statistics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Consented cloud snapshots only. Account counts are not verified unique people. Results describe self-selected usability responses, not clinical outcomes or effectiveness. One device per account; latest uploaded snapshot wins.',
          ),
          TextButton(
            onPressed: loading ? null : load,
            child: const Text('Refresh'),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (rows != null) ...[
            Text(
              '${data.length} contributing accounts · $completed completed response-days',
            ),
            for (final field in ['ease', 'helpfulness', 'issue']) ...[
              const SizedBox(height: 20),
              Builder(
                builder: (_) {
                  final counts = List<int>.generate(
                    field == 'issue' ? 6 : 5,
                    (i) => data.fold<int>(
                      0,
                      (sum, r) => sum + (r['${field}Counts'][i] as int),
                    ),
                  );
                  final n = counts.fold<int>(0, (a, b) => a + b);
                  final mean = n == 0
                      ? '—'
                      : (List.generate(
                                  counts.length,
                                  (i) => (i + 1) * counts[i],
                                ).fold<int>(0, (a, b) => a + b) /
                                n)
                            .toStringAsFixed(2);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field == 'issue'
                            ? 'Reported issues · n=$n'
                            : '$field · n=$n · mean=$mean / 5 · unrated=${completed - n}',
                      ),
                      for (var i = 0; i < counts.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 100,
                                child: Text(
                                  field == 'issue'
                                      ? BetaSurveyRepository.issues[i]
                                            .replaceAll('_', ' ')
                                      : '${i + 1} / 5',
                                ),
                              ),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: n == 0 ? 0 : counts[i] / n,
                                ),
                              ),
                              SizedBox(width: 45, child: Text(' ${counts[i]}')),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            const Text(
              'Means are response-weighted; frequent respondents contribute more. “Not used” is excluded. No dates or individual identities are shown. Review small-group counts before sharing screenshots.',
            ),
          ],
        ],
      ),
    );
  }
}
