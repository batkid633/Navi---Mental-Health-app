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
