# Architecture

SuperHealth uses a local-first Flutter architecture with explicit trust boundaries.

## Data boundary

`AppDatabase` owns the versioned SQLite schema. `HealthRepository` is the only normal application interface to health records. Profiles, schedules, intakes, events, documents, measurements, health context, and plans are profile-scoped. Supplement products and inventory are shared household data; the biomarker catalog and reference ranges are shared catalog data.

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

OneDrive uses a dedicated SuperHealth Microsoft app registration and a single `superhealth_snapshot.json`. Private mode requests `Files.ReadWrite.AppFolder`. Shared-family mode requests delegated `Files.ReadWrite`, enumerates folder metadata for explicit selection, and resolves every snapshot, document, and advisor-workspace path beneath a fixed `SuperHealth` child of the selected folder. Synchronization validates exact table schemas, scalar types, dates, numeric bounds, enums, identifiers, references, and cross-row ownership before staging any remote change. It then merges, records divergent changes, uploads with an ETag, and advances a per-row sync shadow. Stored tokens are bound to both the configured client ID and selected storage mode so an upgrade cannot reuse credentials issued to another app identity or scope. API keys, tokens, import audit tables, and local device paths are excluded.

A portable restore arms a durable sync gate before it mutates local data. Ordinary synchronization remains blocked until the user either resumes normal conflict-aware merging or explicitly publishes the restored snapshot as the authoritative remote copy. Authoritative publishing uses conditional ETags and marks rows synchronized only after the snapshot and documents succeed.

AppFolder isolation prevents direct reads from the former apps’ folders. Legacy exports are selected explicitly through Android’s file picker, read without modification, and passed through the previewed import pipeline. Import hashes prevent accidental repeats, deterministic identifiers make retries safe, and an audit table supports rollback.

## Lab plans

The model may select only biomarkers present in the catalog. Local validation rejects unknown IDs, duplicate markers, invalid evidence labels, missing rationales, or missing tiers. Prices are always replaced with catalog prices. A biomarker is stored once at the tier where it is first added; `itemsThrough()` constructs the cumulative checklists and totals deterministically.

Every candidate plan carries a receipt for the complete immutable health-context package, including its overall hash, file hash, record count, section names, and section hashes. A second stateless provider call to the same configured model receives the same lossless context plus only the parsed candidate data. It must return its own matching receipt and approve without blocking issues. Malformed, incomplete, mismatched, or rejected verification fails closed. Approved plans persist the model/provider identity, context hash, verification summary, warnings, sources, and timestamp, and preserve that audit record through checklist updates and exports.
