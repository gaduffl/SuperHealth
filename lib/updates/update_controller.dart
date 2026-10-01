import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'apk_installer.dart';
import 'app_version.dart';
import 'update_downloader.dart';
import 'update_models.dart';
import 'update_settings.dart';
import 'update_source.dart';

typedef UpdateSourceFactory =
    UpdateSource Function(UpdateSettings settings, String? token);

/// The production wiring: GitHub's release API, or a manifest URL.
UpdateSourceFactory updateSourceFactoryFor(Dio dio) =>
    (settings, token) => switch (settings.source) {
      UpdateSourceKind.github => GitHubReleaseSource(
        repository: normalizeGitHubRepository(settings.githubRepository)!,
        dio: dio,
        token: token,
      ),
      UpdateSourceKind.server => ManifestUpdateSource(
        manifestUri: parseSecureUrl(settings.serverUrl)!,
        dio: dio,
        token: token,
      ),
    };

enum UpdatePhase {
  idle,
  checking,
  upToDate,
  available,

  /// Waiting for the person to allow installs from this app in system settings.
  needsPermission,
  downloading,

  /// Downloaded and verified, not yet handed to Android — or handed over and
  /// dismissed, so the same file can be offered again without another download.
  readyToInstall,
  awaitingConfirmation,
  failed,
}

/// Looks for a newer release, downloads it, and hands it to Android.
///
/// Nothing here runs without the person pressing a button, apart from the
/// optional check at startup — which only *looks*. Fetching and installing are
/// always an explicit tap, because replacing the app is not something to do
/// while someone is mid-entry.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.installer,
    required this.settingsStore,
    required this.tokenStore,
    required this.downloader,
    required this.sourceFactory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _events = installer.events.listen(_onInstallEvent);
  }

  final ApkInstaller installer;
  final UpdateSettingsStore settingsStore;
  final UpdateTokenStore tokenStore;
  final UpdateDownloader downloader;
  final UpdateSourceFactory sourceFactory;
  final DateTime Function() _clock;

  /// A relaunch inside this window does not re-ask the server: a few cold
  /// starts in an hour is a phone being fiddled with, not news.
  static const autoCheckInterval = Duration(hours: 1);

  late final StreamSubscription<InstallEvent> _events;
  CancelToken? _cancelToken;
  UpdateSource? _source;

  UpdatePhase _phase = UpdatePhase.idle;
  UpdateSettings _settings = const UpdateSettings();
  AppVersion? _installed;
  AvailableUpdate? _available;
  UpdateException? _failure;
  DateTime? _lastCheckedAt;
  File? _downloaded;
  int _received = 0;
  int? _total;
  bool _hasToken = false;
  bool _loaded = false;

  UpdatePhase get phase => _phase;
  UpdateSettings get settings => _settings;
  AppVersion? get installedVersion => _installed;
  AvailableUpdate? get available => _available;
  UpdateException? get failure => _failure;
  DateTime? get lastCheckedAt => _lastCheckedAt;
  bool get hasToken => _hasToken;
  bool get loaded => _loaded;
  bool get supported => installer.isSupported;

  /// 0–1 while the size is known, null when it is not (an indeterminate bar).
  double? get progress {
    final total = _total;
    if (total == null || total <= 0) return null;
    return (_received / total).clamp(0.0, 1.0);
  }

  int get receivedBytes => _received;
  int? get totalBytes => _total;

  bool get busy =>
      _phase == UpdatePhase.checking ||
      _phase == UpdatePhase.downloading ||
      _phase == UpdatePhase.awaitingConfirmation;

  /// Whether a newer build is known, for a badge somewhere other than the card.
  bool get updateAvailable => switch (_phase) {
    UpdatePhase.available ||
    UpdatePhase.needsPermission ||
    UpdatePhase.downloading ||
    UpdatePhase.readyToInstall ||
    UpdatePhase.awaitingConfirmation => true,
    UpdatePhase.failed => _available != null,
    _ => false,
  };

  Future<void> load() async {
    _settings = await settingsStore.load();
    _hasToken = await tokenStore.read(_settings.source) != null;
    _lastCheckedAt = await settingsStore.lastCheckedAt();
    if (supported) {
      try {
        _installed = await installer.installedVersion();
      } on UpdateException {
        // Leaves the card without a version line rather than without a card.
      }
    }
    // A build that has just replaced itself leaves its APK behind, and the
    // process that downloaded it is gone. Awaited: a later download must not
    // have its own file swept away by a clean-up still in flight.
    await downloader.discardAll();
    _loaded = true;
    notifyListeners();
  }

  /// The startup check. Quiet by construction: it never shows an error, because
  /// a phone without signal at launch is normal and not worth a red banner.
  Future<void> checkInBackground() async {
    if (!_loaded) await load();
    if (!supported || !_settings.autoCheck || !_settings.isConfigured) return;
    final last = _lastCheckedAt;
    if (last != null && _clock().difference(last) < autoCheckInterval) return;
    await checkForUpdates(background: true);
  }

  Future<void> checkForUpdates({bool background = false}) async {
    if (busy) return;
    if (!_loaded) await load();
    if (!supported) {
      return _fail(
        const UpdateException(UpdateFailureKind.unsupportedPlatform),
      );
    }
    if (!_settings.isConfigured) {
      if (background) return;
      return _fail(const UpdateException(UpdateFailureKind.notConfigured));
    }
    final previous = _phase;
    _phase = UpdatePhase.checking;
    _failure = null;
    notifyListeners();
    try {
      final installed = _installed ??= await installer.installedVersion();
      final token = await tokenStore.read(_settings.source);
      final source = sourceFactory(_settings, token);
      final latest = await source.fetchLatest();
      _source = source;
      _lastCheckedAt = _clock();
      await settingsStore.recordCheck(_lastCheckedAt!);
      if (latest.version.isNewerThan(installed)) {
        // A file fetched for an older release must not be offered as this one.
        if (_available?.version != latest.version) _downloaded = null;
        _available = latest;
        _phase = UpdatePhase.available;
      } else {
        _available = null;
        _downloaded = null;
        _phase = UpdatePhase.upToDate;
        // An APK for a build this one has caught up to is dead weight.
        await downloader.discardAll();
      }
      notifyListeners();
    } on UpdateException catch (error) {
      if (background) {
        // Back to what the card was showing: a silent failure must not erase a
        // known update or leave the card stuck on "checking".
        _phase = previous == UpdatePhase.checking ? UpdatePhase.idle : previous;
        notifyListeners();
      } else {
        _fail(error);
      }
    }
  }

  /// Asks Android for permission if needed, downloads, verifies and installs.
  Future<void> downloadAndInstall() async {
    final update = _available;
    if (update == null || busy) return;
    final source = _source;
    if (source == null) return checkForUpdates();
    if (!await _installAllowed()) return;
    // A file that survived an earlier attempt for this exact release is
    // already verified; offering it again saves a download over mobile data.
    final existing = _downloaded;
    if (existing != null && await existing.exists()) {
      return installDownloaded();
    }
    _phase = UpdatePhase.downloading;
    _failure = null;
    _received = 0;
    _total = update.sizeBytes;
    final cancel = _cancelToken = CancelToken();
    notifyListeners();
    try {
      await downloader.discardAll();
      _downloaded = await downloader.download(
        update,
        source,
        cancelToken: cancel,
        onProgress: (received, total) {
          _received = received;
          _total = total;
          notifyListeners();
        },
      );
    } on UpdateException catch (error) {
      _cancelToken = null;
      // A cancelled download is the person's own choice, not a failure.
      if (error.kind == UpdateFailureKind.cancelled) {
        _phase = UpdatePhase.available;
        notifyListeners();
      } else {
        _fail(error);
      }
      return;
    }
    _cancelToken = null;
    await installDownloaded();
  }

  Future<void> installDownloaded() async {
    final file = _downloaded;
    if (file == null) return;
    if (!await _installAllowed()) return;
    _phase = UpdatePhase.readyToInstall;
    _failure = null;
    notifyListeners();
    try {
      await installer.install(file);
      // The commit succeeded; the system sheet's own event normally lands
      // first, but if it is late the person still sees that something is
      // happening rather than a button that did nothing.
      if (_phase == UpdatePhase.readyToInstall) {
        _phase = UpdatePhase.awaitingConfirmation;
        notifyListeners();
      }
    } on UpdateException catch (error) {
      _fail(error);
    }
  }

  void cancelDownload() => _cancelToken?.cancel();

  Future<void> openInstallPermissionSettings() async {
    try {
      await installer.openInstallPermissionSettings();
    } on UpdateException catch (error) {
      _fail(error);
    }
  }

  /// Called when the app returns to the foreground. Coming back from the
  /// "install unknown apps" page with the switch on carries on where the
  /// person left off, instead of asking them to find the button again.
  Future<void> onResumed() async {
    if (_phase != UpdatePhase.needsPermission) return;
    if (await installer.canInstallPackages()) await downloadAndInstall();
  }

  /// Saves the source settings. A null [token] leaves the stored one alone, an
  /// empty one removes it — so editing the repository never wipes a credential
  /// the form did not show.
  Future<void> saveSettings(UpdateSettings settings, {String? token}) async {
    await settingsStore.save(settings);
    if (token != null) {
      if (token.trim().isEmpty) {
        await tokenStore.delete(settings.source);
      } else {
        await tokenStore.save(settings.source, token);
      }
    }
    final changedSource =
        settings.source != _settings.source ||
        settings.githubRepository != _settings.githubRepository ||
        settings.serverUrl != _settings.serverUrl;
    _settings = settings;
    _hasToken = await tokenStore.read(settings.source) != null;
    if (changedSource || token != null) {
      // What was learned from the old source says nothing about the new one.
      _available = null;
      _downloaded = null;
      _source = null;
      _failure = null;
      if (!busy) _phase = UpdatePhase.idle;
      await downloader.discardAll();
    }
    notifyListeners();
  }

  Future<bool> _installAllowed() async {
    try {
      if (await installer.canInstallPackages()) return true;
    } on UpdateException catch (error) {
      _fail(error);
      return false;
    }
    _phase = UpdatePhase.needsPermission;
    notifyListeners();
    return false;
  }

  void _onInstallEvent(InstallEvent event) {
    switch (event.kind) {
      case InstallEventKind.awaitingConfirmation:
        _phase = UpdatePhase.awaitingConfirmation;
        notifyListeners();
      case InstallEventKind.cancelled:
        _phase = UpdatePhase.readyToInstall;
        notifyListeners();
      case InstallEventKind.success:
        _available = null;
        _downloaded = null;
        _phase = UpdatePhase.upToDate;
        unawaited(downloader.discardAll());
        notifyListeners();
      case InstallEventKind.failed:
        _fail(UpdateException(UpdateFailureKind.installFailed, event.message));
    }
  }

  void _fail(UpdateException error) {
    _failure = error;
    _phase = UpdatePhase.failed;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    unawaited(_events.cancel());
    super.dispose();
  }
}
