import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_models.dart';

/// API keys stay in Android encrypted storage and are never exposed through
/// repository snapshots, imports, exports, or OneDrive synchronization.
class ApiKeyStore {
  ApiKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  final FlutterSecureStorage _storage;

  static String _key(AiProvider provider) => 'ai_key_${provider.name}';

  Future<String?> read(AiProvider provider) =>
      _storage.read(key: _key(provider));

  Future<bool> hasKey(AiProvider provider) async {
    final value = await read(provider);
    return value != null && value.trim().isNotEmpty;
  }

  Future<void> save(AiProvider provider, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await delete(provider);
      return;
    }
    await _storage.write(key: _key(provider), value: trimmed);
  }

  Future<void> delete(AiProvider provider) =>
      _storage.delete(key: _key(provider));
}
