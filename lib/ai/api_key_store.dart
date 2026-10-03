import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'ai_models.dart';
import 'chatgpt_auth.dart';

/// API keys stay in Android encrypted storage and are never exposed through
/// repository snapshots, imports, exports, or OneDrive synchronization.
///
/// The ChatGPT subscription has no key: [read] answers for it with the stored
/// access token, so every call site keeps its one "is there a credential"
/// check, and the client renews the session itself on each request.
class ApiKeyStore {
  ApiKeyStore({FlutterSecureStorage? storage, this.chatGpt})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  final FlutterSecureStorage _storage;

  /// Null where no sign-in was wired up, such as a test that does not care;
  /// the subscription then simply reads as not signed in.
  final ChatGptAuth? chatGpt;

  static String _key(AiProvider provider) => 'ai_key_${provider.name}';

  /// What to tell someone who has no credential for [provider] yet. One
  /// sentence for every flow, because "add a chatgpt API key" sends the reader
  /// looking for a field that does not exist.
  static String missingCredentialMessage(AiProvider provider) =>
      provider == AiProvider.chatgpt
      ? 'Sign in with ChatGPT in Settings first.'
      : 'Add a ${provider.name} API key in Settings first.';

  Future<String?> read(AiProvider provider) async {
    if (provider == AiProvider.chatgpt) {
      return chatGpt?.storedAccessToken();
    }
    return _storage.read(key: _key(provider));
  }

  Future<bool> hasKey(AiProvider provider) async {
    final value = await read(provider);
    return value != null && value.trim().isNotEmpty;
  }

  Future<void> save(AiProvider provider, String value) async {
    if (provider == AiProvider.chatgpt) {
      throw StateError('A ChatGPT subscription is signed in, not given a key.');
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await delete(provider);
      return;
    }
    await _storage.write(key: _key(provider), value: trimmed);
  }

  Future<void> delete(AiProvider provider) async {
    if (provider == AiProvider.chatgpt) {
      await chatGpt?.signOut();
      return;
    }
    await _storage.delete(key: _key(provider));
  }
}
