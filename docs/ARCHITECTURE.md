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

## Interface

`lib/ui/design.dart` holds the shared visual vocabulary — surface cards, the progress ring, the day strip, stat tiles, and the qualitative series palette. Nothing there hardcodes a brightness-specific colour, so light, dark, high-contrast, and the deuteranomaly-friendly palette all work without per-screen special cases. `seriesColors` sorts its keys before assigning, so a chart series keeps its colour when an unrelated series is added or filtered out.

`lib/ui/charts.dart` wraps `fl_chart` behind the four shapes the app needs: a multi-series weekly line chart, a stacked adherence bar chart, a daily value chart, and a single-series trend. Each carries a `semanticLabel`, because the numbers behind a chart have to remain reachable without sight of it.

`ShellNavigation` routes deep links. The Today screen's overview tiles are shortcuts, so a tile issues a `SectionRequest` naming a section, an optional filter, and a monotonically increasing token; the shell switches tab and the owning screen applies the request and marks the token handled. The token is what lets a repeated tap on the same tile re-apply a filter the user has since changed by hand. The same channel carries a prompt to the advisor, so the Today screen's day analysis reuses the one BYOK code path instead of adding a second.

`SupplementInsights` remains the only place that derives numbers from records: adherence, stock projection, exposure, weekly chartable series, purchase planning, and cost. Screens read it and render; they do not compute.

## AI providers

OpenAI uses the Responses API, Anthropic uses Messages, and Gemini uses Interactions. Models are fetched from each provider at runtime. A versioned capability registry exposes only documented reasoning levels and hosted tools; unknown models receive no speculative switches.

The main advisor may use provider-hosted web search and isolated code execution. Provider sandbox files are not treated as app files. Persistent file changes use the `superhealth-file-proposal` protocol and require a second, app-side approval.

`SupplementLabelService` reads a pasted product label with the same configured parsing model. It sends only the packaging text — never the health context envelope — and does the division by serving size locally rather than asking the model for it, so an arithmetic slip cannot silently store a dose several times too high. The result populates the editable ingredient rows; persistence still requires the user to save the product.

PDF parsing ports the useful extraction contract from the former Biomarkers backend while removing Firebase authentication, credits, billing, app-owned API keys, and PC linking. Parsing supports inline or temporary provider file input, validates JSON locally, and requires row mapping review before save.

## Synchronization

OneDrive uses a dedicated SuperHealth Microsoft app registration and a single `superhealth_snapshot.json`. Private mode requests `Files.ReadWrite.AppFolder`. Shared-family mode requests delegated `Files.ReadWrite`, enumerates folder metadata for explicit selection, and resolves every snapshot, document, and advisor-workspace path beneath a fixed `SuperHealth` child of the selected folder. Synchronization validates exact table schemas, scalar types, dates, numeric bounds, enums, identifiers, references, and cross-row ownership before staging any remote change. It then merges, records divergent changes, uploads with an ETag, and advances a per-row sync shadow. Stored tokens are bound to both the configured client ID and selected storage mode so an upgrade cannot reuse credentials issued to another app identity or scope. API keys, tokens, import audit tables, and local device paths are excluded.

Synchronization runs on app resume as well as on the explicit action, throttled to one automatic attempt per fifteen minutes and skipped whenever another task is already in flight. An automatic run reports failure into controller state instead of raising a dialog, and a run that stops at conflicts uploads nothing, so only a clean run advances the device-local record of when the cloud copy was last complete. That timestamp is deliberately outside every snapshot and portable backup: it describes what this device uploaded, and a restored copy of another phone's value would claim a backup that never happened here.

A portable restore arms a durable sync gate before it mutates local data. Ordinary synchronization remains blocked until the user either resumes normal conflict-aware merging or explicitly publishes the restored snapshot as the authoritative remote copy. Authoritative publishing uses conditional ETags and marks rows synchronized only after the snapshot and documents succeed.

AppFolder isolation prevents direct reads from the former apps’ folders. Legacy exports are selected explicitly through Android’s file picker, read without modification, and passed through the previewed import pipeline. Import hashes prevent accidental repeats, deterministic identifiers make retries safe, and an audit table supports rollback.

## Lab plans

The model may select only biomarkers present in the catalog. Local validation rejects unknown IDs, duplicate markers, invalid evidence labels, missing rationales, or missing tiers. Prices are always replaced with catalog prices. A biomarker is stored once at the tier where it is first added; `itemsThrough()` constructs the cumulative checklists and totals deterministically.

Every candidate plan carries a receipt for the complete immutable health-context package, including its overall hash, file hash, record count, section names, and section hashes. A second stateless provider call to the same configured model receives the same lossless context plus only the parsed candidate data. It must return its own matching receipt and approve without blocking issues. Malformed, incomplete, mismatched, or rejected verification fails closed. Approved plans persist the model/provider identity, context hash, verification summary, warnings, sources, and timestamp, and preserve that audit record through checklist updates and exports.
