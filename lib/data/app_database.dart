// ignore_for_file: prefer_initializing_formals

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

/// Owns the local, offline-first health ledger.
///
/// This is the first production schema. The earlier SuperHealth prototype was
/// never used for real data, so it deliberately uses a new database file. That
/// keeps the production ownership rules unambiguous instead of trying to infer
/// whether prototype supplements belonged to a person or the household.
class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _databasePath = databasePath;

  static const schemaVersion = 7;
  static const fileName = 'super_health_v1.db';

  final DatabaseFactory _factory;
  final String? _databasePath;
  Database? _database;

  /// Tables whose rows have a direct profile owner.
  static const profileTables = <String>{
    'profiles',
    'supplement_schedules',
    'supplement_intakes',
    'health_event_definitions',
    'health_events',
    'profile_biomarker_targets',
    'documents',
    'measurements',
    'named_health_records',
    'biomarker_lists',
    'lab_plans',
    'advisor_messages',
    'trend_dose_links',
  };

  /// Complete ordered list included in a OneDrive snapshot.
  static const synchronizedTables = <String>[
    'profiles',
    'supplements',
    'supplement_schedules',
    'supplement_intakes',
    'inventory_movements',
    'health_event_definitions',
    'health_events',
    'biomarkers',
    'biomarker_ranges',
    'profile_biomarker_targets',
    'documents',
    'measurements',
    'named_health_records',
    'biomarker_lists',
    'biomarker_list_items',
    'lab_plans',
    'lab_plan_items',
    'advisor_messages',
    'trend_dose_links',
  ];

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final resolvedPath =
        _databasePath ?? path.join(await _factory.getDatabasesPath(), fileName);
    return _factory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
  }

  Future<void> _create(Database db, int version) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE profiles (
          id TEXT PRIMARY KEY,
          display_name TEXT NOT NULL,
          date_of_birth TEXT,
          sex TEXT,
          height_cm REAL,
          weight_kg REAL,
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      // The catalog and inventory are household-owned. Schedules and intakes
      // below remain profile-owned.
      await txn.execute('''
        CREATE TABLE supplements (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          brand TEXT NOT NULL DEFAULT '',
          form TEXT NOT NULL DEFAULT '',
          ingredients_json TEXT NOT NULL DEFAULT '[]',
          units_per_container INTEGER,
          container_count REAL,
          price_eur REAL,
          bioavailability TEXT NOT NULL DEFAULT '',
          notes TEXT NOT NULL DEFAULT '',
          active INTEGER NOT NULL DEFAULT 1,
          low_stock_alerts INTEGER NOT NULL DEFAULT 1,
          low_stock_threshold_units REAL,
          stock_unit TEXT NOT NULL DEFAULT 'unit',
          source_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE supplement_schedules (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          supplement_id TEXT NOT NULL REFERENCES supplements(id),
          dose REAL NOT NULL CHECK(dose >= 0),
          unit TEXT NOT NULL,
          time_of_day TEXT NOT NULL,
          weekdays_json TEXT NOT NULL DEFAULT '[]',
          instructions TEXT NOT NULL DEFAULT '',
          start_date TEXT,
          end_date TEXT,
          active INTEGER NOT NULL DEFAULT 1,
          reminder_enabled INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE supplement_intakes (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          supplement_id TEXT NOT NULL REFERENCES supplements(id),
          schedule_id TEXT REFERENCES supplement_schedules(id),
          taken_at TEXT NOT NULL,
          dose REAL NOT NULL CHECK(dose >= 0),
          unit TEXT NOT NULL,
          skipped INTEGER NOT NULL DEFAULT 0,
          notes TEXT NOT NULL DEFAULT '',
          ingredients_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE inventory_movements (
          id TEXT PRIMARY KEY,
          supplement_id TEXT NOT NULL REFERENCES supplements(id),
          profile_id TEXT REFERENCES profiles(id),
          intake_id TEXT REFERENCES supplement_intakes(id),
          quantity_units REAL NOT NULL,
          occurred_at TEXT NOT NULL,
          reason TEXT NOT NULL CHECK(reason IN
            ('initial', 'purchase', 'intake', 'correction', 'discard', 'import')),
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE health_event_definitions (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          kind TEXT NOT NULL CHECK(kind IN ('symptom', 'tag')),
          name TEXT NOT NULL,
          default_unit TEXT,
          use_score INTEGER NOT NULL DEFAULT 0,
          value_mode TEXT NOT NULL DEFAULT 'occurrence'
            CHECK(value_mode IN ('occurrence', 'intensity', 'amount')),
          portion_amount REAL,
          portion_label TEXT,
          include_in_check_in INTEGER NOT NULL DEFAULT 0,
          color_value INTEGER,
          archived INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE health_events (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          definition_id TEXT REFERENCES health_event_definitions(id),
          kind TEXT NOT NULL CHECK(kind IN ('symptom', 'tag')),
          name TEXT NOT NULL,
          observed_at TEXT NOT NULL,
          score INTEGER CHECK(score IS NULL OR (score >= 0 AND score <= 10)),
          numeric_value REAL,
          unit TEXT,
          duration_minutes INTEGER,
          notes TEXT NOT NULL DEFAULT '',
          color_value INTEGER,
          archived INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
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
      ''');

      // Population/lab reference ranges remain shared catalog evidence.
      await txn.execute('''
        CREATE TABLE biomarker_ranges (
          id TEXT PRIMARY KEY,
          biomarker_id TEXT NOT NULL REFERENCES biomarkers(id),
          range_type TEXT NOT NULL,
          sex TEXT,
          age_min INTEGER,
          age_max INTEGER,
          low REAL,
          high REAL,
          optimal_low REAL,
          optimal_high REAL,
          unit TEXT NOT NULL,
          evidence_label TEXT,
          evidence_url TEXT,
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      // Personal longevity targets never overwrite the shared reference data.
      await txn.execute('''
        CREATE TABLE profile_biomarker_targets (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          biomarker_id TEXT NOT NULL REFERENCES biomarkers(id),
          low REAL,
          high REAL,
          borderline_low REAL,
          borderline_high REAL,
          unit TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'personal',
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE documents (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          file_name TEXT NOT NULL,
          mime_type TEXT,
          sha256 TEXT,
          local_path TEXT,
          one_drive_item_id TEXT,
          document_date TEXT,
          parsed_at TEXT,
          parser_provider TEXT,
          parser_model TEXT,
          lab_name TEXT,
          report_comment TEXT NOT NULL DEFAULT '',
          parse_status TEXT NOT NULL DEFAULT 'saved',
          warnings_json TEXT NOT NULL DEFAULT '[]',
          errors_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      // Reported values are immutable evidence. Canonical values are a
      // deterministic comparison aid and can be recomputed from the raw pair.
      await txn.execute('''
        CREATE TABLE measurements (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          biomarker_id TEXT NOT NULL REFERENCES biomarkers(id),
          document_id TEXT REFERENCES documents(id),
          taken_at TEXT NOT NULL,
          value REAL NOT NULL,
          unit_reported TEXT NOT NULL,
          canonical_value REAL,
          canonical_unit TEXT,
          conversion_status TEXT NOT NULL DEFAULT 'not_required',
          lab_ref_low REAL,
          lab_ref_high REAL,
          page INTEGER,
          row_text TEXT,
          extraction_confidence REAL,
          flags_json TEXT NOT NULL DEFAULT '[]',
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE named_health_records (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          name TEXT NOT NULL,
          kind TEXT NOT NULL CHECK(kind IN
            ('condition', 'medication', 'goal', 'family_history')),
          status TEXT NOT NULL DEFAULT 'active',
          dose REAL,
          unit TEXT,
          schedule TEXT,
          start_date TEXT,
          end_date TEXT,
          priority INTEGER,
          target_date TEXT,
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE biomarker_lists (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          name TEXT NOT NULL,
          description TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE biomarker_list_items (
          id TEXT PRIMARY KEY,
          list_id TEXT NOT NULL REFERENCES biomarker_lists(id),
          biomarker_id TEXT NOT NULL REFERENCES biomarkers(id),
          due_interval_days INTEGER,
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE lab_plans (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
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
      ''');

      await txn.execute('''
        CREATE TABLE lab_plan_items (
          id TEXT PRIMARY KEY,
          plan_id TEXT NOT NULL REFERENCES lab_plans(id),
          biomarker_id TEXT NOT NULL REFERENCES biomarkers(id),
          biomarker_name TEXT NOT NULL,
          tier TEXT NOT NULL CHECK(tier IN ('core', 'advanced', 'comprehensive')),
          priority INTEGER NOT NULL,
          rationale TEXT NOT NULL,
          evidence_class TEXT NOT NULL,
          price_eur REAL,
          preparation TEXT NOT NULL DEFAULT '',
          checked INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE advisor_messages (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          conversation_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          citations_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute(_createTrendDoseLinks);

      await txn.execute('''
        CREATE TABLE sync_shadow (
          table_name TEXT NOT NULL,
          row_id TEXT NOT NULL,
          updated_at TEXT,
          PRIMARY KEY (table_name, row_id)
        )
      ''');

      await txn.execute('''
        CREATE TABLE sync_conflicts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          row_id TEXT NOT NULL,
          conflict_type TEXT NOT NULL,
          local_json TEXT,
          remote_json TEXT,
          detected_at TEXT NOT NULL,
          resolved_at TEXT,
          resolution TEXT
        )
      ''');

      await txn.execute('''
        CREATE TABLE import_runs (
          id TEXT PRIMARY KEY,
          source_type TEXT NOT NULL,
          source_hash TEXT NOT NULL UNIQUE,
          profile_id TEXT,
          preview_json TEXT NOT NULL,
          imported_at TEXT NOT NULL,
          rolled_back_at TEXT
        )
      ''');

      await txn.execute('''
        CREATE TABLE import_audit (
          import_id TEXT NOT NULL REFERENCES import_runs(id),
          sequence INTEGER NOT NULL,
          table_name TEXT NOT NULL,
          row_id TEXT NOT NULL,
          action TEXT NOT NULL,
          before_json TEXT,
          PRIMARY KEY (import_id, sequence)
        )
      ''');

      for (final statement in _indexes) {
        await txn.execute(statement);
      }
    });
  }

  /// Shared by [_create] and [_upgrade] so a fresh install and an upgraded one
  /// cannot drift into different shapes for the same table.
  static const _createTrendDoseLinks = '''
        CREATE TABLE trend_dose_links (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          biomarker_id TEXT REFERENCES biomarkers(id),
          definition_id TEXT REFERENCES health_event_definitions(id),
          ingredient_name TEXT NOT NULL,
          ingredient_unit TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0,
          CHECK ((biomarker_id IS NULL) <> (definition_id IS NULL))
        )
      ''';

  static const _trendDoseLinkIndexes = <String>[
    'CREATE UNIQUE INDEX idx_trend_dose_biomarker ON trend_dose_links(profile_id, biomarker_id) WHERE deleted = 0 AND biomarker_id IS NOT NULL',
    'CREATE UNIQUE INDEX idx_trend_dose_definition ON trend_dose_links(profile_id, definition_id) WHERE deleted = 0 AND definition_id IS NOT NULL',
  ];

  static const _indexes = <String>[
    ..._trendDoseLinkIndexes,
    'CREATE INDEX idx_supplements_name ON supplements(active, deleted, name)',
    'CREATE INDEX idx_schedules_profile ON supplement_schedules(profile_id, active, deleted)',
    'CREATE INDEX idx_intakes_profile_time ON supplement_intakes(profile_id, taken_at)',
    'CREATE UNIQUE INDEX idx_inventory_intake ON inventory_movements(intake_id) WHERE intake_id IS NOT NULL',
    'CREATE INDEX idx_inventory_supplement ON inventory_movements(supplement_id, occurred_at, deleted)',
    'CREATE UNIQUE INDEX idx_event_definition_name ON health_event_definitions(profile_id, kind, name) WHERE deleted = 0',
    'CREATE INDEX idx_events_profile_time ON health_events(profile_id, observed_at)',
    'CREATE UNIQUE INDEX idx_biomarkers_name ON biomarkers(canonical_name) WHERE deleted = 0',
    'CREATE INDEX idx_targets_profile ON profile_biomarker_targets(profile_id, biomarker_id, deleted)',
    'CREATE UNIQUE INDEX idx_targets_active ON profile_biomarker_targets(profile_id, biomarker_id) WHERE deleted = 0',
    'CREATE INDEX idx_measurements_profile_time ON measurements(profile_id, taken_at)',
    'CREATE INDEX idx_measurements_biomarker ON measurements(profile_id, biomarker_id, taken_at)',
    'CREATE INDEX idx_named_records_profile ON named_health_records(profile_id, kind, deleted)',
    'CREATE INDEX idx_lists_profile ON biomarker_lists(profile_id, deleted, name)',
    'CREATE UNIQUE INDEX idx_list_item_active ON biomarker_list_items(list_id, biomarker_id) WHERE deleted = 0',
    'CREATE INDEX idx_lab_plans_profile ON lab_plans(profile_id, created_at, deleted)',
    'CREATE INDEX idx_lab_items_plan ON lab_plan_items(plan_id, tier, priority, deleted)',
    'CREATE INDEX idx_advisor_conversation ON advisor_messages(profile_id, conversation_id, created_at, deleted)',
    'CREATE UNIQUE INDEX idx_import_source_hash ON import_runs(source_hash)',
  ];

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3 || newVersion != schemaVersion) {
      throw StateError(
        'Unsupported SuperHealth database upgrade $oldVersion → $newVersion.',
      );
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE profiles ADD COLUMN height_cm REAL');
    }
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE lab_plans ADD COLUMN verification_summary TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE lab_plans ADD COLUMN verification_warnings_json TEXT NOT NULL DEFAULT '[]'",
      );
      await db.execute(
        "ALTER TABLE lab_plans ADD COLUMN verification_citations_json TEXT NOT NULL DEFAULT '[]'",
      );
      await db.execute('ALTER TABLE lab_plans ADD COLUMN verified_at TEXT');
    }
    if (oldVersion < 6) {
      await db.execute(
        "ALTER TABLE health_event_definitions "
        "ADD COLUMN value_mode TEXT NOT NULL DEFAULT 'occurrence'",
      );
      await db.execute(
        'ALTER TABLE health_event_definitions ADD COLUMN portion_amount REAL',
      );
      await db.execute(
        'ALTER TABLE health_event_definitions ADD COLUMN portion_label TEXT',
      );
      await db.execute(
        'ALTER TABLE health_event_definitions '
        'ADD COLUMN include_in_check_in INTEGER NOT NULL DEFAULT 0',
      );
      // Existing definitions already encode their number semantics: a
      // scored definition (symptoms, and any tag rated 0-10) becomes
      // `intensity`, preserving exactly how it already behaved. A tag with a
      // stored unit but no score becomes `amount`, keeping that unit as the
      // canonical one. Everything else keeps the occurrence default.
      await db.execute('''
        UPDATE health_event_definitions
        SET value_mode = CASE
          WHEN use_score = 1 THEN 'intensity'
          WHEN default_unit IS NOT NULL AND TRIM(default_unit) != '' THEN 'amount'
          ELSE 'occurrence'
        END
      ''');
    }
    if (oldVersion < 7) {
      // A new table rather than added columns, so there is nothing to
      // back-fill: no dose underlay exists until the user confirms one.
      await db.execute(_createTrendDoseLinks);
      for (final statement in _trendDoseLinkIndexes) {
        await db.execute(statement);
      }
    }
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
