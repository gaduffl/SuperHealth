import 'package:shared_preferences/shared_preferences.dart';

/// Device-local guard that prevents an automatic OneDrive sync immediately
/// after a portable backup has replaced the local health record.
///
/// This is deliberately not part of a snapshot or portable backup. A restored
/// device must make its own explicit choice between a normal merge and
/// publishing the restored record as the authoritative cloud copy.
class RestoreSyncDecisionRequiredError extends StateError {
  RestoreSyncDecisionRequiredError()
    : super(
        'OneDrive sync is paused after a portable restore. Choose "Resume and merge" or "Publish restored data" first.',
      );
}

class RestoreSyncGateStore {
  RestoreSyncGateStore({
    Future<SharedPreferences> Function()? preferencesProvider,
  }) : _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance;

  static const _pendingKey = 'portable_restore_sync_decision_pending';

  final Future<SharedPreferences> Function() _preferencesProvider;

  /// Reads the durable gate state. A storage failure fails closed so a restored
  /// health record is never silently synchronized without a remembered choice.
  Future<bool> isPending() async {
    try {
      return (await _preferencesProvider()).getBool(_pendingKey) ?? false;
    } on Object {
      throw StateError(
        'Could not verify the portable-restore OneDrive safety decision.',
      );
    }
  }

  Future<void> requireDecision() => _set(true);

  Future<void> clearDecision() => _set(false);

  Future<void> _set(bool value) async {
    try {
      final stored = await (await _preferencesProvider()).setBool(
        _pendingKey,
        value,
      );
      if (!stored) {
        throw StateError('Device settings rejected the restore-sync decision.');
      }
    } on StateError {
      rethrow;
    } on Object {
      throw StateError(
        'Could not save the portable-restore OneDrive decision.',
      );
    }
  }
}
