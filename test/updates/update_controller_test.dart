import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_health/updates/apk_installer.dart';
import 'package:super_health/updates/app_version.dart';
import 'package:super_health/updates/update_controller.dart';
import 'package:super_health/updates/update_downloader.dart';
import 'package:super_health/updates/update_models.dart';
import 'package:super_health/updates/update_settings.dart';

import 'fakes.dart';

const _apkUrl = 'https://api.github.com/repos/o/r/releases/assets/9';

void main() {
  late Directory dir;
  late FakeInstaller installer;
  late MemoryTokens tokens;
  late FakeAdapter adapter;
  late FixedSource source;
  late DateTime now;
  final bytes = List<int>.generate(64, (i) => i);

  AvailableUpdate update({String version = '0.43.0+72'}) => AvailableUpdate(
    version: AppVersion.tryParse(version)!,
    downloadUri: Uri.parse(_apkUrl),
    sizeBytes: bytes.length,
    sha256: sha256Of(bytes),
    notes: 'Fixes',
  );

  UpdateController build() => UpdateController(
    installer: installer,
    settingsStore: UpdateSettingsStore(),
    tokenStore: tokens,
    downloader: UpdateDownloader(
      dio: dioFor(adapter),
      directory: () async => dir,
    ),
    sourceFactory: (_, _) => source,
    clock: () => now,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = tempDir();
    installer = FakeInstaller();
    tokens = MemoryTokens();
    adapter = FakeAdapter({_apkUrl: Reply(200, bytes: bytes)});
    source = FixedSource(update());
    now = DateTime.utc(2026, 10, 1, 12);
  });

  test('a newer release is offered and the check time is recorded', () async {
    final controller = build();
    await controller.checkForUpdates();

    expect(controller.phase, UpdatePhase.available);
    expect(controller.available!.version.toString(), '0.43.0+72');
    expect(controller.installedVersion.toString(), '0.42.0+71');
    expect(controller.updateAvailable, isTrue);
    expect(await UpdateSettingsStore().lastCheckedAt(), now);
  });

  test(
    'the same or an older build is "up to date" and clears stale downloads',
    () async {
      File('${dir.path}/superhealth-0.42.0-71.apk').createSync(recursive: true);
      source.update = update(version: '0.42.0+71');
      final controller = build();
      await controller.checkForUpdates();
      // The clean-up is deliberately fire-and-forget.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.phase, UpdatePhase.upToDate);
      expect(controller.updateAvailable, isFalse);
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'the stored token reaches the source for the configured kind only',
    () async {
      tokens.values[UpdateSourceKind.server] = 'server-token';
      tokens.values[UpdateSourceKind.github] = 'github-token';
      String? seen;
      final controller = UpdateController(
        installer: installer,
        settingsStore: UpdateSettingsStore(),
        tokenStore: tokens,
        downloader: UpdateDownloader(
          dio: dioFor(adapter),
          directory: () async => dir,
        ),
        sourceFactory: (_, token) {
          seen = token;
          return source;
        },
      );
      await controller.checkForUpdates();
      expect(seen, 'github-token');
    },
  );

  test(
    'a failed manual check is shown; a failed startup check is silent',
    () async {
      source.error = const UpdateException(UpdateFailureKind.network);
      final manual = build();
      await manual.checkForUpdates();
      expect(manual.phase, UpdatePhase.failed);
      expect(manual.failure!.kind, UpdateFailureKind.network);

      final startup = build();
      await startup.checkInBackground();
      expect(startup.phase, UpdatePhase.idle);
      expect(startup.failure, isNull);
    },
  );

  test(
    'a silent failure does not erase an update that was already known',
    () async {
      final controller = build();
      await controller.checkForUpdates();
      source.error = const UpdateException(UpdateFailureKind.network);
      await controller.checkForUpdates(background: true);

      expect(controller.phase, UpdatePhase.available);
      expect(controller.available, isNotNull);
    },
  );

  test(
    'the startup check honours the switch, the configuration and the interval',
    () async {
      final off = build();
      await off.saveSettings(const UpdateSettings(autoCheck: false));
      await off.checkInBackground();
      expect(source.fetches, 0);

      final on = build();
      await on.saveSettings(const UpdateSettings());
      await on.checkInBackground();
      expect(source.fetches, 1);

      now = now.add(const Duration(minutes: 10));
      await build().checkInBackground();
      expect(
        source.fetches,
        1,
        reason: 'a relaunch within the hour does not re-ask',
      );

      now = now.add(UpdateController.autoCheckInterval);
      await build().checkInBackground();
      expect(source.fetches, 2);
    },
  );

  test('an unconfigured manual check explains what is missing', () async {
    final controller = build();
    await controller.saveSettings(
      const UpdateSettings(source: UpdateSourceKind.server),
    );
    await controller.checkForUpdates();
    expect(controller.failure!.kind, UpdateFailureKind.notConfigured);
    expect(source.fetches, 0);
  });

  test('nothing is fetched or installed off Android', () async {
    installer.supported = false;
    final controller = build();
    await controller.checkForUpdates();
    expect(controller.supported, isFalse);
    expect(controller.failure!.kind, UpdateFailureKind.unsupportedPlatform);
    expect(source.fetches, 0);
  });

  test('download then install hands the verified file to Android', () async {
    final controller = build();
    await controller.checkForUpdates();
    await controller.downloadAndInstall();

    expect(installer.installed, hasLength(1));
    expect(installer.installed.single.readAsBytesSync(), bytes);
    expect(controller.phase, UpdatePhase.awaitingConfirmation);
  });

  test(
    'without the install permission nothing is downloaded and the person is sent to settings',
    () async {
      installer.allowed = false;
      final controller = build();
      await controller.checkForUpdates();
      await controller.downloadAndInstall();

      expect(controller.phase, UpdatePhase.needsPermission);
      expect(
        adapter.requests,
        isEmpty,
        reason: 'no data spent before the switch is on',
      );
      await controller.openInstallPermissionSettings();
      expect(installer.permissionPageOpened, 1);
    },
  );

  test(
    'returning from settings with the switch on carries on by itself',
    () async {
      installer.allowed = false;
      final controller = build();
      await controller.checkForUpdates();
      await controller.downloadAndInstall();

      await controller.onResumed();
      expect(
        controller.phase,
        UpdatePhase.needsPermission,
        reason: 'still off',
      );

      installer.allowed = true;
      await controller.onResumed();
      expect(installer.installed, hasLength(1));
    },
  );

  test('a corrupt download fails and installs nothing', () async {
    adapter = FakeAdapter({_apkUrl: Reply(200, bytes: List.filled(64, 7))});
    final controller = build();
    await controller.checkForUpdates();
    await controller.downloadAndInstall();

    expect(controller.phase, UpdatePhase.failed);
    expect(controller.failure!.kind, UpdateFailureKind.checksumMismatch);
    expect(installer.installed, isEmpty);
    expect(controller.available, isNotNull, reason: 'the person can try again');
  });

  test(
    'dismissing the system sheet keeps the file so install can be offered again',
    () async {
      final controller = build();
      await controller.checkForUpdates();
      await controller.downloadAndInstall();
      installer.emit(const InstallEvent(InstallEventKind.cancelled));
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, UpdatePhase.readyToInstall);

      final requestsBefore = adapter.requests.length;
      await controller.downloadAndInstall();
      expect(installer.installed, hasLength(2));
      expect(
        adapter.requests.length,
        requestsBefore,
        reason: 'no second download',
      );
    },
  );

  test(
    'an installer failure is reported with Android\'s own message',
    () async {
      final controller = build();
      await controller.checkForUpdates();
      await controller.downloadAndInstall();
      installer.emit(
        const InstallEvent(
          InstallEventKind.failed,
          'INSTALL_FAILED_UPDATE_INCOMPATIBLE',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.phase, UpdatePhase.failed);
      expect(controller.failure!.kind, UpdateFailureKind.installFailed);
      expect(controller.failure!.detail, contains('INCOMPATIBLE'));
    },
  );

  test('a commit that throws is a failure, not a hang', () async {
    installer.installError = const UpdateException(
      UpdateFailureKind.installFailed,
      'no space',
    );
    final controller = build();
    await controller.checkForUpdates();
    await controller.downloadAndInstall();
    expect(controller.phase, UpdatePhase.failed);
    expect(controller.failure!.detail, 'no space');
  });

  test(
    'a newer release invalidates a file downloaded for an older one',
    () async {
      final controller = build();
      await controller.checkForUpdates();
      await controller.downloadAndInstall();
      installer.emit(const InstallEvent(InstallEventKind.cancelled));
      await Future<void>.delayed(Duration.zero);

      final newer = update(version: '0.44.0+73');
      source.update = newer;
      adapter.routes[_apkUrl] = Reply(200, bytes: bytes);
      await controller.checkForUpdates();
      final before = adapter.requests.length;
      await controller.downloadAndInstall();
      expect(
        adapter.requests.length,
        greaterThan(before),
        reason: 'fetched again',
      );
    },
  );

  test(
    'cancelling a download returns to "available", not to an error',
    () async {
      adapter = FakeAdapter({
        _apkUrl: Reply(
          200,
          chunks: [for (var i = 0; i < 40; i++) List.filled(2, i)],
          headers: {'content-length': '80'},
        ),
      });
      source.update = AvailableUpdate(
        version: AppVersion.tryParse('0.43.0+72')!,
        downloadUri: Uri.parse(_apkUrl),
      );
      final controller = build();
      await controller.checkForUpdates();
      controller.addListener(() {
        if (controller.phase == UpdatePhase.downloading &&
            controller.receivedBytes >= 10) {
          controller.cancelDownload();
        }
      });
      await controller.downloadAndInstall();

      expect(controller.phase, UpdatePhase.available);
      expect(controller.failure, isNull);
      expect(installer.installed, isEmpty);
      expect(dir.existsSync() ? dir.listSync() : [], isEmpty);
    },
  );

  test(
    'editing the source forgets what the old one said, and keeps a token it did not touch',
    () async {
      final controller = build();
      await controller.saveSettings(const UpdateSettings(), token: 'abc');
      await controller.checkForUpdates();
      expect(controller.available, isNotNull);

      await controller.saveSettings(
        const UpdateSettings(githubRepository: 'someone/else'),
      );
      expect(controller.available, isNull);
      expect(controller.phase, UpdatePhase.idle);
      expect(
        controller.hasToken,
        isTrue,
        reason: 'null token means leave it alone',
      );

      await controller.saveSettings(
        const UpdateSettings(githubRepository: 'someone/else'),
        token: '  ',
      );
      expect(controller.hasToken, isFalse, reason: 'an empty token removes it');
    },
  );

  test(
    'settings load from storage and report whether a token exists',
    () async {
      SharedPreferences.setMockInitialValues({
        'update_source': 'server',
        'update_server_url': 'https://updates.example.org/latest.json',
      });
      tokens.values[UpdateSourceKind.server] = 'x';
      final controller = build();
      await controller.load();
      expect(controller.settings.source, UpdateSourceKind.server);
      expect(controller.hasToken, isTrue);
      expect(controller.loaded, isTrue);
    },
  );

  test('progress is indeterminate when the size is unknown', () async {
    final controller = build();
    expect(controller.progress, isNull);
  });

  // Silences "unused" for Dio import used by the adapter helpers above.
  test('dio helper is wired', () => expect(dioFor(adapter), isA<Dio>()));
}
