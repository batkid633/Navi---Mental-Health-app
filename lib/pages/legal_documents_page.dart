import 'package:flutter/material.dart';

import '../legal/legal_content.dart';

class LegalDocumentsPage extends StatelessWidget {
  final int initialTabIndex;

  const LegalDocumentsPage({super.key, this.initialTabIndex = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTabIndex.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Legal'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Privacy'),
              Tab(text: 'Terms'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _LegalDocumentView(
              title: LegalContent.privacyPolicyTitle,
              version: LegalContent.privacyPolicyVersion,
              sections: LegalContent.privacyPolicySections,
            ),
            _LegalDocumentView(
              title: LegalContent.termsTitle,
              version: LegalContent.termsVersion,
              sections: LegalContent.termsSections,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalDocumentView extends StatelessWidget {
  final String title;
  final String version;
  final List<LegalSection> sections;

  const _LegalDocumentView({
    required this.title,
    required this.version,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(title, style: textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Effective ${LegalContent.effectiveDate} | Version $version',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final section in sections) ...[
            Text(
              section.title,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(section.body),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}
