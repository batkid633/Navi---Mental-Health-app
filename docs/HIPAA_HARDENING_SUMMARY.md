# HIPAA-Oriented Hardening Summary

Implemented in this repo:

- In-app Privacy Policy and Terms screens
- Versioned privacy, terms, and consent constants
- Onboarding links to policy and terms before consent completion
- Settings links to policy and terms after onboarding
- Local consent snapshot now includes policy and terms versions
- Firestore consent records collection for append-only consent snapshots
- Firestore rules for user-owned consent records with updates blocked
- Draft policy documents and operational runbooks

Important limitation: this is HIPAA-oriented hardening, not a HIPAA compliance certification. Compliance depends on legal role, operations, contracts, training, policies, audits, risk analysis, and incident handling outside the codebase.

