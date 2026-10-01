import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/app_localizations.dart';
import '../updates/update_controller.dart';
import '../updates/update_models.dart';
import '../updates/update_settings.dart';
import 'common.dart';

String _t(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

/// The "App updates" block of Settings.
///
/// Renders nothing when no [UpdateController] is provided or the platform has
/// no installer to hand an APK to, so a build that cannot update never shows a
/// button that cannot work.
class AppUpdateSection extends StatefulWidget {
  const AppUpdateSection({super.key});

  @override
  State<AppUpdateSection> createState() => _AppUpdateSectionState();
}

class _AppUpdateSectionState extends State<AppUpdateSection>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<UpdateController?>()?.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<UpdateController?>();
    if (controller == null || !controller.supported) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: _t(context, 'App updates', 'App-Updates'),
          subtitle: _t(
            context,
            'Download a new SuperHealth build and install it over this one',
            'Eine neue SuperHealth-Version laden und über diese installieren',
          ),
        ),
        _UpdateCard(controller: controller),
      ],
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = controller.installedVersion;
    final update = controller.available;
    final phase = controller.phase;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      controller.updateAvailable
                          ? Icons.system_update
                          : Icons.verified_outlined,
                      color: controller.updateAvailable
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            installed == null
                                ? 'SuperHealth'
                                : _t(
                                    context,
                                    'Installed: $installed',
                                    'Installiert: $installed',
                                  ),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _statusLine(context),
                            key: const ValueKey('update-status'),
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (controller.lastCheckedAt case final checked?)
                            Text(
                              _t(
                                context,
                                'Last checked ${_when(context, checked)}',
                                'Zuletzt geprüft ${_when(context, checked)}',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (phase == UpdatePhase.downloading) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: controller.progress),
                ],
                if (phase == UpdatePhase.awaitingConfirmation) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (update != null && update.notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    update.notes,
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (phase == UpdatePhase.failed &&
                    controller.failure != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _failureMessage(context, controller.failure!),
                    key: const ValueKey('update-failure'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (phase == UpdatePhase.needsPermission) ...[
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      context,
                      'Android needs your permission before SuperHealth can '
                          'install an update. Switch on “Allow from this '
                          'source”, then come back — the download starts by '
                          'itself.',
                      'Android braucht deine Erlaubnis, bevor SuperHealth ein '
                          'Update installieren darf. Aktiviere „Aus dieser '
                          'Quelle zulassen“ und komm zurück – der Download '
                          'startet dann von selbst.',
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: _actions(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.tune_outlined),
            title: Text(_t(context, 'Update source', 'Update-Quelle')),
            subtitle: Text(_sourceSummary(context)),
            trailing: const Icon(Icons.chevron_right),
            onTap: controller.busy
                ? null
                : () => showUpdateSourceDialog(context, controller),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(BuildContext context) {
    final check = OutlinedButton.icon(
      key: const ValueKey('update-check'),
      onPressed: controller.busy ? null : controller.checkForUpdates,
      icon: const Icon(Icons.refresh),
      label: Text(_t(context, 'Check for updates', 'Nach Updates suchen')),
    );
    switch (controller.phase) {
      case UpdatePhase.downloading:
        return [
          OutlinedButton(
            key: const ValueKey('update-cancel'),
            onPressed: controller.cancelDownload,
            child: Text(_t(context, 'Cancel', 'Abbrechen')),
          ),
        ];
      case UpdatePhase.awaitingConfirmation:
        return const [];
      case UpdatePhase.needsPermission:
        return [
          FilledButton.icon(
            key: const ValueKey('update-permission'),
            onPressed: controller.openInstallPermissionSettings,
            icon: const Icon(Icons.settings_outlined),
            label: Text(_t(context, 'Open settings', 'Einstellungen öffnen')),
          ),
        ];
      case UpdatePhase.available:
      case UpdatePhase.readyToInstall:
      case UpdatePhase.failed when controller.available != null:
        return [
          FilledButton.icon(
            key: const ValueKey('update-install'),
            onPressed: controller.downloadAndInstall,
            icon: const Icon(Icons.download),
            label: Text(
              controller.phase == UpdatePhase.readyToInstall
                  ? _t(context, 'Install now', 'Jetzt installieren')
                  : _t(
                      context,
                      'Download and install',
                      'Herunterladen und installieren',
                    ),
            ),
          ),
          check,
        ];
      case UpdatePhase.idle:
      case UpdatePhase.checking:
      case UpdatePhase.upToDate:
      case UpdatePhase.failed:
        return [check];
    }
  }

  String _statusLine(BuildContext context) {
    final update = controller.available;
    final size = update?.sizeBytes;
    final sizeText = size == null ? '' : ' · ${_megabytes(size)}';
    return switch (controller.phase) {
      UpdatePhase.idle =>
        controller.settings.isConfigured
            ? _t(context, 'Not checked yet.', 'Noch nicht geprüft.')
            : _t(
                context,
                'Choose where updates come from.',
                'Wähle, woher Updates kommen.',
              ),
      UpdatePhase.checking => _t(
        context,
        'Checking for updates…',
        'Suche nach Updates…',
      ),
      UpdatePhase.upToDate => _t(
        context,
        'You have the latest version.',
        'Du hast die neueste Version.',
      ),
      UpdatePhase.available => _t(
        context,
        'Version ${update?.version} is available$sizeText.',
        'Version ${update?.version} ist verfügbar$sizeText.',
      ),
      UpdatePhase.needsPermission => _t(
        context,
        'Version ${update?.version} is ready to download.',
        'Version ${update?.version} kann geladen werden.',
      ),
      UpdatePhase.downloading => _t(
        context,
        'Downloading ${_progressText(controller)}',
        'Lade herunter ${_progressText(controller)}',
      ),
      UpdatePhase.readyToInstall => _t(
        context,
        'Version ${update?.version} is downloaded and verified.',
        'Version ${update?.version} ist geladen und geprüft.',
      ),
      UpdatePhase.awaitingConfirmation => _t(
        context,
        'Confirm the installation in the Android dialog. SuperHealth '
            'restarts when it finishes.',
        'Bestätige die Installation im Android-Dialog. SuperHealth startet '
            'danach neu.',
      ),
      UpdatePhase.failed => _t(
        context,
        'The update did not complete.',
        'Das Update wurde nicht abgeschlossen.',
      ),
    };
  }

  String _sourceSummary(BuildContext context) {
    final settings = controller.settings;
    final token = controller.hasToken
        ? _t(context, ' · token saved', ' · Token gespeichert')
        : '';
    return switch (settings.source) {
      UpdateSourceKind.github => 'GitHub · ${settings.githubRepository}$token',
      UpdateSourceKind.server =>
        settings.serverUrl.isEmpty
            ? _t(
                context,
                'Own server · not set',
                'Eigener Server · nicht gesetzt',
              )
            : '${_t(context, 'Own server', 'Eigener Server')} · '
                  '${Uri.tryParse(settings.serverUrl)?.host ?? settings.serverUrl}'
                  '$token',
    };
  }

  String _failureMessage(BuildContext context, UpdateException error) {
    final hasToken = controller.hasToken;
    final detail = error.detail == null ? '' : ' (${error.detail})';
    final text = switch (error.kind) {
      UpdateFailureKind.notConfigured => _t(
        context,
        'Choose where updates come from first.',
        'Wähle zuerst, woher Updates kommen.',
      ),
      UpdateFailureKind.notFound =>
        hasToken
            ? _t(
                context,
                'No release was found. Check the name, and that the token '
                    'is allowed to read it.',
                'Keine Version gefunden. Prüfe den Namen und ob der Token '
                    'lesen darf.',
              )
            : _t(
                context,
                'No release was found. A private repository needs an access '
                    'token.',
                'Keine Version gefunden. Ein privates Repository braucht '
                    'einen Zugriffstoken.',
              ),
      UpdateFailureKind.unauthorized =>
        hasToken
            ? _t(
                context,
                'The server rejected the access token.',
                'Der Server hat den Zugriffstoken abgelehnt.',
              )
            : _t(
                context,
                'This source needs an access token.',
                'Diese Quelle braucht einen Zugriffstoken.',
              ),
      UpdateFailureKind.rateLimited => _t(
        context,
        'Too many requests. Try again later, or add an access token.',
        'Zu viele Anfragen. Versuche es später erneut oder füge einen '
            'Zugriffstoken hinzu.',
      ),
      UpdateFailureKind.network => _t(
        context,
        'Could not reach the update server$detail.',
        'Der Update-Server ist nicht erreichbar$detail.',
      ),
      UpdateFailureKind.storage => _t(
        context,
        'The update could not be saved. Free some storage and try again.',
        'Das Update konnte nicht gespeichert werden. Schaffe Speicherplatz '
            'und versuche es erneut.',
      ),
      UpdateFailureKind.noApk => _t(
        context,
        'The latest release has no APK attached.',
        'An der neuesten Version hängt keine APK-Datei.',
      ),
      UpdateFailureKind.badResponse => _t(
        context,
        'The server answered with something this app cannot read.',
        'Der Server hat etwas geantwortet, das die App nicht lesen kann.',
      ),
      UpdateFailureKind.insecureUrl => _t(
        context,
        'Updates are only fetched over https.',
        'Updates werden nur über https geladen.',
      ),
      UpdateFailureKind.checksumMismatch => _t(
        context,
        'The download did not match its checksum and was discarded.',
        'Der Download stimmte nicht mit der Prüfsumme überein und wurde '
            'verworfen.',
      ),
      UpdateFailureKind.sizeMismatch => _t(
        context,
        'The download was incomplete and was discarded.',
        'Der Download war unvollständig und wurde verworfen.',
      ),
      UpdateFailureKind.cancelled => _t(context, 'Cancelled.', 'Abgebrochen.'),
      UpdateFailureKind.installPermissionMissing => _t(
        context,
        'Android has not allowed SuperHealth to install apps yet.',
        'Android erlaubt SuperHealth noch nicht, Apps zu installieren.',
      ),
      UpdateFailureKind.installFailed => _t(
        context,
        'Android could not install the update$detail.',
        'Android konnte das Update nicht installieren$detail.',
      ),
      UpdateFailureKind.unsupportedPlatform => _t(
        context,
        'In-app updates work on Android only.',
        'App-Updates funktionieren nur unter Android.',
      ),
    };
    // Android's own wording for a different signing key is cryptic
    // (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`); the cause is worth stating.
    final incompatible =
        error.kind == UpdateFailureKind.installFailed &&
        (error.detail?.toUpperCase().contains('INCOMPATIBLE') ?? false);
    if (!incompatible) return text;
    return '$text ${_t(context, 'It is signed with a different key than the installed app.', 'Es ist mit einem anderen Schlüssel signiert als die installierte App.')}';
  }

  static String _progressText(UpdateController controller) {
    final total = controller.totalBytes;
    final received = _megabytes(controller.receivedBytes);
    return total == null ? received : '$received / ${_megabytes(total)}';
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static String _when(BuildContext context, DateTime at) => DateFormat.yMMMd(
    Localizations.localeOf(context).toString(),
  ).add_Hm().format(at.toLocal());
}

Future<void> showUpdateSourceDialog(
  BuildContext context,
  UpdateController controller,
) => showDialog<void>(
  context: context,
  builder: (_) => _UpdateSourceDialog(controller: controller),
);

class _UpdateSourceDialog extends StatefulWidget {
  const _UpdateSourceDialog({required this.controller});

  final UpdateController controller;

  @override
  State<_UpdateSourceDialog> createState() => _UpdateSourceDialogState();
}

class _UpdateSourceDialogState extends State<_UpdateSourceDialog> {
  late UpdateSourceKind _source = widget.controller.settings.source;
  late bool _autoCheck = widget.controller.settings.autoCheck;
  late final _repository = TextEditingController(
    text: widget.controller.settings.githubRepository,
  );
  late final _server = TextEditingController(
    text: widget.controller.settings.serverUrl,
  );
  final _token = TextEditingController();
  bool _removeToken = false;
  bool _tokenSaved = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadTokenState();
  }

  // The token itself is never read back into the form; only whether one exists.
  Future<void> _loadTokenState() async {
    final saved = await widget.controller.tokenStore.read(_source) != null;
    if (mounted) setState(() => _tokenSaved = saved);
  }

  @override
  void dispose() {
    _repository.dispose();
    _server.dispose();
    _token.dispose();
    super.dispose();
  }

  String? get _repositoryError =>
      _submitted && normalizeGitHubRepository(_repository.text) == null
      ? _t(
          context,
          'Use the form owner/name.',
          'Verwende die Form Besitzer/Name.',
        )
      : null;

  String? get _serverError => _submitted && parseSecureUrl(_server.text) == null
      ? _t(
          context,
          'Enter an https:// address.',
          'Gib eine https://-Adresse ein.',
        )
      : null;

  Future<void> _save() async {
    setState(() => _submitted = true);
    final github = _source == UpdateSourceKind.github;
    if (github ? _repositoryError != null : _serverError != null) return;
    final current = widget.controller.settings;
    final token = _removeToken
        ? ''
        : _token.text.trim().isEmpty
        ? null
        : _token.text.trim();
    final navigator = Navigator.of(context);
    await widget.controller.saveSettings(
      current.copyWith(
        source: _source,
        githubRepository: github
            ? normalizeGitHubRepository(_repository.text)!
            : current.githubRepository,
        serverUrl: github
            ? current.serverUrl
            : parseSecureUrl(_server.text)!.toString(),
        autoCheck: _autoCheck,
      ),
      token: token,
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final github = _source == UpdateSourceKind.github;
    return AlertDialog(
      title: Text(_t(context, 'Update source', 'Update-Quelle')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<UpdateSourceKind>(
              segments: [
                const ButtonSegment(
                  value: UpdateSourceKind.github,
                  label: Text('GitHub'),
                ),
                ButtonSegment(
                  value: UpdateSourceKind.server,
                  label: Text(_t(context, 'Own server', 'Eigener Server')),
                ),
              ],
              selected: {_source},
              onSelectionChanged: (selection) {
                setState(() {
                  _source = selection.single;
                  _token.clear();
                  _removeToken = false;
                });
                _loadTokenState();
              },
            ),
            const SizedBox(height: 16),
            if (github)
              TextField(
                key: const ValueKey('update-repository'),
                controller: _repository,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: _t(context, 'Repository', 'Repository'),
                  hintText: defaultUpdateRepository,
                  errorText: _repositoryError,
                ),
                onChanged: (_) => setState(() {}),
              )
            else ...[
              TextField(
                key: const ValueKey('update-server'),
                controller: _server,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: _t(
                    context,
                    'Release manifest URL',
                    'URL der Release-Manifestdatei',
                  ),
                  hintText: 'https://updates.example.org/latest.json',
                  errorText: _serverError,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              Text(
                _t(
                  context,
                  'A JSON file with version, apk_url and sha256.',
                  'Eine JSON-Datei mit version, apk_url und sha256.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('update-token'),
              controller: _token,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_removeToken,
              decoration: InputDecoration(
                labelText: _t(
                  context,
                  'Access token (optional)',
                  'Zugriffstoken (optional)',
                ),
                helperText: _tokenSaved && !_removeToken
                    ? _t(
                        context,
                        'A token is saved. Leave empty to keep it.',
                        'Ein Token ist gespeichert. Leer lassen, um ihn '
                            'zu behalten.',
                      )
                    : github
                    ? _t(
                        context,
                        'A private repository needs a fine-grained token with '
                            'read access to Contents.',
                        'Ein privates Repository braucht einen '
                            'feingranularen Token mit Lesezugriff auf Contents.',
                      )
                    : null,
                helperMaxLines: 3,
              ),
            ),
            if (_tokenSaved)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _removeToken,
                onChanged: (value) => setState(() {
                  _removeToken = value ?? false;
                  if (_removeToken) _token.clear();
                }),
                title: Text(
                  _t(
                    context,
                    'Remove saved token',
                    'Gespeicherten Token löschen',
                  ),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoCheck,
              onChanged: (value) => setState(() => _autoCheck = value),
              title: Text(
                _t(
                  context,
                  'Check when the app starts',
                  'Beim Start nach Updates suchen',
                ),
              ),
              subtitle: Text(
                _t(
                  context,
                  'Only looks for a new version. Nothing is downloaded or '
                      'installed without your tap.',
                  'Sucht nur nach einer neuen Version. Ohne dein Tippen wird '
                      'nichts geladen oder installiert.',
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(_t(context, 'Cancel', 'Abbrechen')),
        ),
        FilledButton(
          key: const ValueKey('update-source-save'),
          onPressed: _save,
          child: Text(_t(context, 'Save', 'Speichern')),
        ),
      ],
    );
  }
}
