# Security Review - 2026-06-01

## Scope

- Backend FastAPI auth, admin endpoints, file/path handling, upload handling, and user runtime data scoping.
- Firebase Firestore and Storage rules.
- Flutter client paths that call sensitive backend endpoints.
- Repository scan for hardcoded private keys, server API keys, client secrets, tokens, and passwords.

## Changes Made

- Added `require_admin` in `backend/auth.py`.
- Gated `/config-check`, `/monitoring/summary`, `/audio/train`, and `/whoop/retrain` behind admin access.
- Added bounded request models and runtime validation for journal text, prediction dates, daily feature batch size, audio modes, audio content types, and upload size.
- Restricted audio training CSV paths to backend-controlled data directories.
- Replaced raw/sanitized runtime user directory names with hashed storage keys to reduce path collision risk.
- Added defensive delete path checks for backend user runtime data.
- Tightened Firebase Storage writes for user audio to authenticated owner paths, audio content types, and a 25 MB cap.
- Fixed the Flutter audio multipart call so it does not send a JSON `Content-Type` header with multipart uploads.
- Added admin/upload-size env examples to deployment configuration.

## Secret Scan Summary

No private key blocks, OpenAI-style server keys, AWS access keys, or hardcoded password assignment values were found in source files scanned outside build artifacts, virtualenvs, logs, and model binaries.

Expected non-secret/client-side findings:

- Firebase client API keys in `android/app/google-services.json` and `lib/firebase_options.dart`.
- Environment variable names and documentation examples for tokens, secrets, and passwords.
- Code paths that read tokens/secrets from environment variables or Google Secret Manager.

Ignored local secret-bearing files are covered by `.gitignore`, including `.env*`, `navi_ml/tokens/`, `logs/*.jsonl`, `logs/*.csv`, and `backend/user_runtime_data/`.

## Verification

- `python -m py_compile backend\app.py backend\auth.py backend\user_data.py backend\whoop_api.py backend\ml\audio_mood.py backend\ml\feature_loader.py backend\ml\predict_mood.py`
- FastAPI smoke test confirmed:
  - `/health` returns `200`
  - `/config-check` returns `403` without admin access
  - invalid `/predict/tomorrow` date returns `422`
- `flutter test` passed Hive persistence tests, then failed in `test/widget_test.dart` during Firebase initialization setup.
- `flutter analyze` reports existing info/warning items in `journal_detail_page.dart` and web utility files.
