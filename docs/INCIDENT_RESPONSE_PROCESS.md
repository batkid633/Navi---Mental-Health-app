# Incident Response Process

Owner: Security Officer

Review cadence: Quarterly and after each incident

This process is HIPAA-oriented and must be tailored by counsel and the appointed privacy/security officers before production use.

## Severity Levels

- `SEV-1`: Confirmed or likely unauthorized access, disclosure, loss, ransomware, credential compromise, public exposure, or destructive action involving production user mental health data.
- `SEV-2`: Security event with plausible production data exposure, failed access control, missing audit data, or vendor incident under investigation.
- `SEV-3`: Low-risk security issue, blocked attack, suspicious activity without known exposure, or tabletop follow-up.

## First Hour

1. Assign incident commander, privacy lead, security lead, communications lead, and scribe.
2. Preserve evidence: logs, cloud audit events, affected commits, screenshots, alerts, IAM state, database export metadata, and vendor notifications.
3. Contain without destroying evidence: rotate exposed credentials, disable compromised accounts, revoke sessions, block public access, pause affected sync jobs, or isolate backend services.
4. Determine whether mental health data, identifiers, audio, journal text, model features, backups, or consent records may be involved.
5. Start an incident record in the incident register with timestamps in UTC.

## First 24 Hours

1. Scope affected systems, users, data types, time window, and vendors.
2. Determine whether data was encrypted or otherwise rendered unusable, unreadable, or indecipherable.
3. Assess whether the event is a HIPAA breach, FTC Health Breach Notification Rule event, state breach event, contractual reportable event, app store reportable issue, or research-reportable event.
4. Notify business associates, covered entities, IRB, university officials, cloud vendors, cyber insurer, and counsel as applicable.
5. Create a user-safe remediation plan and preserve a decision log.

## HIPAA-Oriented Breach Assessment

For each impermissible use or disclosure, document:

- Nature and extent of PHI involved, including identifiers and re-identification risk
- Unauthorized person who used or received the information
- Whether PHI was actually acquired or viewed
- Extent to which the risk was mitigated

If notification is required, plan for individual notice without unreasonable delay and no later than 60 calendar days after discovery. For 500 or more affected individuals in a state or jurisdiction, evaluate media notice. For HHS Secretary notice, use the current OCR breach portal timing rules.

## Recovery

1. Patch root cause and add regression tests or policy checks.
2. Rotate all affected keys, secrets, tokens, and service account credentials.
3. Rebuild and redeploy from trusted sources.
4. Validate Firestore, Storage, backend, Firebase Auth, Cloud Run, CI/CD, and monitoring access controls.
5. Notify users and regulators when required.

## Post-Incident Review

Complete within 10 business days:

- Timeline
- Root cause
- Data and user impact
- Notification decisions
- Control failures
- Remediation owner and due date
- Training or policy changes
- Evidence archive location

