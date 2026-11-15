# Consented audio analysis

The previous Flutter service unconditionally returned an E2EE/on-device-model
error. Recording worked, but no analysis request was attempted on any platform.

The Analyze action now asks permission for the selected recording on every attempt.
Cancel/dismiss does not read the audio or start an analysis request. There is no
remembered consent and no automatic retry. The dialog names the configured backend
host and explains that HTTPS protects transport, but the backend reads the audio.
This processing is not end-to-end encrypted. Existing encrypted storage is unchanged.

After consent, the app sends an authenticated multipart request to /audio/analyze,
with the recording and its mode. The local backend source already implements this
endpoint. The app removes the JSON Content-Type header so multipart boundaries are
correct, uses a generic upload filename, refuses insecure HTTP and redirects, and
rejects empty files and uploads above 25 MiB. The backend may configure a lower limit.
Timeouts report uncertainty: the server may still finish processing the request.

The backend source uses a temporary WAV file and attempts cleanup in a finally
block; this is not a guarantee of zero server retention after crashes. Production
behavior and model availability were not inspected during this task. No recordings
were sent and no backend deployment or configuration changes were made.

Results labeled heuristic_fallback remain viewable but are not saved as mood labels
or sent onward as input to insights. Only results marked user_model or global_model
enter that existing path; those labels alone do not establish clinical validity.
Malformed results and nested analysis errors are treated as failures. The existing
audio pipeline analyzes acoustics; this change does not add speech transcription or
interpret the recording's words using an LLM.

Local tests cover consent/cancel/re-prompt, no access before consent, multipart
format/authentication, size checks, invalid responses and timeout without retries.
The phone is disconnected: installation and real backend analysis remain unverified.

## Device acceptance

1. Record a short new clip. Tap Analyze, then Cancel; no result should be created.
2. Tap Analyze again. Confirm the expected backend host and explicitly agree.
3. Check the returned model status and acoustic results. A heuristic result should
   explain that its mood estimate was not added to insights.
4. Repeat Analyze and confirm it asks permission again.
5. Verify offline/expired-session failures keep the recording available.

Older recordings with stale/missing local paths may require separate recovery;
this change does not fetch cloud recordings silently or rewrite stored file paths.
