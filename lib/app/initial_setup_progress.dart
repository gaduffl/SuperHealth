import 'package:shared_preferences/shared_preferences.dart';

/// Device-local facts recorded only after an explicit setup action succeeds.
///
/// These facts are intentionally not synchronized: API keys, OneDrive device
/// authorization, and the initial setup of a second phone must remain local to
/// that device.
class InitialSetupFacts {
  const InitialSetupFacts({
    this.legacyJsonImported = false,
    this.legacyJsonSkipped = false,
    this.legacyPdfsAttached = false,
    this.legacyPdfsSkipped = false,
    this.dataRestored = false,
    this.firstSuccessfulSync = false,
    this.cloudSkipped = false,
    this.aiSkipped = false,
  });

  final bool legacyJsonImported;
  final bool legacyJsonSkipped;
  final bool legacyPdfsAttached;
  final bool legacyPdfsSkipped;
  final bool dataRestored;
  final bool firstSuccessfulSync;
  final bool cloudSkipped;
  final bool aiSkipped;
}

/// Immutable setup snapshot composed from [InitialSetupFacts] and live state.
class InitialSetupProgress {
  const InitialSetupProgress({
    required this.profileExists,
    required this.legacyJsonImported,
    required this.legacyJsonSkipped,
    required this.legacyPdfsAttached,
    required this.legacyPdfsSkipped,
    required this.dataRestored,
    required this.oneDriveReady,
    required this.firstSuccessfulSync,
    required this.cloudSkipped,
    required this.advisorReady,
    required this.aiSkipped,
  });

  const InitialSetupProgress.empty()
    : profileExists = false,
      legacyJsonImported = false,
      legacyJsonSkipped = false,
      legacyPdfsAttached = false,
      legacyPdfsSkipped = false,
      dataRestored = false,
      oneDriveReady = false,
      firstSuccessfulSync = false,
      cloudSkipped = false,
      advisorReady = false,
      aiSkipped = false;

  final bool profileExists;
  final bool legacyJsonImported;
  final bool legacyJsonSkipped;
  final bool legacyPdfsAttached;
  final bool legacyPdfsSkipped;
  final bool dataRestored;
  final bool oneDriveReady;
  final bool firstSuccessfulSync;
  final bool cloudSkipped;
  final bool advisorReady;
  final bool aiSkipped;

  bool get legacyJsonHandled =>
      dataRestored || legacyJsonImported || legacyJsonSkipped;

  bool get legacyPdfsHandled =>
      dataRestored || legacyPdfsAttached || legacyPdfsSkipped;

  bool get cloudHandled =>
      cloudSkipped || (oneDriveReady && firstSuccessfulSync);

  bool get advisorHandled => advisorReady || aiSkipped;

  bool get isComplete =>
      profileExists &&
      legacyJsonHandled &&
      legacyPdfsHandled &&
      cloudHandled &&
      advisorHandled;

  @override
  bool operator ==(Object other) =>
      other is InitialSetupProgress &&
      profileExists == other.profileExists &&
      legacyJsonImported == other.legacyJsonImported &&
      legacyJsonSkipped == other.legacyJsonSkipped &&
      legacyPdfsAttached == other.legacyPdfsAttached &&
      legacyPdfsSkipped == other.legacyPdfsSkipped &&
      dataRestored == other.dataRestored &&
      oneDriveReady == other.oneDriveReady &&
      firstSuccessfulSync == other.firstSuccessfulSync &&
      cloudSkipped == other.cloudSkipped &&
      advisorReady == other.advisorReady &&
      aiSkipped == other.aiSkipped;

  @override
  int get hashCode => Object.hashAll([
    profileExists,
    legacyJsonImported,
    legacyJsonSkipped,
    legacyPdfsAttached,
    legacyPdfsSkipped,
    dataRestored,
    oneDriveReady,
    firstSuccessfulSync,
    cloudSkipped,
    advisorReady,
    aiSkipped,
  ]);
}

/// Persists explicit, device-local initial-setup outcomes.
class InitialSetupProgressStore {
  InitialSetupProgressStore({
    Future<SharedPreferences> Function()? preferencesProvider,
  }) : _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance;

  static const _legacyJsonImportedKey = 'initial_setup_legacy_json_imported';
  static const _legacyJsonSkippedKey = 'initial_setup_legacy_json_skipped';
  static const _legacyPdfsAttachedKey = 'initial_setup_legacy_pdfs_attached';
  static const _legacyPdfsSkippedKey = 'initial_setup_legacy_pdfs_skipped';
  static const _dataRestoredKey = 'initial_setup_data_restored';
  static const _firstSuccessfulSyncKey = 'initial_setup_first_successful_sync';
  static const _cloudSkippedKey = 'initial_setup_cloud_skipped';
  static const _aiSkippedKey = 'initial_setup_ai_skipped';

  final Future<SharedPreferences> Function() _preferencesProvider;

  Future<InitialSetupFacts> loadFacts() async {
    try {
      final preferences = await _preferencesProvider();
      return InitialSetupFacts(
        legacyJsonImported:
            preferences.getBool(_legacyJsonImportedKey) ?? false,
        legacyJsonSkipped: preferences.getBool(_legacyJsonSkippedKey) ?? false,
        legacyPdfsAttached:
            preferences.getBool(_legacyPdfsAttachedKey) ?? false,
        legacyPdfsSkipped: preferences.getBool(_legacyPdfsSkippedKey) ?? false,
        dataRestored: preferences.getBool(_dataRestoredKey) ?? false,
        firstSuccessfulSync:
            preferences.getBool(_firstSuccessfulSyncKey) ?? false,
        cloudSkipped: preferences.getBool(_cloudSkippedKey) ?? false,
        aiSkipped: preferences.getBool(_aiSkippedKey) ?? false,
      );
    } on Object {
      return const InitialSetupFacts();
    }
  }

  Future<void> recordLegacyJsonImported() => _set(_legacyJsonImportedKey);

  Future<void> recordLegacyJsonSkipped() => _set(_legacyJsonSkippedKey);

  Future<void> recordLegacyPdfsAttached() => _set(_legacyPdfsAttachedKey);

  Future<void> recordLegacyPdfsSkipped() => _set(_legacyPdfsSkippedKey);

  Future<void> recordDataRestored() => _set(_dataRestoredKey);

  Future<void> recordFirstSuccessfulSync() => _set(_firstSuccessfulSyncKey);

  Future<void> recordCloudSkipped() => _set(_cloudSkippedKey);

  Future<void> recordAiSkipped() => _set(_aiSkippedKey);

  Future<void> _set(String key) async {
    final preferences = await _preferencesProvider();
    await preferences.setBool(key, true);
  }
}
