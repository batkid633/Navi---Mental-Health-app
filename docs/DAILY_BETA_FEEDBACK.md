# Daily beta feedback and owner reporting

Daily prompts remain optional. Answers stay in account-specific encrypted Hive
storage. Cloud sharing defaults OFF, independently of research consent and prompts.
Settings → Daily beta feedback & statistics offers explicit sharing consent
(version beta-sharing-1), status, retry, opt-out, and shared deletion.

Only answers saved after opting in enter the shared aggregate. No historical
backfill or skipped days. Editing a saved answer replaces its daily contribution.
The snapshot contains schema/consent versions, completed response-day count, five
counts each for ease/helpfulness, and six issue counts. Its document ID is the
Firebase UID: pseudonymous, not anonymous. No journal text, audio, health data,
names, emails, free text or survey dates are uploaded.

Failed requests stay queued locally and retry on save, resume or explicit Retry.
Direct authenticated REST requests avoid a Firestore SDK persistent write queue.
The app must reopen while signed in to retry; closed-app delivery is not guaranteed.
Turning sharing off cancels pending uploads but retains the existing cloud snapshot.
An already-dispatched upload may still complete. Delete shared feedback disables
sharing, clears the local sharing subset and queues cloud deletion. If offline,
reopen NAVI online to complete it. Local answers remain. Deleting local beta answers
also requests shared deletion. Previously distributed presentations cannot be recalled.

Use ONE DEVICE PER ACCOUNT for this beta. The latest snapshot replaces the previous
account snapshot. Changing devices or reinstalling can reduce cumulative totals.
This is a minimal usability feedback system, not a longitudinal research repository.

## Owner view

Settings → Daily beta feedback & statistics → Owner aggregate statistics loads
consented snapshots for an authorized owner account. It shows contributing accounts,
response-days, distributions, response-weighted means, unrated counts and issues.
Identifiers are not displayed and cohort results are not persisted by this screen.
Project administrators can still see account-linked documents in Firebase.

Account counts are not verified unique people. These are self-selected usability
responses, not retention, clinical efficacy or representative population estimates.
Frequent responders contribute more. Without dates there are no time trends.
Review small-group counts before sharing screenshots.

The Python CSV dashboard and its tests were retired. Personal in-app CSV export
remains. beta_feedback_private/ stays Git-ignored; existing private files were kept.

## Deployment status and procedure

Local implementation and emulator tests are complete. On October 25, 2026, the
beta-only Firestore rules were deployed and the supplied NAVI UID received beta
owner membership. Deployed rules were read back and matched the tested release.
No survey, journal, or other user records were read or changed during deployment.
The local iOS Release build and code-signature verification passed. The profile
expires October 31, 2026. Device installation and end-to-end consent/upload/owner-view
verification are pending because the phone is disconnected.

1. Sign into Firebase CLI for existing project project-bc878e6c-6f53-4f24-88a.
2. Read and back up deployed Firestore rules, compare with the repository baseline,
   and preserve any remote-only changes before publishing.
3. Deploy ONLY Firestore rules from the reviewed beta-only release config:
   firebase deploy --only firestore:rules --project project-bc878e6c-6f53-4f24-88a
   --config /Users/cmdb/Documents/navi-toolchain/beta-rule-deploy/firebase.json
   (Place both command lines on one line.)
4. As administrator, create beta_feedback_owners/<OWNER_AUTH_UID> with enabled: true.
   Existence grants read access to feedback snapshots only. Clients cannot create
   or change membership. Delete membership to revoke access.
5. Build/install and verify opt-in, a real survey save, owner visibility, edit without
   duplication, opt-out and deletion. Do not add synthetic production participants.

## Validation

42 Flutter tests pass, including sharing default-off, no history backfill, retry,
opt-out, deletion retry and deletion ordered after an in-flight upload.
Local emulator tests in test/beta_feedback_rules.cjs pass for anonymous/cross-user
denial, owner listing, privilege escalation denial, payload validation, deletion,
and existing journal isolation. No production data was used.

Test tools are isolated outside the app at navi-toolchain/beta-firebase:
Firebase CLI 14.22.0, rules-unit-testing 4.0.1 and Firebase JS 11.10.0, with Node
22.16.0 in navi-toolchain/node-v22.16.0-darwin-arm64. Flutter dependencies unchanged.
Set NAVI_FIREBASE_TEST_MODULES to the tool installation's package.json and run
node test/beta_feedback_rules.cjs via firebase emulators:exec on demo-navi-beta,
with local Firestore port 8086 and a config pointing to firestore.rules.

## Release scope and rollback

The repository already had unpublished keyboard_sessions and notification_devices
rules. They were excluded from this deployment to avoid unrelated access changes.
Production contains its previous rules plus only beta_feedback_snapshots and
beta_feedback_owners access checks. Do not assume a full root-config deploy is
equivalent to this release.

The exact tested/deployed source, prior source, release metadata and isolated
config are saved locally in /Users/cmdb/Documents/navi-toolchain/beta-rule-deploy/.
To roll back, publish before.rules through a separate Firestore-only config after
checking for subsequent production edits. Owner membership can be revoked by
deleting only its beta_feedback_owners document. Neither rollback deletes survey
snapshots; any feedback-data deletion requires its own deliberate action.
