import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class CrisisResourcesCard extends StatelessWidget {
  final bool compact;

  const CrisisResourcesCard({super.key, this.compact = false});

  Future<void> _launch(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.errorContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.health_and_safety, color: colorScheme.error),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Navi is not emergency care',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              compact
                  ? 'If you might act on thoughts of harming yourself or someone else, call 911 now. For 24/7 crisis support in the U.S., call or text 988.'
                  : 'Navi can support reflection, but it does not monitor emergencies, provide diagnosis, or replace professional care. If you might act on thoughts of harming yourself or someone else, call 911 now. For 24/7 crisis support in the U.S., call or text 988, or chat at 988lifeline.org.',
            ),
            if (!compact) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _launch(Uri(scheme: 'tel', path: '988')),
                    icon: const Icon(Icons.call),
                    label: const Text('Call 988'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _launch(Uri(scheme: 'sms', path: '988')),
                    icon: const Icon(Icons.sms),
                    label: const Text('Text 988'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _launch(Uri.parse('https://988lifeline.org/chat/')),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('988 chat'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
