# SuperHealth

SuperHealth is a private, Android-first personal health companion combining supplement intake, symptoms and tags, biomarker history, lab-report parsing, price-aware lab planning, exploratory correlations, and a user-controlled AI advisor.

## What is included

- Isolated profiles with conditions, medicines, goals, and family history.
- Supplement products, daily schedules, intake history, symptoms, and exposure tags.
- Biomarker catalog with German lab prices, manual results, reviewed PDF extraction, trends, and lab-reference status.
- Exploratory daily Pearson correlations with 0–2 day exposure lags and explicit non-causality labeling.
- AI-generated Core, Advanced, and Comprehensive lab checklists. Tiers are cumulative and totals use only stored EUR prices.
- Saved lab plans plus PDF, CSV, and JSON export.
- Direct BYOK integrations for OpenAI, Anthropic, and Gemini, with live model discovery and conservative per-model reasoning/tool controls.
- Separate model configuration for PDF parsing and the main advisor.
- OneDrive AppFolder snapshot sync, document upload, and conflict recording through a dedicated SuperHealth Microsoft app identity.
- Previewed import of existing Supplement Manager and Biomarkers JSON data with deterministic deduplication, audit history, and rollback support.
- A profile-scoped advisor workspace. The AI may read workspace text and propose file changes, but every create, replace, or delete requires an exact user preview and confirmation.

## Privacy and safety model

- SQLite is local-first and every health row is profile-scoped.
- API keys and OneDrive tokens use Android secure storage and are never synchronized, exported, or placed in AI context.
- The advisor receives a serialized, read-only active-profile snapshot. No AI service is given a database or repository handle.
- Complete health context is never silently truncated. The app asks for a larger-context model when a known model limit is insufficient.
- OneDrive uses `Files.ReadWrite.AppFolder` through a dedicated SuperHealth registration; it cannot browse the rest of the drive or another app’s AppFolder.
- Provider-hosted web search and code execution are exposed only for models whose support is registered from provider documentation.
- Recommendations distinguish guideline-supported, longevity-oriented, experimental, and unclassified evidence. The app is planning support, not diagnosis or emergency care.

See [Architecture](docs/ARCHITECTURE.md) and the [User guide](docs/USER_GUIDE.md).

## Development

Requirements: Flutter 3.44.6, Dart 3.12+, Java 17, and an Android SDK.

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
```

GitHub Actions runs the same checks and uploads a release APK artifact. Personal local builds fall back to debug signing. For installable updates from CI, configure a stable private signing key as described in [Android signing](docs/ANDROID_SIGNING.md).

The repository intentionally contains no API keys, access tokens, health data, or signing secrets.
