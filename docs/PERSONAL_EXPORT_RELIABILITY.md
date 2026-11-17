# Personal export reliability — local changes

The submitted export reported a SecretBox message-authentication failure. This
means the encrypted material could not be authenticated using the current key;
it does not establish whether the key is wrong or the ciphertext is damaged.
No keys, credentials, ciphertext, cloud rules or production data were changed.

Previously one failed read/decryption discarded all cloud sections. The exporter
now collects independent sections with per-section timeouts, keeps successful
sections and reports unreadable sections as errors, not empty collections. Profile
key redaction is retained. Outer cloud/backend errors are generic rather than
including raw exception details. Account changes during export abort the result.

Settings shows a partial-export status and preview title instead of unqualified
success when a source fails or cloud export is not requested. The existing format
is retained with additive status fields. A returned backend payload is explicitly
unverified: the deployed backend can suppress feature-read errors into an empty
object, so successful transport does not prove dataset completeness.

This does not recover a failed collection, export audio binary files, restore
missing local records or certify complete provider coverage. A fresh on-device
export is required to identify the failing collection and investigate recovery
without risking readable data. Do not reset encryption or delete records.

Local tests use synthetic loaders only. No live export, shared-server access,
deployment or iPhone install was performed during this change.

## November 17: feature snapshot omissions

Local code audit found that journal background initialization called the feature
sync method with only the journal box. Keyboard and Beacon saves supplied only
one additional box. Optional omitted boxes were converted to empty iterables.
Thus different callers produced incompatible partial snapshots of the same day.

The central method now opens all omitted local modality boxes before building a
snapshot. New `syncCloud: false` reads avoid starting cloud hydration/rewrite as
part of this preparation. Failed local reads abort the upload rather than send
an incomplete replacement. Existing research-consent checks remain; account and
consent are checked again after loading. The public journal sync wrapper no longer
silently swallows local read failures and substitutes absent modalities.

Personal exports additionally include `localDailyFeatures` from all available
local boxes and explicit coverage metadata. This is independent of whether the
backend export contains the latest measurements. No network call was run to verify
remote persistence. The records remain journal-day scoped: raw exported modality
lists retain observations on other days. Expanding uploaded rows to non-journal
days requires coordinating the backend's required sentiment field and target
handling; no fabricated neutral journal scores were introduced.

Both native and web builders now require calendar adjacency for `Next_day_delta`.
Previously the next observed entry could be several days later. Existing exported
historical labels are not rewritten; Python evaluation already recomputes exact
calendar-day targets instead of trusting that column.

Wearable metrics are not loaded by this local feature builder. The repository's
backend has biometric-preservation logic, but its deployment and actual provider
persistence have not been inspected under local-only restrictions. Empty exported
health columns do not establish that the wearable itself failed to sync.

Remaining cloud collection errors are not diagnosed by the generic export status:
a decryption failure, rules denial, or other read failure requires distinct evidence.
The earlier MAC error does not prove every currently unavailable collection has
the same cause. No key resets, data deletion or rules changes were performed.

Regression tests verify native/web gap-safe labels, inclusion of available audio,
and exclusion of raw journal text from numeric feature records. Rebuild/install
and a fresh personal export are required to verify the changes on-device.
