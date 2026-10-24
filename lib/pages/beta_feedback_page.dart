import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/beta_survey_repository.dart';

Future<void> showBetaSurvey(
  BuildContext context,
  BetaSurveyRepository repository,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SurveyDialog(repository: repository),
);

class _SurveyDialog extends StatefulWidget {
  final BetaSurveyRepository repository;
  const _SurveyDialog({required this.repository});
  @override
  State<_SurveyDialog> createState() => _SurveyDialogState();
}

class _SurveyDialogState extends State<_SurveyDialog> {
  int? ease;
  int? helpfulness;
  String issue = 'none';
  bool busy = false;
  String? error;
  late final String day = widget.repository.today;
  Future<void> finish(bool submit) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (submit) {
        await widget.repository.save(
          day: day,
          ease: ease,
          helpfulness: helpfulness,
          issue: issue,
        );
      } else {
        await widget.repository.skip(day);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error =
              'Could not save. If the date changed, skip and reopen from Settings.';
        });
    }
  }

  Widget rating(String title, int? value, ValueChanged<int?> change) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      Wrap(
        spacing: 6,
        children: [
          for (var i = 1; i <= 5; i++)
            ChoiceChip(
              label: Text('$i'),
              selected: value == i,
              onSelected: busy ? null : (_) => change(i),
            ),
          ChoiceChip(
            label: const Text('Not used'),
            selected: value == null,
            onSelected: busy ? null : (_) => change(null),
          ),
        ],
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Daily beta feedback'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Optional: reflect on your most recent NAVI use. Responses stay encrypted on this device; nothing is uploaded. Saving agrees to local storage. You can disable reminders or delete responses in Settings.',
            ),
            const SizedBox(height: 12),
            rating(
              'How easy was NAVI to use?\n1 = very difficult · 5 = very easy',
              ease,
              (v) => setState(() => ease = v),
            ),
            const SizedBox(height: 12),
            rating(
              'How helpful was NAVI?\n1 = not helpful · 5 = very helpful',
              helpfulness,
              (v) => setState(() => helpfulness = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: issue,
              decoration: const InputDecoration(
                labelText: 'Main issue, if any',
              ),
              items: [
                for (final v in BetaSurveyRepository.issues)
                  DropdownMenuItem(
                    value: v,
                    child: Text(v.replaceAll('_', ' ')),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() => issue = v ?? 'none'),
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => finish(false),
          child: const Text('Skip today'),
        ),
        FilledButton(
          onPressed: busy ? null : () => finish(true),
          child: Text(busy ? 'Saving…' : 'Save locally'),
        ),
      ],
    ),
  );
}

class BetaFeedbackPage extends StatefulWidget {
  final BetaSurveyRepository repository;
  const BetaFeedbackPage({super.key, required this.repository});
  @override
  State<BetaFeedbackPage> createState() => _BetaFeedbackPageState();
}

class _BetaFeedbackPageState extends State<BetaFeedbackPage> {
  String? message;
  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      message = 'Could not complete this action.';
    }
    if (mounted) setState(() {});
  }

  Future<void> delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete local beta responses?'),
        content: const Text(
          'This also disables daily survey prompts. Journals and other data are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) await perform(widget.repository.deleteResponses);
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.repository.statistics;
    return Scaffold(
      appBar: AppBar(title: const Text('Beta feedback & statistics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'This account on this device only. Repeated responses are not unique participants. These are usability observations, not clinical outcomes or evidence of effectiveness.',
          ),
          SwitchListTile(
            title: const Text('Offer survey on first use each day'),
            value: widget.repository.enabled,
            onChanged: (v) => perform(() => widget.repository.setEnabled(v)),
          ),
          FilledButton(
            onPressed: () =>
                perform(() => showBetaSurvey(context, widget.repository)),
            child: const Text('Answer or edit today’s survey'),
          ),
          Text(
            '${stats['completed']} completed days · ${stats['skipped']} skipped days',
          ),
          const Text(
            'Days when NAVI was not opened are not counted. “Not used” ratings are excluded from averages.',
          ),
          for (final metric in ['ease', 'helpfulness']) ...[
            const SizedBox(height: 16),
            Text(
              '${metric == 'ease' ? 'Ease of use' : 'Helpfulness'}: n=${(stats[metric] as Map)['n']}, mean=${((stats[metric] as Map)['mean'] as double?)?.toStringAsFixed(2) ?? '—'} / 5',
            ),
            for (var i = 0; i < 5; i++)
              Row(
                children: [
                  SizedBox(width: 45, child: Text('${i + 1} / 5')),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (stats[metric] as Map)['n'] == 0
                          ? 0
                          : ((stats[metric] as Map)['counts'] as List)[i] /
                                (stats[metric] as Map)['n'],
                    ),
                  ),
                  SizedBox(
                    width: 35,
                    child: Text(
                      '  ${((stats[metric] as Map)['counts'] as List)[i]}',
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: 16),
          const Text('Reported issues (one selection per completed day)'),
          for (final e in (stats['issues'] as Map).entries)
            Text('${e.key}: ${e.value}'),
          OutlinedButton(
            onPressed: () => perform(() async {
              await Clipboard.setData(
                ClipboardData(text: widget.repository.aggregateCsv()),
              );
              message =
                  'Aggregate CSV copied. Clipboard content can be accessed outside NAVI; review before sharing.';
            }),
            child: const Text('Copy aggregate CSV for charts'),
          ),
          TextButton(
            onPressed: delete,
            child: const Text('Delete local beta responses'),
          ),
          if (message != null) Text(message!),
        ],
      ),
    );
  }
}
