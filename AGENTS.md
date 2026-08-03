# AGENTS.md

Working notes for AI coding agents on SuperHealth. Read this before changing
code. For *why* the system is shaped the way it is, read
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — this file covers *how to work in
the repository* without breaking it.

SuperHealth is a private, local-first Flutter health companion: supplements,
symptoms and exposure tags, biomarkers, lab planning, correlations, and a BYOK
AI advisor. It holds one person's real medical history, so the bar for silent
data loss or leaked context is higher than the bar for a missing feature.

## Verify before you claim done

CI (`.github/workflows/flutter.yml`, job `verify`) runs exactly this, and the
formatting gate fails on any diff, so run all four locally in order:

```sh
flutter pub get
dart format lib test          # CI fails if this produces a diff
flutter analyze               # must print "No issues found!"
flutter test                  # whole suite, not just the file you touched
```

Flutter is pinned to **3.44.6** in CI. Use the same version; a newer formatter
reflows files and turns a small diff into a whole-file rewrite.

CI also builds a signed release APK. That step needs repository secrets
(`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`,
`ANDROID_STORE_PASSWORD`) and an Android SDK, so it cannot be reproduced in a
sandbox without them — see [docs/ANDROID_SIGNING.md](docs/ANDROID_SIGNING.md).
If `verify` fails and every Dart step above is clean locally, suspect that
stage (or exhausted Actions minutes) rather than assuming your diff broke it.

Never commit `android/app/upload-keystore.jks`, an API key, a token, or real
health data. `android/local.properties` is tracked but holds only a local
Flutter SDK path — do not commit a machine-specific rewrite of it.

## Layout

| Path | Holds |
| --- | --- |
| `lib/domain/entities.dart` | Every entity, each with `toMap()`/`fromMap()` mirroring its SQLite row |
| `lib/data/app_database.dart` | Versioned schema: `schemaVersion`, `_create`, `_upgrade`, table allowlists |
| `lib/data/health_repository.dart` | The only normal read/write interface to health records |
| `lib/analysis/` | `correlation_service.dart`, `supplement_insights.dart` — all derived numbers |
| `lib/app/app_controller.dart` | `ChangeNotifier` holding loaded state; screens read it, mutate through it |
| `lib/ai/` | Provider clients, context builder, advisor, parsing, lab planner |
| `lib/sync/`, `lib/backup/` | OneDrive snapshot sync, portable backup/restore |
| `lib/ui/` | Screens, dialogs, and `design.dart`/`charts.dart` visual vocabulary |
| `test/` | Mirrors `lib/` one directory per layer |

## Conventions that will bite you

**Schema changes need all three edits.** Bump `AppDatabase.schemaVersion`, add
the column to the `CREATE TABLE` in `_create` (fresh installs), *and* add an
`if (oldVersion < N)` block of `ALTER TABLE` statements in `_upgrade` (existing
installs). Miss the third and every existing user crashes on launch. Back-fill
new columns from whatever already encoded the same meaning rather than leaving
them default — see the v6 `value_mode` back-fill for the shape.

A whole new table is the same three edits plus its allowlists. Hold its DDL in
one `static const` used by both `_create` and `_upgrade`, as `trend_dose_links`
does, so a fresh install and an upgraded one cannot drift apart. Then register
it in `profileTables` (if its rows have a profile owner), in
`synchronizedTables` (or it is silently absent from sync and backup), and add a
`_SynchronizedReference` per foreign key plus a `case` in
`_validateSynchronizedRowSemantics`. A constraint SQLite enforces with `CHECK`
still has to be re-checked there, because a synchronized row arrives as JSON
from another device and is validated before it is written.

Migration tests build a synthetic old database by hand and open it through the
real `AppDatabase`. A fixture only creates the tables that test cares about, so
an unconditional `ALTER TABLE` against a table the fixture omits fails there
while working fine in production. Extend the fixture to match what a real
database of that version had.

**Soft delete, never hard delete.** `repository.softDelete(table, id)` sets
`deleted = 1` and bumps `updated_at`; sync relies on the tombstone. It rejects
tables outside `AppDatabase.synchronizedTables`. Queries filter `deleted = 0`.

**New tables need a home in both allowlists.** `profileTables` marks rows with a
direct profile owner; `synchronizedTables` is the ordered snapshot contract.
Omitting a table from the latter silently excludes it from sync and backup.

**Ids come from `repository.newId()`** (UUID v4), never from a counter.

**Timestamps are stored UTC ISO-8601**, but day bucketing for charts and
correlations is *local* calendar days. Several tests pin DST and year
boundaries; do not "simplify" them into UTC arithmetic.

**Units never mix.** Values are only summed within one canonical unit. Tag
value modes (`TagValueMode.occurrence`/`intensity`/`amount`) decide how a day's
entries reduce — count, mean, or sum-within-unit. Supplement ingredient exposure
keeps separate units separate rather than adding them, and an ingredient is
identified by its name *and* unit everywhere, because the same substance logged
in IU and in µg is two series. Adding a code path that sums across units is a
correctness bug even when it type-checks. Where two quantities genuinely cannot
be converted — a blood concentration and a daily intake — give them separate
axes rather than a shared scale, as the `TrendChart` dose underlay does.

**Missing data is not zero.** A day with nothing logged and a day with a
deliberate zero must not render identically; `DoseBucket.tracked` carries that
distinction and the chart shades untracked spans instead of drawing a zero bar.

**Charts are plotted against real dates.** `TrendChart` positions points by
timestamp, not list index, because measurements arrive at irregular intervals
and equal spacing would make a six-month gap read like a six-day one.

**Correlations must degrade safely.** Events with no resolvable definition keep
the legacy fallback so old data keeps behaving exactly as it did. Preserve that
when touching `correlation_service.dart`.

**Both languages, always.** English and German. Shell strings go through the
typed `AppLocalizations` registry, whose `translationsComplete` guard fails if a
key is missing from either map. One-off screen copy uses
`AppLocalizations.of(context).pick('English', 'Deutsch')`. There is no
untranslated fallback path — do not add one.

**The AI layer gets serialized data, never handles.** `HealthContextBuilder`
produces a read-only snapshot string; provider clients receive that and prompts.
Never pass `AppDatabase`, a SQLite connection, or repository write methods into
`lib/ai/`. Keys and tokens live in secure storage and are outside every snapshot
and export allowlist. Parsed or AI-proposed changes always require explicit user
confirmation before they touch the database or disk.

**Screens render, they do not compute.** Derived numbers belong in
`SupplementInsights` or a service. Follow `lib/ui/design.dart` for surfaces and
`seriesColors` for chart colours; nothing hardcodes a brightness-specific colour
so light, dark, high-contrast, and deuteranomaly palettes all work unchanged.
Charts carry a `semanticLabel`.

## Tests

`flutter_test` plus `sqflite_common_ffi` for real SQLite. Call
`setUpAll(sqfliteFfiInit)`, then build an `AppDatabase(factory:
databaseFactoryFfi, databasePath: inMemoryDatabasePath)` and a
`HealthRepository` over it; close the database at the end. Tests needing a full
`AppController` construct it through a local `_Fixture` helper — copy the one in
`test/app/delete_supplement_test.dart` rather than inventing another shape.

Test names are sentences describing the guarantee ("exposure never combines
mixed reported units and sorts deterministically"), not `test1`. Seed fixture
data only — no real names, no real health values.

Correlation analysis needs at least 7 paired days by default (`minimumPairs`);
a shorter series returns empty and a test asserting `.single` on it will fail
with `Bad state: No element`.

## Comments

The codebase comments *why*, not *what* — a constraint, a rejected alternative,
a consequence that is not visible locally. Match that. Do not add narrating
comments restating the line below them, and do not leave behind commentary about
the change process ("fixed the bug", "as requested"); the diff already says
that.

## Landing a change

Branch from the current `main`, and open a PR rather than pushing to `main`.

**Squash merge, always.** `main` is a linear history of one commit per PR, each
ending in `(#NN)`. A merge commit or a rebased stack of work-in-progress commits
breaks that. Land your own PR once `verify` is green rather than leaving it open
— but green first: a PR that has not passed CI is not ready to merge, and a
stale green on a superseded commit does not count.

Bump `version:` in `pubspec.yaml` when a change should ship as an installable
build — the release job refuses to reuse a version tag, because Android will not
install an update carrying the same versionCode.

**Keep this file current.** When a change adds, removes, or alters a convention
described here — a new layer under `lib/`, a different verification command, a
new invariant a future agent could violate without noticing — update AGENTS.md
in the same PR. A stale entry is worse than a missing one, because it gets
trusted. Record the constraint and its consequence, not a changelog of what you
did.
