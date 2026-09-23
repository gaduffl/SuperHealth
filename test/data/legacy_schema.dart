/// Table definitions old enough to appear in a migration fixture.
///
/// The fixtures in this directory each build a deliberately small database —
/// only the tables the migration under test touches. That stays honest as long
/// as no *later* migration touches a table they left out: the v12 upgrade adds
/// a column to `lab_plans`, and every fixture that had never heard of the
/// table failed with "no such table". A real database at any of those versions
/// has it, so the fixtures carry it too.
///
/// Keep these at the shape a v5 database already had. A migration that alters
/// one of these tables belongs here as well, so the next one does not have to
/// rediscover the same failure.
library;

const legacyBiomarkersTable = '''
  CREATE TABLE biomarkers (
    id TEXT PRIMARY KEY,
    canonical_name TEXT NOT NULL,
    display_name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT '',
    default_unit TEXT NOT NULL DEFAULT '',
    price_eur REAL,
    lab_name TEXT,
    price_checked_at TEXT,
    description TEXT NOT NULL DEFAULT '',
    synonyms_json TEXT NOT NULL DEFAULT '[]',
    is_temporary INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )
''';

const legacyLabPlansTable = '''
  CREATE TABLE lab_plans (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL,
    title TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    planned_for TEXT,
    currency TEXT NOT NULL DEFAULT 'EUR',
    context_hash TEXT NOT NULL,
    provider TEXT,
    model TEXT,
    status TEXT NOT NULL DEFAULT 'draft',
    verification_summary TEXT NOT NULL DEFAULT '',
    verification_warnings_json TEXT NOT NULL DEFAULT '[]',
    verification_citations_json TEXT NOT NULL DEFAULT '[]',
    verified_at TEXT,
    deleted INTEGER NOT NULL DEFAULT 0
  )
''';

const legacyBiomarkerListsTable = '''
  CREATE TABLE biomarker_lists (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )
''';

const legacyBiomarkerListItemsTable = '''
  CREATE TABLE biomarker_list_items (
    id TEXT PRIMARY KEY,
    list_id TEXT NOT NULL,
    biomarker_id TEXT NOT NULL,
    due_interval_days INTEGER,
    notes TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted INTEGER NOT NULL DEFAULT 0
  )
''';
