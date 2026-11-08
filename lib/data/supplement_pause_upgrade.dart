/// v17 and older snapshots and portable backups predate per-profile pauses.
/// Call after verifying the original checksums, before row validation, so an
/// older file restores with every product unpaused for every profile, which is
/// exactly what it meant when it was written.
void upgradeSupplementPauseRows(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    row.putIfAbsent('paused_profile_ids_json', () => '[]');
  }
}
