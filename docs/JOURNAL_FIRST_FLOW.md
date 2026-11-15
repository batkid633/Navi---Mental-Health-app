# Journal-first opening and Today freshness

NAVI opens the Journal tab. Today is not mounted or asked to load a prediction
until selected. Users can still visit Today or Audio directly; saving a journal
does not force navigation or impose a daily-entry requirement.

When personalized insights are enabled, Today waits for the existing daily-feature
sync before requesting a prediction, but only when the existing research-sharing
setting permits that sync. Successful changed payloads invalidate the prediction
cache via force_reload. Unchanged payloads retain normal cache behavior. Explicit
Reload Insight still forces regeneration. Failed sync/prediction displays an
unavailable message and retry action rather than claiming newly refreshed results.

Research sharing is not enabled automatically. With it off, Today explains that
new journal/audio metrics are not uploaded; remote insights may use prior data.
The local journal summary still updates. This preserves the existing consent
boundary, although tying personal insight inputs to research consent merits a
separate product/privacy review before wider beta testing.

This change does not rewrite or deploy backend LLM prompts. Prompt quality, feature
coverage and the persistent high-sentiment report remain separate audit tasks.
Audio contributes through the existing feature pipeline; audio-only behavior and
Today's existing journal-data requirement are unchanged.

Validation: 52 local Flutter tests pass, including refresh ordering, failed-sync
handling, no input sharing when disabled, and disabling insights mid-sync. Analysis
reports only four pre-existing style notices. No production endpoints were called.
Phone installation and live freshness verification remain pending.
