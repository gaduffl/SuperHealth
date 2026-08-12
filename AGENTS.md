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

**A screen that says "today" must re-derive the day, not capture it.** The app
is left open and backgrounded for days, so a `DateTime.now()` stored in a
`State` field at launch is stale by morning — `DashboardScreen` showed its launch
day under a header printing the real date, and checked doses off against the
wrong one. Re-sync on build, on `AppLifecycleState.resumed`, and on a timer to
the next midnight; the widget takes an injectable `clock` so a test can turn the
calendar over without waiting.

**A per-item opt-in that defaults to off needs a way to see it and a way to set
it in bulk.** `SupplementSchedule.reminderEnabled` defaults to false and lived
only inside the edit dialog, so a whole library could have every reminder off
while Settings advertised the feature — indistinguishable from reminders being
broken. The schedule row now carries a badge and Settings can switch them all on.
Apply the same test to any new per-row flag: can its state be seen from the list,
and is there a path that does not mean opening every row?

**Silent skips need a public predicate.** `ReminderPlanner.plan()` drops a
schedule whose `timeOfDay` it cannot parse, which is correct but invisible.
`canScheduleReminder()` exposes exactly that decision so the UI flags the row
instead of keeping a second copy of the parsing rules that would drift. When a
planner or service silently discards input, give callers the same question it
asked.

**An Android notification channel is immutable after its first creation.**
Importance, sound and vibration are frozen the moment the channel is created and
every later change is ignored for the life of the install. Correcting any of them
means a **new channel id** (`..._v2`) plus deleting the old one, or the fix
reaches only fresh installs. Create channels explicitly at initialize rather than
letting the first notification create them implicitly.

**A dose reminder needs an exact alarm.** `inexactAllowWhileIdle` is batched by
Doze and routinely lands hours late, which is indistinguishable from a reminder
that never came. Schedule exact when Android grants the right (`USE_EXACT_ALARM`
on 14+, `SCHEDULE_EXACT_ALARM` on 12-13) and fall back to inexact when it is
withheld — never treat "unknown" as granted, because scheduling an exact alarm
without the right throws and one throw aborts the rest of the batch.

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

**An AI flow sends only what its job needs.** Lab price updates send the
biomarker catalog and nothing else — no measurements, no supplements, no
symptoms — because pricing does not need them. Before adding a flow, ask what
the smallest input that answers the question is, rather than reaching for the
health context because it already exists.

**A call that runs for minutes reports what it is doing.** `LabPlannerService`
takes an `onProgress` callback and names each stage; the screen shows the stage
and a running clock rather than only greying a button, because a still screen
and a hung request look identical. Progress reporting never throws — commentary
must not cost the caller their result.

**A stage label is not enough on its own.** There are only four stage changes
across several minutes, so between them the screen is as still as a hang.
`ProviderActivity` carries the live byte counts and a bounded tail of the
model's reasoning out of the SSE loop, and the card shows them. The *point* is
diagnostic: a count that keeps moving proves the run is slow, not stuck.

**`labPlanHasGoneQuiet` is the stall signal, and it stays quiet when it does not
know.** A null `lastActivityAt` covers both "has not started producing" and
"this provider does not stream at all" — neither is evidence of a stall, and a
warning that fires on both is one nobody reads. The 90-second threshold is
deliberately generous for the same reason.

**Stream deltas are coalesced, never forwarded raw.** `ActivityReporter` emits
at most once per 400 ms and flushes at the end; a long turn delivers thousands
of deltas, and one rebuild each would spend the call redrawing a progress card.
It also bounds the retained reasoning tail on write, so a long trace cannot grow
without limit, and it swallows listener exceptions — it is called from inside
the SSE loop, where a throw would abort a response that was arriving fine.

**The lab planner writes a diagnostic trace as it runs, not at the end.**
`LabPlanTrace` appends a JSON line per milestone straight to disk, because the
runs worth explaining are the ones that never reach an end — and an in-memory
record dies with the process that lost the plan. A run with no `run_end` is
therefore itself the finding, and `formatTraceReport` names it "NEVER FINISHED"
rather than leaving an absence the reader has to notice.

**The trace records everything except the health context.** Model responses are
kept in full (bounded to 20k chars per field) because an unparseable response is
the artefact being diagnosed; the context is kept as sha, size and record count
only, since it is megabytes, reproducible, and the most sensitive thing here.
The exported file still names biomarkers, so every surface that offers it says
so — an export that undersells what it contains is a privacy bug.

**Trim the trace when a run starts, never when it ends.** Trimming after a run
is how the evidence for the last failure disappears exactly when it is wanted.
`trimTraceToRuns` also cuts on run boundaries: a run truncated at the top reads
like a generation that began halfway through.

**Dense JSON is ~2.3 bytes per token, not 3.5.** Measured, not guessed: a
2,020,279-byte package billed 847,443 input tokens. The old divisor under-counted
by 46%, which let `deliveryFor` pass a package as "inline" whose true size
overshot the 0.72 working-room budget that check exists to defend — a quality
guard silently bypassed, not merely a bad display number. Use
`estimatedJsonTokens`, and keep it erring *high*: over-estimating routes to the
lossless file path, under-estimating degrades answers near the context limit.

**Every AI role that costs real money gets its own `AiTask`.** Lab planning
used to read `advisorSettings`, so the most expensive call in the app silently
ran on whatever the advisor was set to — a user who picked a cheaper model for
it had no way to find out except the bill. `AiTask.labPlanner` falls back to the
advisor's settings on load, because that is what existing installs have been
using and showing it is the truth.

**The verifier reviews the question that was asked.** `priorities` reaches both
passes. It used to reach only the draft, so the reviewer saw tests omitted, found
no justification in the stored record, and blocked a plan that was doing exactly
what the user requested. `verificationInstructionBlock` passes the instruction as
*data*, and is explicit that it justifies an omission without excusing it: a
clinically significant omission still returns, as a `warning` rather than a
`blocking_issue`. A reviewer that approves whatever it is told is not a review.

**Never gate correctness on a model transcribing data it cannot compute.** The
context receipt used to demand a verbatim echo of all 19 section digests —
1,344 characters of random hex — and a run that produced an approved 43-item
plan was thrown away because one of them came back 63 characters instead of 64.
It proved nothing, either: the model *copies* those digests out of the manifest
rather than deriving them, so a correct echo showed manifest access, which
`sha256`, `file_sha256`, `record_count` and the section enumeration already
show at a fraction of the surface. Ask what a receipt field proves that the
cheaper fields do not, and price in the transcription failure rate before
making it a gate.

**A cheaper tier must say what it gives up.** Three tiers with different
lengths do not explain themselves: nothing on screen tells the reader whether
the missing tests were reasoned about or fell off the end. Each of the two
cheaper tiers carries the count, the names, the price delta, and the planner's
reasoning. Only the last of those comes from the model — the rest are derived
from the plan, so the list can never disagree with the plan it describes.
`itemsOmittedVersusNext` is exactly the next tier's own additions, because
tiers are cumulative and each item names the tier that adds it. The reasoning
is prose, not a gate: a tier without it says so and still shows the gap.

**Rebuild a record with `copyWith`, never by re-listing its fields.** Two call
sites re-typed all seventeen `LabPlan` fields to change one, which is how a
newly added field silently stops being persisted — `_withVerification` would
have dropped `tierTradeoffs` on every approved plan. A test asserts that
`copyWith` carries what it does not replace.

**A widget must not hold the record it was opened with.** The biomarker detail
sheet kept the `Biomarker` it was constructed with and a non-listening
`AppController`, so it was frozen at open time. Its own Edit action then
re-seeded the form from that frozen copy: a saved price went to the database
and vanished from the field, which is indistinguishable from the save having
failed. Pass identity, resolve from the controller inside `build`, and handle
the record having been deleted meanwhile.

**A migration fixture needs every table a later migration will touch.** The
fixtures in `test/data/` build deliberately small databases, which stays honest
right up until a new migration alters a table they left out — v12 added a
column to `lab_plans` and broke four fixtures that had never created it. Shared
definitions live in `test/data/legacy_schema.dart`; add a table there when a
migration starts altering it.

**A second-pass parse failure must not discard the first pass.** An unreadable
verification means the plan is *unverified* — which `approved: false` states
and `canSave` already enforces — not that a complete, paid-for draft is
worthless. `_verify` catches `LabPlanFormatException` and returns an
unapproved verification carrying the parse error as a blocking issue, so the
user can still read the plan. Everything else — a dropped connection, a refusal
— is a failure of the *call* rather than of the answer, and still rethrows.

**Nothing in the context package may vary per build.** OpenAI caches the longest
matching prefix, and the prefix covers the structured-output schema, the tool
definitions and the whole input. `generated_at` sorted ahead of `raw_ledger`, so
a fresh timestamp made every run a guaranteed cold prefill of ~600k tokens.
`packageDateFor` quantises it to the UTC day: precise enough to reason about
result age, byte-identical across a day's runs. Before adding any field to the
package, check whether it changes when the data has not.

**Draft and verify can never share a cache, and that is deliberate.** Their
structured-output schemas differ, and the schema is a *prefix to the system
message*, so the two prefixes diverge at position zero. Unifying them would mean
giving up schema-constrained output on the draft, where it pins 42 items to exact
catalog ids. Cross-run caching wins the same tokens without that cost — priorities
live in the trailing user message, so re-running with a different instruction
still hits.

**The cache key is the catalog fingerprint, and it refuses to guess.** Keying
on the whole-context hash sends every run to a cold node, because that hash
changes on every logged dose. `catalogFingerprintOf` hashes only the invariant
sections — and returns *null* when none of them resolve, rather than a
fingerprint over absences. That constant was a real bug caught by a test: one
cache key shared by every profile and every catalog state, where a stale prefix
could serve a plan. The caller falls back to the whole-context hash, which is
merely less cacheable. Section names there must match `completeProfileSnapshot`
exactly (`biomarker_catalog`, not `biomarkers`).

**The manifest proves coverage with a count and a hash, not a list of ids.**
`_sectionMetadata` used to emit `record_ids` for every section — ids already
present in the rows they belong to, costing ~78 KB (~33k tokens) per call on a
real profile for nothing the content hash did not already cover. Nothing ever
read them. Before adding a field to the manifest, ask what it proves that
`records` + `sha256` does not. The `ids` list is still built, purely to reject
duplicates.

**A row carries evidence, not columns.** `created_at`/`updated_at` say when a
row was written or corrected, never when the thing happened — every section has
its own clinical date. `deleted` is 0 on every carried row because the queries
filter on it. `color_value` is what a tag is drawn in. `profile_id` repeats
`active_profile_id` 36 characters at a time on every clinical row. Together
with dropping keys whose value would be null, `""`, `[]` or `{}`, that was 31%
of the advisor's package. Numbers are never dropped: a `0` dose and an absent
dose are different facts.

**An omission the model cannot see is a lie by construction.** The reading
protocol says never to infer that a record is absent, so every reason a *key*
can be missing is spelled out in `coverage_contract.row_encoding` — empty means
"nothing recorded", bookkeeping is listed by name, `profile_id` is present only
where it differs. Trim nothing from a row without adding its rule there.

**An index that transcribes the ledger is not an index.** `chronology` emitted
one entry per record — `{at, section, record_ref, date_field}` — and all four
values were already in the row it pointed at. 446 KB on a real profile, a
quarter of the package, to sort rows the model can sort; the per-section range
it summarised was already in `manifest.sections` as `earliest`/`latest`. Before
adding to `attention_index`, ask what it computes that the ledger does not
already state.

**A summary is not a window, and `lossless` has to be withdrawn for one.** A
window removes rows and declares it; what survives is still verbatim. A summary
keeps every record but stops carrying it row by row — so `manifest.lossless`
becomes false the moment one is present, `summarised` names the section, and
the declaration states its grain, what it preserves and what it **loses**.
`supplement_intakes_weekly` covers every dose older than the advisor's eight
weeks at one row per supplement-week: 1,171 rows became 284, and the time of
day, per-dose notes and individual ids are gone. Saying so is the price of
being allowed to do it.

**A count derived from a windowed section must say what it counted.**
`_supplementExposure` reports `carried_*` for the rows in the package and
`ledger_*` from `supplement_intake_history`, which spans the whole ledger.
Unlabelled, "first recorded 3 weeks ago" reads as "started 3 weeks ago" when it
means "the window starts 3 weeks ago" — the exact confusion the index exists to
prevent.

**A question joins the conversation only once it has an answer.** `ask` used to
save the user message before the model call, so every failed turn — a rejected
cache key, a dropped stream, a coverage failure — left one behind. The screen
restores the text into the input box and reports the error, so the user believes
the turn never happened, while every later turn silently re-sent it. Both
messages are now saved together at the end, and `conversationHistory` replays
only complete question-and-answer pairs, which heals conversations that already
collected danglers without deleting anything the user might still want to read.

**Conversations are derived from their messages, not stored beside them.** A
conversations table would need a title column duplicating the first question, a
row created before anything had been said, and a migration — while
`advisor_messages` already carries every fact `AdvisorConversation` holds. The
consequence is that a conversation nobody has spoken in does not exist, which is
the right answer: starting one and backing out leaves nothing to tidy up.
Existing installs keep `primary` as an ordinary conversation.

**"Unresolved" is a different state from "the default".** The active
conversation is null until a refresh picks the most recent one, and any explicit
choice — opening one, deleting into a fallback, starting a new one — sets it.
Inferring the difference from an empty message list instead sent every restart
to `primary`, which for anyone with history is the *oldest* thread rather than
where they left off. When a field means both "nobody has chosen yet" and a real
value, make the first one null.

**Every model call that costs money gets a trace.** `AiTrace` is not lab-planner
specific: one `AiTraceStore` per feature, each with its own file, because a lab
plan and an advisor turn are different questions and interleaving them makes
"which run was this" the reader's first problem. The advisor had none, so
`cached_tokens` — the only evidence that a prompt cache key earns anything — was
unobservable on the app's most repetitive call. A claim about tokens that no
trace can confirm is a guess.

**The release build downloads Gradle, so it can fail for reasons this repo
does not control.** A dropped connection to `services.gradle.org` lost the
v0.30.0+50 release outright — `verify` had passed on the same commit and the
diff touched no Android config. `~/.gradle/caches` and `~/.gradle/wrapper` are
cached so the download stops happening, and the APK build retries three times.
Retrying a *build* is only defensible because `flutter analyze` and
`flutter test` run first: a Dart error cannot reach that step, so three
failures mean a real Android or signing problem rather than a flake.

**A release that never published can reuse its version; one that did, cannot.**
The publish step refuses to overwrite an existing tag from a different commit,
because a new build under an old versionCode is one Android will not install as
an update. When the tag does not exist, the version is still free.

**A retry must send the same tools as the call it retries.** Tool definitions
are part of the cached prefix and sit ahead of the input, so turning web search
off for the advisor's repair pass moved the prefix at position zero: a measured
run wrote 313k tokens and then read back **nothing** on a repair issued seconds
later with the same key and the same context. Suppressing one search bought a
second full prefill of the whole package. Change the trailing prompt on a
retry; never the tools, the system prompt, or the schema.

**A cache that expires before the user replies is not a cache.** The default
prompt cache lives in memory for a few minutes — shorter than reading a
6,000-character answer and typing a follow-up — so a chat's second turn was
re-prefilling a context that had not changed by a byte. `prompt_cache_retention:
'24h'` travels with the key, and only with the key: a hint the provider might
reject must never go on its own.

**Work in flight has to be visible somewhere.** Nothing is written until the
answer arrives, which is what keeps a failed turn out of the history — and it
also meant the question vanished on send: cleared from the input box, absent
from the thread, welcome screen still showing. `pendingAdvisorQuestion` carries
it for exactly the duration of the call. Whenever a write is deferred until
success, ask where the user sees the thing they just did.

**The advisor is where prompt caching pays, not the lab planner.** A chat
re-sends the entire context on every turn; the planner runs twice and stops. The
advisor had no `promptCacheKey` at all. Both now key on the catalog fingerprint
through `ProviderRequest.cacheKey`, which is bounded by construction — a key one
character over the limit fails the whole call before a token.

**Never discard a provider error payload you do not recognise.** The OpenAI
handler read only `event['message']`, so a nested shape produced the literal
string "OpenAI stream error." with the real reason thrown away — and
`response.failed` was returned like a success, so the caller reported "returned
no text output" instead of the error the API had just given.
`describeProviderError` checks every known nesting and, failing all of them,
includes a bounded dump of the raw event. An unrecognised payload is exactly the
case where the text matters most.

**A cache hint must never be able to fail the request.** The first
`prompt_cache_key` was a 20-character prefix plus a 64-character SHA — 84
characters against OpenAI's limit of 64 — and the API rejected the whole call
with HTTP 400, killing the generation before a single token. `labPlanCacheKeyFor`
now fits by construction, and `usablePromptCacheKey` drops anything a provider
would reject rather than sending it. Dropping, never truncating: a shortened key
could collide, and one catalog could be served another's prefix. A cold prefill
is an acceptable outcome; no plan is not.

**Routing is not the same as a cache hit.** A cross-run hit also needs the
invariant data to *lead* the payload, and it does not: `stableJson` sorts keys,
so the volatile `attention_index` precedes `raw_ledger` and caps the shared
prefix within the first few hundred bytes. Within one run the context string is
byte-identical, so draft and verify share everything. Do not claim cross-run
caching works until the package is reordered.

**Every call in one logical run shares a `promptCacheKey`.** A lab plan sends the
same ~800k-token context twice, minutes apart. Automatic prefix caching alone
missed completely — 824k written, 832k written again, zero read — costing a
second full prefill of four and a half minutes. The key is derived from the
context hash, so editing one record starts a new cache line rather than reusing
one built from data the plan is no longer about.

**A windowed section must declare itself.** Lab planning carries four months of
`supplement_intakes`, and that is only safe because the package says so:
`manifest.windowed`, `coverage_contract.windowed_sections`, an extra reading-
protocol line, and `complete: false`. The reading protocol tells the model never
to infer that a record is absent — an undeclared window would make that
instruction a lie.

**Windowing a ledger loses duration, so give duration back.** Three years of a
supplement and one month of it are identical inside a four-month slice, and
"long-term exposure" versus "recently started" is exactly what decides whether a
test is worth ordering. `supplement_intake_history` carries first dose, last
dose and count over the *whole* ledger — one row per product. Apply the same
reasoning before windowing anything else.

**A context bound on `DateTime.now()` is not deterministic.** The window cutoff
snaps to a UTC midnight (`labPlanningIntakeCutoff`), because the context hash
identifies a body of evidence: the receipt validates against it and the prompt
cache key is derived from it. An instant-based bound made two builds a second
apart disagree, and the repository tests caught it.

**A generation is three sequential full-context model calls, not one.** Draft,
optional repair, then an independent verification that re-sends the entire
candidate — plus a token-count round trip and, on the file path, a context
upload. Minutes is the expected cost, not a symptom. Before treating slowness as
a bug, check whether the byte counts were moving.

**Backgrounding does not stop a Dart isolate; a sleeping device and a reclaimed
process do.** `LongTaskGuard` answers both — a wakelock against sleep, a
foreground service (`dataSync`) against the kill list. Take it through the guard
rather than either mechanism directly, and remember they are not
interchangeable: only the service survives memory pressure, so a wakelock alone
must never be described as making a long call background-safe.

**Nothing runs inside the foreground service.** The work stays on the main
isolate, where secure storage, the database and the context builder already are;
a second isolate would have to re-establish all three. The service buys process
priority, nothing more — so it takes no task handler and no repeating callback.

**The guard is best effort, and the screen says which it got.** Every platform
call in `LongTaskGuard` swallows its failure: a guard that could not be taken
makes the task fragile, but a guard that threw would lose the task outright.
`hasForegroundService` reports what was actually taken, and the progress card
only promises "you can switch away" when it is true — otherwise it falls back to
telling the user to keep the app open. Holds are refcounted, and `release()`
never stops a service the guard did not start.

**A notification the platform shows needs the user's language at the call
site.** `AppController` cannot resolve `AppLanguage.system` — only the widget
tree knows what the user is reading — so `generateLabPlan` takes a required
`LongTaskNotice` rather than defaulting to English. Do the same for any other
string that leaves the app.

**Android manifest changes are not optional plugin extras.** A foreground
service needs its `<service>` declaration, its `foregroundServiceType`, and the
matching `FOREGROUND_SERVICE_*` permission in
`android/app/src/main/AndroidManifest.xml`. `flutter_foreground_task`'s own
manifest contributes neither the service nor the typed permission, and the
failure is silent at build time and fatal at runtime.

**Easy mode is per profile, and its capabilities live in one place.**
`FeatureVisibility` names every difference; screens ask it (`controller
.visibility.stockManagement`) rather than testing `easyMode` inline, because
scattered checks drift until the mode means something different in each corner.
It is not only subtraction: easy mode turns reminders *on* by default and leads
Today with the lab-report shortcut, since hiding screens makes an app smaller
rather than easier.

**A flag that removes features defaults to off.** `Profile.easyMode` defaults to
`false` even though new profiles start simple, because a `Profile` is rebuilt
field by field whenever one is edited — an omitted flag would have made renaming
a profile silently take features away. `createProfile` opts new profiles in
explicitly, so that decision has exactly one home. Apply the same reasoning to
any future flag whose *true* value hides something.

**A package is a price, a list is a recall schedule.** They hold the same
biomarkers for different reasons, so a package is *expanded* into a list rather
than stored in one: "due" is a per-marker question — ferritin every six months,
TSH every twelve — and a bundle-level interval would discard what the list
already knows. `biomarker_list_items.biomarker_id` stays `NOT NULL` for that
reason. Adding a package never overwrites an entry already on the list; the
interval and notes on it were set deliberately.

**A bundle is costed instead of its parts, never as well as them.**
`LabPlanPricing` picks packages greedily by saving and removes their covered
tests from the pool, so overlapping bundles (kleines ⊂ großes Blutbild) cannot
both charge for the markers they share. A package needs at least two planned
tests to apply — one is that test's price under another name. When a covered
test has no individual price the saving is *unknown*, not zero: the bundle is
still applied because it turns an unknown into a number, but it reports
`savingEur == null` rather than inventing one.

**A zero price is an absent price.** The legacy import writes 0 where its source
had no figure, so `priceEur == null` is not the test for "unpriced" — use
`hasLabPrice()` / `Biomarker.hasPrice`. Getting this wrong made a 169-marker
catalog report itself fully priced, hid every one of them from the price updater,
and made `LabPlan.knownTotal` total a tier as if those tests were free.

**A button whose enabled state reads a `TextEditingController` needs
`onChanged`.** Typing does not rebuild the widget on its own, so the button
reads stale text and only comes to life when some unrelated `setState` fires —
which is what happened to "Fetch page" after a paste.

**Batch anything sized by the catalog.** ~170 biomarkers of structured output
overruns the model's output limit, truncating the JSON and losing the entire
run. `LabPriceService.catalogBatchSize` splits the request; a failed batch is
named in the result rather than discarding the batches that worked.

**A model proposal that spends money is never pre-ticked without a source.**
`LabPriceService` requires a verbatim `quote` from the supplied text; a price
the model asserted rather than read goes to review, as does a foreign currency,
a first price, a move beyond ±50%, or a lab name that contradicts the stored
one. Currencies are surfaced, never converted: an exchange rate the app invented
would be a second guess stacked on the first. Ids outside the catalog are
dropped, never created.

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

**`TrackingScreen` does not come up under `flutter_test`.** `pumpWidget` on it
hangs before the first frame completes — reproduced with both `pumpAndSettle`
and bounded `pump`, and unrelated to any recent change. `DashboardScreen` and
`HealthScreen` pump fine, so this is specific to that screen and not yet
diagnosed. Until it is, test catalog logic through a top-level predicate
(`catalogMatchesFilter`) rather than by standing the screen up.

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
- Foreground-service behaviour on a real device. `LongTaskGuard`'s bookkeeping is
  tested against injected seams, but the service actually starting, surviving
  Doze, and stopping cleanly has never run anywhere: CI builds the APK and never
  installs it. Treat the first report from a device as the real verification.
