// Run against a local demo-project Firestore emulator only. See deployment docs.
const { createRequire } = require('node:module');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const modules = process.env.NAVI_FIREBASE_TEST_MODULES;
if (!modules) throw new Error('Set NAVI_FIREBASE_TEST_MODULES to the isolated test package.json');
const localRequire = createRequire(resolve(modules));
const { initializeTestEnvironment, assertSucceeds, assertFails } = localRequire('@firebase/rules-unit-testing');
const { doc, setDoc, getDoc, getDocs, collection, deleteDoc } = localRequire('firebase/firestore');

(async () => {
  const env = await initializeTestEnvironment({
    projectId: 'demo-navi-beta',
    firestore: { host: '127.0.0.1', port: 8086, rules: readFileSync(resolve(process.env.NAVI_BETA_RULES || 'firestore.rules'), 'utf8') },
  });
  try {
    const a = env.authenticatedContext('tester-a').firestore();
    const b = env.authenticatedContext('tester-b').firestore();
    const owner = env.authenticatedContext('owner').firestore();
    const anon = env.unauthenticatedContext().firestore();
    const payload = { schemaVersion: 'beta-feedback-1', consentVersion: 'beta-sharing-1', completed: 1,
      easeCounts: [0, 0, 0, 0, 1], helpfulnessCounts: [0, 0, 0, 0, 0], issueCounts: [1, 0, 0, 0, 0, 0] };
    const path = 'beta_feedback_snapshots/tester-a';
    await assertFails(setDoc(doc(anon, path), payload));
    await assertFails(setDoc(doc(b, path), payload));
    await assertSucceeds(setDoc(doc(a, path), payload));
    await assertSucceeds(getDoc(doc(a, path)));
    await assertFails(getDoc(doc(b, path)));
    await assertFails(getDocs(collection(a, 'beta_feedback_snapshots')));
    await assertFails(getDocs(collection(owner, 'beta_feedback_snapshots')));
    await assertFails(setDoc(doc(a, 'beta_feedback_owners/tester-a'), {}));
    for (const invalid of [
      {...payload, journal: 'not permitted'}, {...payload, consentVersion: 'unknown'},
      {...payload, completed: -1}, {...payload, completed: 1.5},
      {...payload, easeCounts: [1, 1, 1, 1, 1]}, {...payload, issueCounts: [0, 0, 0, 0, 0, 0]},
      {...payload, helpfulnessCounts: [0]}, {...payload, easeCounts: ['1', 0, 0, 0, 0]},
    ]) await assertFails(setDoc(doc(a, path), invalid));
    await env.withSecurityRulesDisabled(async (ctx) => setDoc(doc(ctx.firestore(), 'beta_feedback_owners/owner'), {enabled: true}));
    await assertSucceeds(getDocs(collection(owner, 'beta_feedback_snapshots')));
    await assertFails(setDoc(doc(owner, path), payload));
    await assertFails(deleteDoc(doc(b, path)));
    await assertSucceeds(deleteDoc(doc(a, path)));
    await assertSucceeds(setDoc(doc(a, 'users/tester-a/journal_entries/fixture'), {text: 'synthetic'}));
    await assertFails(getDoc(doc(b, 'users/tester-a/journal_entries/fixture')));
    console.log('Beta access, schema validation, deletion, and existing journal isolation passed.');
  } finally { await env.cleanup(); }
})().catch((error) => { console.error(error); process.exitCode = 1; });
