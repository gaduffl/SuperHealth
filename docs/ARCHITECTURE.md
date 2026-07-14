# Architecture

SuperHealth uses a local-first Flutter architecture with explicit trust boundaries.

## Data boundary

`AppDatabase` owns the versioned SQLite schema. `HealthRepository` is the only normal application interface to health records. Profiles, supplements, intakes, events, documents, measurements, health context, and plans are stored as profile-scoped rows. The biomarker catalog and reference ranges are shared catalog data.

The advisor and parser never receive `AppDatabase`, a SQLite connection, or `HealthRepository` write methods:

- `HealthContextBuilder` serializes a complete active-profile snapshot.
- Provider clients receive only that JSON string, prompts, and selected settings.
- `DocumentParsingService` produces an in-memory review model. Database and PDF persistence happen only after the user confirms the review screen.
- `SafeWorkspaceService` stages path-safe file proposals in memory. It checks the reviewed prior hash before applying an approved change.

API keys and OneDrive tokens live in Android secure storage and are outside every snapshot and export allowlist.

## AI providers

OpenAI uses the Responses API, Anthropic uses Messages, and Gemini uses Interactions. Models are fetched from each provider at runtime. A versioned capability registry exposes only documented reasoning levels and hosted tools; unknown models receive no speculative switches.

The main advisor may use provider-hosted web search and isolated code execution. Provider sandbox files are not treated as app files. Persistent file changes use the `superhealth-file-proposal` protocol and require a second, app-side approval.

PDF parsing ports the useful extraction contract from the former Biomarkers backend while removing Firebase authentication, credits, billing, app-owned API keys, and PC linking. Parsing supports inline or temporary provider file input, validates JSON locally, and requires row mapping review before save.

## Synchronization

OneDrive uses Microsoft Graph AppFolder scope and a single `superhealth_snapshot.json`. Synchronization downloads, validates, merges, records divergent changes, uploads with an ETag, and advances a per-row sync shadow. API keys, tokens, import audit tables, and local device paths are excluded.

Legacy exports are read without modification and passed through the same previewed import pipeline. Import hashes prevent accidental repeats, deterministic identifiers make retries safe, and an audit table supports rollback.

## Lab plans

The model may select only biomarkers present in the catalog. Local validation rejects unknown IDs, duplicate markers, invalid evidence labels, missing rationales, or missing tiers. Prices are always replaced with catalog prices. A biomarker is stored once at the tier where it is first added; `itemsThrough()` constructs the cumulative checklists and totals deterministically.
