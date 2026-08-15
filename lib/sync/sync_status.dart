import 'package:shared_preferences/shared_preferences.dart';

/// Device-local record of when this phone last completed a full OneDrive sync.
///
/// Deliberately outside every snapshot and portable backup. It describes what
/// *this* device has uploaded, so restoring another phone's copy of it would
/// claim a backup that never happened here.
class SyncStatusStore {
  SyncStatusStore({Future<SharedPreferences> Function()? preferencesProvider})
    : _preferencesProvider =
          preferencesProvider ?? SharedPreferences.getInstance;

  static const _lastSuccessKey = 'onedrive_last_successful_sync_at';

  final Future<SharedPreferences> Function() _preferencesProvider;

  /// The last completed sync, or null when this device has recorded none.
  ///
  /// A storage or parse failure reads as "never synchronized". This value only
  /// ever prompts the user towards syncing again, so failing in that direction
  /// can understate how fresh the cloud copy is but never overstate it.
  Future<DateTime?> lastSuccessfulSync() async {
    try {
      final raw = (await _preferencesProvider()).getString(_lastSuccessKey);
      if (raw == null || raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toUtc();
    } on Object {
      return null;
    }
  }

  /// Records a sync that uploaded the complete snapshot.
  ///
  /// Never called for a run that stopped at unresolved conflicts: that run
  /// leaves the cloud copy untouched, so recording it would report a backup
  /// that does not exist. A write failure is swallowed for the same reason the
  /// read is — the sync itself did succeed, and losing the timestamp only
  /// shows the record as staler than it really is.
  Future<void> recordSuccessfulSync(DateTime at) async {
    try {
      await (await _preferencesProvider()).setString(
        _lastSuccessKey,
        at.toUtc().toIso8601String(),
      );
    } on Object {
      // Intentionally ignored; see above.
    }
  }
}
