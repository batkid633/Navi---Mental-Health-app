# HIPAA and Research Next Steps

This is an external-action checklist for handling mental health data and possibly pursuing academic research. It is not legal advice.

## 1. Determine Legal Role

- Decide whether Navi is a direct-to-consumer wellness app, a healthcare provider tool, a covered entity component, a business associate, a university research system, or a hybrid.
- Get written legal analysis on whether HIPAA, FTC Health Breach Notification Rule, state privacy laws, consumer health privacy laws, 42 CFR Part 2, COPPA/minor-consent laws, app store health rules, and international privacy laws apply.
- If any covered entity or covered provider uses Navi, execute business associate agreements before PHI flows.

## 2. Appoint Compliance Owners

- Name a Privacy Officer and Security Officer.
- Create a compliance calendar for risk analysis, access reviews, training, policy review, incident tabletop exercises, vendor reviews, and backup restore tests.
- Maintain a policy index and evidence folder.

## 3. Complete Security Risk Analysis

- Inventory data flows from device, Hive, Firebase Auth, Firestore, Storage, backend APIs, Cloud Run, logs, model files, exports, WHOOP data, and any analytics/AI provider.
- Classify PHI, identifiable consumer health data, coded research data, de-identified data, logs, secrets, and backups.
- Document threats, vulnerabilities, likelihood, impact, existing controls, remediation owners, and due dates.
- Validate encryption at rest and in transit, key management, audit logging, retention, deletion, and disaster recovery.

## 4. Contract Vendors

- Review Firebase/Google Cloud, WHOOP, email/support, monitoring, crash reporting, analytics, AI/model vendors, repository hosting, CI/CD, and data warehouses.
- Execute BAAs where required.
- Disable vendors that will not sign required agreements or cannot meet data-use restrictions.
- Confirm vendor breach notification timelines, subcontractors, data location, deletion, logging, and support access.

## 5. Prepare Production Policies

- Privacy Policy
- Terms of Use
- HIPAA Notice of Privacy Practices, if Navi is operated by a covered healthcare provider or health plan
- Incident response and breach notification
- Access control and access review
- Data retention and deletion
- Data export and user rights
- Secure development lifecycle
- Vendor management
- Employee training and sanctions
- Backup, disaster recovery, and business continuity

## 6. Research Governance

- Before using user data for academic research, write a protocol covering purpose, hypotheses, population, recruitment, consent, risks, benefits, compensation, privacy protections, data minimization, withdrawal, retention, sharing, and publication.
- Submit to an IRB or qualified ethics reviewer before recruitment or analysis if the activity is human-subjects research or if the institution requires review.
- Separate app-service consent from research consent.
- Decide whether research data will be identifiable, coded, limited dataset, or de-identified. Keep the linkage key separately with strict access controls.
- Create a data use agreement for collaborators.
- Register the study if required by institution, funder, journal, or law.
- Define how participants can withdraw and what happens to already analyzed or de-identified data.

## 7. Mental Health Safety Review

- Have a licensed mental health professional review safety language, crisis resources, high-risk interaction paths, model output wording, and disclaimers.
- Decide whether Navi will detect crisis language. If yes, define duty-to-warn limits, escalation workflows, false positive handling, jurisdiction handling, and staffing before launch.
- Avoid representing predictions as diagnosis or treatment.

## 8. Launch Gate

Do not launch with real mental health data until these are complete:

- Counsel-reviewed legal role memo
- Security risk analysis and remediation plan
- Signed required BAAs and vendor approvals
- Production incident response runbook and tabletop
- Monthly access review process started
- User support/privacy request process
- Tested export and deletion
- Logging configured without sensitive text/audio leakage
- IRB approval or written non-research determination for academic use
- App store privacy labels and website disclosures aligned with actual behavior

## Primary Sources to Review

- HHS HIPAA Security Rule summary: https://www.hhs.gov/hipaa/for-professionals/security/laws-regulations/
- HHS HIPAA Breach Notification Rule: https://www.hhs.gov/hipaa/for-professionals/breach-notification/
- HHS breach reporting instructions: https://www.hhs.gov/hipaa/for-professionals/breach-notification/breach-reporting/
- HHS model Notices of Privacy Practices: https://www.hhs.gov/hipaa/for-professionals/notice-privacy-practices/
- HHS HIPAA and FTC Act guidance for consumer health apps: https://www.hhs.gov/hipaa/for-professionals/special-topics/hipaa-ftc-act/
- OHRP coded private information guidance: https://www.hhs.gov/ohrp/coded-private-information-or-biospecimens-used-research.html

