# Automatic biometric refresh

Local implementation: September 16, 2026.

Today predictions and Insight trends now await a best-effort refresh of already
connected WHOOP and Google Health providers. The visible Today/Insights page also
reloads on app resume. No connection or permission prompts are started
implicitly. Apple Health remains a local preview; this change does not grant or
enable Apple Health uploads.

The existing provider status/sync endpoints are reused. Automatic imports request
seven days to catch recent updates. Manual Settings sync remains available for
its existing longer lookback. Automatic refresh requires a signed-in account,
cloud sync enabled, and personalized insights enabled.

A shared coordinator coalesces concurrent automatic requests by account/backend.
It throttles successful checks for 30 minutes and retries failed-only checks after
five minutes. These timers are in memory and reset when the process restarts.
They are not a background scheduler: closing NAVI stops automatic activity.

Status calls wait at most four seconds and imports eight seconds per provider.
Unavailable providers do not prevent the existing prediction/fallback paths from
running. The server may still finish a request after the local wait times out;
this client cannot cancel an import already running on the backend. Imports are
started sequentially to reduce concurrent writes. Manual sync is not coalesced by
this coordinator. A partial success is treated as a successful refresh and the
other provider is checked at the next 30-minute opportunity.

Successful imports with saved rows increment a local data revision. The next
successful tomorrow prediction bypasses the LLM cache using the existing
`force_reload` request field. Loading trends first does not consume that revision.
This avoids retaining the previous cached explanation after a new import. The
backend's existing saved-row count does not prove that metric values changed,
so a successful refresh may regenerate an insight with unchanged measurements.
No backend configuration or model changes are part of this task.

Validation uses synthetic coordinator callbacks: duplicate coalescing, throttling,
failure backoff (including synchronous errors), account/backend isolation, and
no-data behavior. Live WHOOP freshness and deployed endpoint behavior were not
queried or verified. To verify on-device later, open Today with WHOOP connected,
cloud sync and personalized insights on, then compare the displayed result with
an authorized provider-data check. No raw health data should be pasted into logs
or GitHub issues.
