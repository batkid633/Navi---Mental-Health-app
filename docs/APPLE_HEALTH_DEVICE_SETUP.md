# Apple Health device milestone

Local preparation: September 12, 2026. No Apple/provider/cloud service was
queried. No account credentials, production configuration, or data were changed.

## Prepared

- Runner HealthKit capability and `com.apple.developer.healthkit` entitlement for
  Debug, Profile, and Release, keeping bundle `com.example.naviPersonal` and team
  `DH5FU348SB` unchanged.
- Read-only permission description; no write, clinical-record, or background
  delivery capability. The unused write description was removed.
- Settings > Apple Health > Preview Apple Health reads the last 30 days and shows
  day coverage for sleep, sleep efficiency, resting heart rate, and HRV SDNN.
- The preview reads HealthKit locally and holds summaries in memory while the
  dialog is open. It does not save, upload, log samples, or send preview analytics.
  The rest of NAVI retains its existing cloud behavior.
- Apple status no longer calls the backend or claims HealthKit authorization
  based on a backend connection flag. No readable samples is explicitly
  ambiguous: absence of data and withheld read access cannot be distinguished.
- Existing cloud sync code remains separate from the preview and is not exposed
  by the Apple card during this milestone. The normalized backend contract still
  requires a future separately authorized deployment.

## Signing gate

The installed Xcode's local
`DVTPortal.framework/Versions/A/Resources/DVTPortalCachedPortalCapabilities.json`
lists `XCODE_FREE_PROGRAM` among valid HealthKit team types. This is local
capability metadata, not confirmation that Apple issued a HealthKit profile for
this account.

The previously decoded NAVI profile lacks `com.apple.developer.healthkit` and
expires September 13, 2026 at 14:38:52 America/New_York. A profile with the HealthKit
entitlement is needed before installing this build. Do not add the entitlement to
an already signed binary or assume that reinstalling renews provisioning.

Manual Xcode step when ready:

1. Open `ios/Runner.xcworkspace`.
2. Select the blue Runner project, then TARGETS > Runner > Signing & Capabilities.
3. Keep Automatically manage signing checked, and the current Personal Team and
   bundle identifier selected. HealthKit should now appear as a capability.
4. Select the connected iPhone as the run destination. If Xcode displays a signing
   repair/update action, use it manually and report the resulting status/error.
   This manual operation may contact Apple's signing services; the agent has not
   performed it under the local-only guardrail.
5. Do not enable Clinical Health Records or Background Delivery, change the bundle,
   or enroll in a paid program to resolve an error without discussing it first.

If Xcode cannot provision HealthKit, keep the currently installed core NAVI app.
There is no device verification yet and no reason to delete the app or its data.
A local build can temporarily omit this capability for continued core testing;
that would not enable real HealthKit reads.

## Device verification after signing/install

Launch from the home screen, open the preview, choose the desired read categories
in the iOS permission sheet, and report the displayed coverage counts. Repeat with
NAVI closed/reopened and after adjusting read access in Health. Empty coverage is
not automatically a failure: the device needs actual samples from compatible
sources. Confirm the preview sends no health data; do not use cloud sync as a
verification shortcut. The existing normalization tests use synthetic data only.

This milestone prepares local native access. Persistent health collection,
research opt-in, backend sync verification, and study-ready measurement validation
are separate pending work.

## Signing update

After the user selected their Personal Team in Xcode, a new local provisioning
profile was issued for `DH5FU348SB.com.example.naviPersonal`. Local decoding
confirmed `com.apple.developer.healthkit = true`, inclusion of the connected
personal iPhone, and expiry September 19, 2026 at 22:19 EDT. This resolves the
previous profile's missing-entitlement gate. The older expiry above is historical.

For the signed build, use local `xcodebuild` without `-allowProvisioningUpdates`
or `-allowProvisioningDeviceRegistration`. Flutter 3.44's signed build workflow
adds those flags automatically; direct Xcode invocation avoids requesting online
provisioning changes under the current guardrails.

## Installation checkpoint — September 13, 2026

Signed Release build succeeded using `BUILD_DIR` (rather than overriding
`CONFIGURATION_BUILD_DIR`, which mismatched CocoaPods resource paths). Artifact:
`build/ios/Release-iphoneos/Runner.app`. Deep/strict signature verification passed;
both the signed app and embedded profile contain the HealthKit entitlement.
Installation on the connected iPhone succeeded.

Launch was rejected by iOS with a Security error listing signature, entitlement,
or explicit profile trust as possible causes. Local signature checks passed;
device trust must be checked next. On iPhone: Settings > General > VPN & Device
Management > Developer App > the Apple Development account > Trust/Verify App.
If already trusted, capture the exact on-device message before further changes.
Health permission and sample coverage remain unverified.
