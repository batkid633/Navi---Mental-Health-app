import 'package:flutter/material.dart';

Future<bool> requestAudioAnalysisConsent(
  BuildContext context,
  Uri endpoint,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Send this recording for analysis?'),
          content: Text(
            'This sends the selected recording to NAVI’s backend at ${endpoint.host} for this analysis attempt. '
            'The connection is encrypted, but the server must read your audio; this processing is not end-to-end encrypted. '
            'The backend code uses a temporary audio file and attempts to remove it after processing. '
            'Results may use an experimental acoustic heuristic, not a validated mood assessment. '
            'A trained-model result may be saved with your entry and used in insights. '
            'Cancel keeps this recording out of the analysis request. You will be asked again for each attempt.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send this recording'),
            ),
          ],
        ),
      ) ??
      false;
}
