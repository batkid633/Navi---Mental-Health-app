# Access Review Process

Owner: Security Officer

Review cadence: Monthly for production, immediately after staff/vendor changes

## Scope

Review every human and service identity with access to:

- Firebase project, Firestore, Storage, Auth, Functions, Data Connect, Hosting
- Google Cloud project, Cloud Run, Artifact Registry, Secret Manager, Cloud Logging, IAM
- GitHub repository, CI/CD secrets, deployment keys, branch protections
- Backend databases, model artifacts, logs, exported datasets, backups
- WHOOP developer credentials and other third-party integrations
- Support inboxes, analytics tools, monitoring tools, and incident tools

## Minimum Access Standards

- Unique user accounts only; no shared admin accounts.
- MFA required for every admin, developer, support, cloud, and repository account.
- Least privilege by role; production data access requires documented need.
- Break-glass accounts must be named, MFA protected, monitored, and tested quarterly.
- Service accounts must have narrowly scoped roles and no long-lived keys unless formally approved.
- Access to identifiable mental health data requires privacy training and signed confidentiality obligations.

## Monthly Review Steps

1. Export IAM and membership lists from Firebase, Google Cloud, GitHub, and vendors.
2. Compare against the approved access register.
3. Remove stale users, unused service accounts, excessive roles, old keys, and former collaborators.
4. Confirm emergency access account status and recent use.
5. Review Cloud Logging/Firebase audit logs for unusual admin or data access.
6. Document reviewer, date, findings, removals, exceptions, and follow-up due dates.

## Joiner/Mover/Leaver Rules

- New access requires owner approval, role, justification, expiration date, and training completion.
- Role changes require same-day permission update.
- Departures require access removal the same day, plus token/session revocation and key rotation if the departing person had secret access.

## Evidence to Keep

- Exported access lists
- Review checklist
- Removed accounts/roles
- Exceptions and expiration dates
- Training records
- Screenshot or log links showing completion

