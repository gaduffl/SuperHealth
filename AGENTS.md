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

**Units have one spelling, enforced on write.** `HealthRepository` canonicalises
every unit column and every unit inside `ingredients_json` before insert — not
the UI, because imports, sync and the AI parser all write too, and normalising
in two screens is how one real library ended up holding `microgram`, `µg`, `IE`
and `IU` for the same quantity. Supplement, ingredient and event units come from
the closed `CanonicalUnit` enum in `lib/domain/units.dart`; an unrecognised one
is preserved rather than coerced, so a data-entry mistake stays visible.
Biomarker units deliberately do **not** use that enum — lab reports carry an open
set of notations (37 distinct spellings in one real export) and rejecting one
would mean refusing a genuine report, so they go through
`UnitConversionService.normalizeUnit`, which canonicalises rather than rejects.

**A substance has an identity separate from its spelling.** `SubstanceCatalog`
maps "Vitamin C"/"Vitamin c" and "B12"/"Vitamin B12" onto one id; anything it
does not know falls back to its own folded name. Group by
`groupingKeyFor(name)`, never by the raw string. Note that a named salt
("Eisen(II)-sulfat") is deliberately *not* the element — its mass includes the
counter-ion.

**IU is not a mass.** There is no generic IU↔µg factor: one IU is 0.025 µg of
vitamin D, 0.3 µg of vitamin A, and 0.67 mg of vitamin E. `SubstanceConversions`
holds a small substance-scoped table and returns null for anything outside it.
Returning null means "keep the series separate", never zero.

**Units never mix.** Values are only summed within one canonical unit. Tag
value modes (`TagValueMode.occurrence`/`intensity`/`amount`) decide how a day's
entries reduce — count, mean, or sum-within-unit. Supplement ingredient exposure
keeps separate units separate rather than adding them, and an ingredient is
identified by its name *and* unit everywhere, because the same substance logged
in IU and in µg is two series. Adding a code path that sums across units is a
correctness bug even when it type-checks. Where two quantities genuinely cannot
be converted — a blood concentration and a daily intake — give them separate
axes rather than a shared scale, as the `TrendChart` dose underlay does.

**A snapshot can be a missing record rather than a record of nothing.**
`SupplementIntake.ingredientSnapshot` is captured at log time and stays empty
forever if the product had no ingredients entered yet — 94% of intakes in one
real library. Anything reading it must fall back to the product's current
ingredients, or it computes from the remaining 6% and is wrong by more than an
order of magnitude.

**Missing data is not zero.** A day with nothing logged and a day with a
deliberate zero must not render identically; `DoseBucket.tracked` carries that
distinction and the chart shades untracked spans instead of drawing a zero bar.
By the same rule, a chosen option that yields nothing to draw has to say so —
an empty chart is indistinguishable from a broken feature.

**Ingredient fields are optional, and products need not have ingredients at
all.** `IngredientEditor` omits the `unit` key entirely when the box is left
empty, and omits `amount` likewise, so anything requiring them silently drops
real entries. An intake logged before its product was broken down carries an
empty `ingredientSnapshot` and needs the product's current ingredients as a
fallback. Treat a supplement with no ingredient rows as a first-class case: it
is still logged as a dose in some unit, which is what `DoseTarget.supplement`
follows.

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

**A feature reachable only by an icon is a feature nobody finds.** Tooltips need
a long-press on touch, so an icon-only `IconButton` carries no label at all on a
phone. The lab-report PDF import spent months looking deleted for exactly this
reason: a screen restructure pushed it behind a navigation push *and* left it as
a bare icon beside a labelled button. Primary flows get a labelled card on the
screen that owns them. When restructuring a screen, check what the old layout
surfaced that the new one buries, and assert the shortcut in a widget test —
code that still exists is not the same as a feature the owner can reach.

**A flow used from two screens is a top-level function, not a method.** Private
top-level functions in the screen file (`_importLabPdf`) let a second entry point
call exactly the same code. Copying the flow into the second screen is how two
paths drift into behaving differently.

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

**Bump `version:` in `pubspec.yaml` in every PR**, both parts — `0.8.4+19` →
`0.9.0+20`. This is not optional and not only for user-facing work. Merging to
`main` runs the release job, which publishes a GitHub Release tagged from that
version and *fails the build* if the tag already exists, because Android refuses
to install an update carrying a versionCode it already has. Forget it and `main`
goes red after the merge, when the PR that caused it is already closed. Raise
the minor for a feature or a schema migration, the patch for a fix or a
refinement; the build number always increments by exactly one.

**A release that did not run is recovered by dispatching, not by an empty
commit.** The push to `main` is the normal trigger, but runs do get cancelled
and runners do go unassigned, and then the version sits merged and unreleased.
`workflow_dispatch` on `main` publishes too, so re-running the workflow from the
Actions tab finishes the job. Whether a run publishes is decided once, by the
`gate` step of `verify`; both the release job and verify's own APK steps read
that single output, so the APK is built exactly once per run. Do not re-express
that condition inline — two copies of it drift, and the failure is silent in
both directions (an APK built twice, or a release that never builds one).

**The AI context is scoped per flow.** `HealthContextScope.labPlanning` carries
the whole biomarker catalog because the planner must be able to propose and
price a test never run; `advisory` carries only measured markers. Supplements are
filtered to the active profile, and the raw inventory ledger is not shipped at
all — `household_stock_levels` carries the useful part in one row per item. One
shared context could not serve both flows without wasting most of it on
whichever did not need it.

**Keep this file current.** When a change adds, removes, or alters a convention
described here — a new layer under `lib/`, a different verification command, a
new invariant a future agent could violate without noticing — update AGENTS.md
in the same PR. A stale entry is worse than a missing one, because it gets
trusted. Record the constraint and its consequence, not a changelog of what you
did.

## Not audited

A data-model audit in August 2026 covered units, ingredient identity, the
`ingredients_json` blob, `use_score`/`value_mode` redundancy, and the
product-vs-ingredient duality. It deliberately did **not** cover the following,
which remain unexamined rather than known-good:

- Sync and merge conflict semantics, and the `sync_shadow` / `sync_conflicts`
  tables.
- Document and PDF handling, hashing, and the import/rollback audit trail.
- Lab plan tier construction and price arithmetic.
- The advisor workspace file-proposal safety model.
- Reminder scheduling and its DST behaviour.
- Soft-delete consistency across all tables — spot-checked on event definitions
  only, where it was found intact.
- ID generation and collision risk.
- The backup/restore checksum scheme.
- Localisation coverage beyond unit and migration strings.
- Index coverage and query performance on the larger tables.
