import 'package:flutter/material.dart';

import '../services/data_service.dart';
import '../services/settings_service.dart';
import 'legal_documents_page.dart';
import '../widgets/crisis_resources_card.dart';

class OnboardingConsentPage extends StatefulWidget {
  final DataService dataService;
  final VoidCallback onComplete;

  const OnboardingConsentPage({
    super.key,
    required this.dataService,
    required this.onComplete,
  });

  @override
  State<OnboardingConsentPage> createState() => _OnboardingConsentPageState();
}

class _OnboardingConsentPageState extends State<OnboardingConsentPage> {
  bool _healthDataConsent = false;
  bool _privacyPolicyAccepted = false;
  bool _notEmergencyCareAcknowledged = false;
  bool _researchDataSharingEnabled = false;
  bool _cloudSyncEnabled = true;
  bool _personalizedInsightsEnabled = true;
  bool _keyboardTrackingEnabled = false;
  bool _isSaving = false;

  bool get _canContinue =>
      _healthDataConsent &&
      _privacyPolicyAccepted &&
      _notEmergencyCareAcknowledged;

  Future<void> _save() async {
    if (!_canContinue) {
      return;
    }
    setState(() => _isSaving = true);
    await SettingsService.saveConsentPreferences(
      healthDataConsent: _healthDataConsent,
      privacyPolicyAccepted: _privacyPolicyAccepted,
      notEmergencyCareAcknowledged: _notEmergencyCareAcknowledged,
      researchDataSharingEnabled: _researchDataSharingEnabled,
      cloudSyncEnabled: _cloudSyncEnabled,
      personalizedInsightsEnabled: _personalizedInsightsEnabled,
      keyboardTrackingEnabled: _keyboardTrackingEnabled,
    );
    await widget.dataService.syncPrivacyConsentToCloud();
    if (mounted) {
      setState(() => _isSaving = false);
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Consent and safety')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Before using Navi',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'A quick setup so Navi knows what it can use, what should stay off, and when to point you toward human help.',
            ),
            const SizedBox(height: 16),
            const CrisisResourcesCard(),
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _notEmergencyCareAcknowledged,
              onChanged: (value) {
                setState(() {
                  _notEmergencyCareAcknowledged = value ?? false;
                });
              },
              title: const Text('I know Navi is not for emergencies'),
              subtitle: const Text(
                'If I might hurt myself or someone else, I should contact emergency services or a crisis line right away.',
              ),
            ),
            CheckboxListTile(
              value: _healthDataConsent,
              onChanged: (value) {
                setState(() {
                  _healthDataConsent = value ?? false;
                });
              },
              title: const Text('Navi can use my entries to power the app'),
              subtitle: const Text(
                'This lets Navi save journals, mood signals, audio details, analysis results, and wellbeing patterns for my account.',
              ),
            ),
            CheckboxListTile(
              value: _privacyPolicyAccepted,
              onChanged: (value) {
                setState(() {
                  _privacyPolicyAccepted = value ?? false;
                });
              },
              title: const Text('I have reviewed the privacy and safety terms'),
              subtitle: const Text(
                'I can change optional settings later. Research sharing is separate and is not required to use Navi.',
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.privacy_tip_outlined),
                  label: const Text('Read privacy policy'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LegalDocumentsPage(),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Read terms'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const LegalDocumentsPage(initialTabIndex: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _cloudSyncEnabled,
              onChanged: (value) {
                setState(() {
                  _cloudSyncEnabled = value;
                });
              },
              title: const Text('Cloud sync'),
              subtitle: const Text(
                'Store app data in your signed-in cloud account for backup and cross-device use.',
              ),
            ),
            SwitchListTile(
              value: _personalizedInsightsEnabled,
              onChanged: (value) {
                setState(() {
                  _personalizedInsightsEnabled = value;
                });
              },
              title: const Text('Personalized insights'),
              subtitle: const Text(
                'Use your saved data to calculate trends, predictions, and longitudinal patterns inside Navi.',
              ),
            ),
            SwitchListTile(
              value: _researchDataSharingEnabled,
              onChanged: (value) {
                setState(() {
                  _researchDataSharingEnabled = value;
                });
              },
              title: const Text('Contribute de-identified research data'),
              subtitle: const Text(
                'Optional. Allows aggregated/de-identified feature records to be shared for model improvement and possible long-term academic research.',
              ),
            ),
            SwitchListTile(
              value: _keyboardTrackingEnabled,
              onChanged: (value) {
                setState(() {
                  _keyboardTrackingEnabled = value;
                });
              },
              title: const Text('In-app typing rhythm tracking'),
              subtitle: const Text(
                'Optional. Stores aggregate typing cadence, correction, and pause features from Navi text fields. Typed content and individual keys are not stored.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _canContinue && !_isSaving ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
