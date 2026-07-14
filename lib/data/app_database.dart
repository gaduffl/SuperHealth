// ignore_for_file: prefer_initializing_formals

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  // The public parameter name is intentionally clearer than the private field.
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _databasePath = databasePath;

  static const schemaVersion = 2;
  static const fileName = 'super_health.db';

  final DatabaseFactory _factory;
  final String? _databasePath;
  Database? _database;

  static const profileTables = <String>{
    'profiles',
    'supplements',
    'supplement_schedules',
    'supplement_intakes',
    'health_events',
    'documents',
    'measurements',
    'named_health_records',
    'lab_plans',
    'advisor_messages',
  };

  static const synchronizedTables = <String>[
    'profiles',
    'supplements',
    'supplement_schedules',
    'supplement_intakes',
    'health_events',
    'biomarkers',
    'biomarker_ranges',
    'documents',
    'measurements',
    'named_health_records',
    'lab_plans',
    'lab_plan_items',
    'advisor_messages',
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
          weight_kg REAL,
          notes TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await txn.execute('''
        CREATE TABLE supplements (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
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
          dose REAL NOT NULL,
          unit TEXT NOT NULL,
          time_of_day TEXT NOT NULL,
          weekdays_json TEXT NOT NULL DEFAULT '[]',
          instructions TEXT NOT NULL DEFAULT '',
          start_date TEXT,
          end_date TEXT,
          active INTEGER NOT NULL DEFAULT 1,
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
          dose REAL NOT NULL,
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
        CREATE TABLE health_events (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          kind TEXT NOT NULL CHECK(kind IN ('symptom', 'tag')),
          name TEXT NOT NULL,
          observed_at TEXT NOT NULL,
          score INTEGER,
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

      await txn.execute('''
        CREATE TABLE measurements (
          id TEXT PRIMARY KEY,
          profile_id TEXT NOT NULL REFERENCES profiles(id),
          biomarker_id TEXT NOT NULL REFERENCES biomarkers(id),
          document_id TEXT REFERENCES documents(id),
          taken_at TEXT NOT NULL,
          value REAL NOT NULL,
          unit_reported TEXT NOT NULL,
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
          status TEXT NOT NULL DEFAULT 'draft'
        )
      ''');

      await txn.execute('''
        CREATE TABLE lab_plan_items (
          id TEXT PRIMARY KEY,
          plan_id TEXT NOT NULL REFERENCES lab_plans(id) ON DELETE CASCADE,
          biomarker_id TEXT NOT NULL REFERENCES biomarkers(id),
          biomarker_name TEXT NOT NULL,
          tier TEXT NOT NULL CHECK(tier IN ('core', 'advanced', 'comprehensive')),
          priority INTEGER NOT NULL,
          rationale TEXT NOT NULL,
          evidence_class TEXT NOT NULL,
          price_eur REAL,
          preparation TEXT NOT NULL DEFAULT ''
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
          created_at TEXT NOT NULL
        )
      ''');

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

  static const _indexes = <String>[
    'CREATE INDEX idx_supplements_profile ON supplements(profile_id, deleted)',
    'CREATE INDEX idx_schedules_profile ON supplement_schedules(profile_id, active, deleted)',
    'CREATE INDEX idx_intakes_profile_time ON supplement_intakes(profile_id, taken_at)',
    'CREATE INDEX idx_events_profile_time ON health_events(profile_id, observed_at)',
    'CREATE INDEX idx_biomarkers_name ON biomarkers(canonical_name, deleted)',
    'CREATE INDEX idx_measurements_profile_time ON measurements(profile_id, taken_at)',
    'CREATE INDEX idx_measurements_biomarker ON measurements(profile_id, biomarker_id, taken_at)',
    'CREATE INDEX idx_named_records_profile ON named_health_records(profile_id, kind, deleted)',
    'CREATE INDEX idx_lab_plans_profile ON lab_plans(profile_id, created_at)',
    'CREATE INDEX idx_lab_items_plan ON lab_plan_items(plan_id, tier, priority)',
    'CREATE INDEX idx_advisor_conversation ON advisor_messages(profile_id, conversation_id, created_at)',
    'CREATE UNIQUE INDEX idx_import_source_hash ON import_runs(source_hash)',
  ];

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute(
          'ALTER TABLE biomarkers ADD COLUMN is_temporary INTEGER NOT NULL DEFAULT 0',
        );
        await txn.execute('ALTER TABLE documents ADD COLUMN lab_name TEXT');
        await txn.execute(
          "ALTER TABLE documents ADD COLUMN report_comment TEXT NOT NULL DEFAULT ''",
        );
        await txn.execute(
          "ALTER TABLE documents ADD COLUMN parse_status TEXT NOT NULL DEFAULT 'saved'",
        );
        await txn.execute(
          "ALTER TABLE documents ADD COLUMN warnings_json TEXT NOT NULL DEFAULT '[]'",
        );
        await txn.execute(
          "ALTER TABLE documents ADD COLUMN errors_json TEXT NOT NULL DEFAULT '[]'",
        );
        await txn.execute('ALTER TABLE measurements ADD COLUMN page INTEGER');
        await txn.execute('ALTER TABLE measurements ADD COLUMN row_text TEXT');
        await txn.execute(
          'ALTER TABLE measurements ADD COLUMN extraction_confidence REAL',
        );
        await txn.execute(
          "ALTER TABLE measurements ADD COLUMN flags_json TEXT NOT NULL DEFAULT '[]'",
        );
      });
    }
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    await db?.close();
  }
}
