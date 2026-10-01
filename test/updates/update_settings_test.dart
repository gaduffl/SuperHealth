import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_health/updates/update_settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a repository is accepted as owner/name or as a pasted link', () {
    expect(
      normalizeGitHubRepository('gaduffl/superhealth'),
      'gaduffl/superhealth',
    );
    expect(
      normalizeGitHubRepository('https://github.com/gaduffl/superhealth/'),
      'gaduffl/superhealth',
    );
    expect(
      normalizeGitHubRepository('https://github.com/gaduffl/superhealth.git'),
      'gaduffl/superhealth',
    );
  });

  test('a repository that could change the API path is rejected', () {
    for (final raw in [
      '',
      'superhealth',
      'a/b/c',
      '../etc',
      'a/..',
      'a/b?x=1',
      'a b/c',
      'http://example.org/a/b',
    ]) {
      expect(normalizeGitHubRepository(raw), isNull, reason: raw);
    }
  });

  test('only https server addresses are accepted', () {
    expect(
      parseSecureUrl('https://updates.example.org/latest.json'),
      isNotNull,
    );
    expect(parseSecureUrl('http://updates.example.org/latest.json'), isNull);
    expect(parseSecureUrl('updates.example.org'), isNull);
    expect(parseSecureUrl('https://'), isNull);
  });

  test('defaults point at the release repository and check on start', () async {
    final settings = await UpdateSettingsStore().load();
    expect(settings.source, UpdateSourceKind.github);
    expect(settings.githubRepository, defaultUpdateRepository);
    expect(settings.autoCheck, isTrue);
    expect(settings.isConfigured, isTrue);
    expect(
      const UpdateSettings(source: UpdateSourceKind.server).isConfigured,
      isFalse,
    );
  });

  test('saved settings and the last check survive a reload', () async {
    final store = UpdateSettingsStore();
    await store.save(
      const UpdateSettings(
        source: UpdateSourceKind.server,
        serverUrl: 'https://updates.example.org/latest.json',
        autoCheck: false,
      ),
    );
    final at = DateTime.utc(2026, 10, 1, 8);
    await store.recordCheck(at);

    final loaded = await UpdateSettingsStore().load();
    expect(loaded.source, UpdateSourceKind.server);
    expect(loaded.serverUrl, 'https://updates.example.org/latest.json');
    expect(loaded.autoCheck, isFalse);
    expect(await store.lastCheckedAt(), at);
  });
}
