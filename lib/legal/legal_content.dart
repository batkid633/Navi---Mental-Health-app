class LegalContent {
  static const String effectiveDate = '2026-05-31';
  static const String privacyPolicyVersion = 'privacy-2026-05-31';
  static const String termsVersion = 'terms-2026-05-31';
  static const String consentVersion = 'consent-2026-05-31';

  static const String privacyPolicyTitle = 'Privacy Policy';
  static const String termsTitle = 'Terms of Use';

  static const List<LegalSection> privacyPolicySections = [
    LegalSection(
      title: 'Sensitive data Navi handles',
      body:
          'Navi may store journal text, mood ratings, sentiment analysis, audio recordings, audio metadata, transcripts, connected health-tracker wellness metrics, optional in-app typing rhythm aggregates, predictions, insight outputs, account identifiers, device sync status, and consent preferences. Mental health entries can be highly sensitive even when they are not part of a clinical record.',
    ),
    LegalSection(
      title: 'How data is used',
      body:
          'Navi uses your data to provide journaling, mood tracking, audio analysis, personalized insights, longitudinal trends, model predictions, account sync, support, security monitoring, data export, and deletion workflows. Navi should not use identifiable data for advertising or unrelated profiling.',
    ),
    LegalSection(
      title: 'Cloud sync and processors',
      body:
          'When cloud sync is enabled, app data may be stored in Firebase services and processed by the Navi backend. Cloud storage, authentication, logging, analytics, model hosting, monitoring, and support vendors must be reviewed for security, privacy, data location, retention, and business associate agreement requirements before production use with regulated health data.',
    ),
    LegalSection(
      title: 'Optional research sharing',
      body:
          'Research/data-sharing is optional and is separate from app use. When enabled, Navi may send de-identified or coded feature records for model improvement and possible academic research. Optional typing rhythm tracking stores aggregate cadence, pause, correction, and platform features only, not typed content or individual keys. Do not treat this as IRB-approved research consent until an IRB or qualified ethics reviewer has approved the protocol, consent language, data plan, and withdrawal process.',
    ),
    LegalSection(
      title: 'Your controls',
      body:
          'You can change cloud sync, personalized insights, in-app typing rhythm tracking, and research/data-sharing settings. You can export or delete your data from the app. Deletion removes local app data and requests deletion from connected cloud/backend stores, although backups, audit logs, legal holds, and already de-identified aggregate datasets may have separate retention rules.',
    ),
    LegalSection(
      title: 'Safety and crisis limits',
      body:
          'Navi is not emergency care, a crisis monitoring service, a therapist, a physician, or a substitute for professional diagnosis or treatment. If you may harm yourself or someone else, call emergency services or a crisis line immediately.',
    ),
    LegalSection(
      title: 'HIPAA status',
      body:
          'HIPAA may apply depending on how Navi is offered, who operates it, whether covered entities are involved, and whether Navi acts as a business associate. This policy is written for HIPAA-oriented handling but is not a legal determination that Navi is HIPAA compliant.',
    ),
    LegalSection(
      title: 'Contact',
      body:
          'Before production launch, replace this placeholder with the legal entity name, mailing address, privacy contact email, security contact email, and complaint instructions.',
    ),
  ];

  static const List<LegalSection> termsSections = [
    LegalSection(
      title: 'Use of Navi',
      body:
          'Navi is a self-tracking and wellbeing insights app. You are responsible for the information you enter and for deciding whether app-generated insights are useful to you. Navi does not provide medical advice, diagnosis, treatment, psychotherapy, crisis response, or clinical monitoring.',
    ),
    LegalSection(
      title: 'Account and data accuracy',
      body:
          'Keep your account secure and only connect data sources you are authorized to use. App predictions and sentiment outputs may be incomplete or wrong, and should not be used as the sole basis for mental health, medical, employment, insurance, or safety decisions.',
    ),
    LegalSection(
      title: 'Consent and withdrawal',
      body:
          'Core consent is required to use features that process mental health data. Optional research/data-sharing can be enabled or disabled later. Turning off optional sharing stops future research feature uploads from this device but may not remove already de-identified aggregate outputs.',
    ),
    LegalSection(
      title: 'Acceptable use',
      body:
          'Do not use Navi to harm others, violate law, upload data about another person without authority, reverse engineer protected services, bypass security controls, or use the app as an emergency dispatch or clinical decision system.',
    ),
    LegalSection(
      title: 'Production readiness',
      body:
          'Before handling regulated health data in production, the operator must complete legal review, security risk analysis, vendor contracting, incident response preparation, access review setup, and research governance steps described in this repository.',
    ),
  ];
}

class LegalSection {
  final String title;
  final String body;

  const LegalSection({required this.title, required this.body});
}
