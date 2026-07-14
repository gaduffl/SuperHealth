import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_models.dart';
import '../ai/ai_settings.dart';
import '../app/app_controller.dart';
import '../import/legacy_import_service.dart';
import 'common.dart';
import 'dialogs.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _oneDriveSignedIn;

  @override
  void initState() {
    super.initState();
    _refreshOneDriveStatus();
  }

  Future<void> _refreshOneDriveStatus() async {
    final value = await context
        .read<AppController>()
        .oneDriveService
        .isSignedIn();
    if (mounted) setState(() => _oneDriveSignedIn = value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
        children: [
          SectionHeader(
            title: 'Profiles',
            subtitle:
                'Every profile is isolated in storage, sync, exports, and AI context',
            action: IconButton.filledTonal(
              onPressed: () => showAddProfileDialog(context, controller),
              icon: const Icon(Icons.person_add_outlined),
            ),
          ),
          Card(
            child: Column(
              children: [
                for (final profile in controller.profiles)
                  ListTile(
                    leading: Icon(
                      profile.id == controller.activeProfile?.id
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                    ),
                    title: Text(profile.displayName),
                    subtitle: Text(
                      [
                        if (profile.age != null) 'Age ${profile.age}',
                        if (profile.sex?.isNotEmpty == true) profile.sex!,
                        if (profile.weightKg != null) '${profile.weightKg} kg',
                      ].join(' · '),
                    ),
                    onTap: () => controller.selectProfile(profile.id),
                  ),
              ],
            ),
          ),
          const SectionHeader(
            title: 'AI providers',
            subtitle:
                'Bring your own key; keys stay in encrypted device storage',
          ),
          for (final provider in AiProvider.values)
            _ApiKeyCard(provider: provider),
          const SectionHeader(
            title: 'AI roles',
            subtitle:
                'Choose separate models for the main advisor and document parsing',
          ),
          _ModelConfigurationCard(
            key: ValueKey('advisor-${controller.advisorSettings?.model}'),
            task: AiTask.advisor,
            title: 'Main advisor',
            settings: controller.advisorSettings,
            allowTools: true,
          ),
          _ModelConfigurationCard(
            key: ValueKey('parsing-${controller.parsingSettings?.model}'),
            task: AiTask.parsing,
            title: 'Lab document parser',
            settings: controller.parsingSettings,
            allowTools: false,
          ),
          SectionHeader(
            title: 'OneDrive AppFolder',
            subtitle:
                'Dedicated SuperHealth storage; no Google or PC linking',
            action: _oneDriveSignedIn == true
                ? const Chip(
                    avatar: Icon(Icons.check, size: 16),
                    label: Text('Connected'),
                  )
                : null,
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(
                    _oneDriveSignedIn == null
                        ? 'Checking connection…'
                        : _oneDriveSignedIn == true
                        ? 'OneDrive is connected'
                        : 'Connect OneDrive',
                  ),
                  subtitle: const Text(
                    'Uses Microsoft Files.ReadWrite.AppFolder and cannot browse your whole drive.',
                  ),
                  trailing: _oneDriveSignedIn == true
                      ? TextButton(
                          onPressed: controller.busy
                              ? null
                              : () => _sync(controller),
                          child: const Text('Sync now'),
                        )
                      : TextButton(
                          onPressed: controller.busy
                              ? null
                              : () => _connectOneDrive(controller),
                          child: const Text('Connect'),
                        ),
                ),
                if (_oneDriveSignedIn == true)
                  ListTile(
                    leading: const Icon(Icons.link_off),
                    title: const Text('Disconnect this device'),
                    onTap: () async {
                      await controller.oneDriveService.signOut();
                      await _refreshOneDriveStatus();
                    },
                  ),
              ],
            ),
          ),
          const SectionHeader(
            title: 'Legacy data import',
            subtitle: 'Previewed, deduplicated, audited, and rollback-capable',
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.move_to_inbox_outlined),
                  title: const Text(
                    'Import Supplement Manager or Biomarkers data',
                  ),
                  subtitle: const Text(
                    'Use Android’s file picker for exported JSON files, '
                    'including files stored in OneDrive.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: controller.busy ? null : () => _importData(controller),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Safety & privacy'),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.storage_outlined),
                  title: Text('Local-first SQLite record'),
                  subtitle: Text(
                    'The AI has no SQL, repository, or database tool.',
                  ),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.folder_outlined),
                  title: Text('File changes require approval'),
                  subtitle: Text(
                    'Provider sandboxes are isolated. Every local or OneDrive workspace write is previewed '
                    'with its exact operation and path before it can be applied.',
                  ),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.health_and_safety_outlined),
                  title: Text('Planning support, not diagnosis'),
                  subtitle: Text(
                    'Evidence labels and safety warnings are required, including for longevity-oriented checks.',
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'SuperHealth 0.1.1 · Personal-use Android build',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectOneDrive(AppController controller) async {
    try {
      final code = await controller.oneDriveService.startDeviceCodeSignIn();
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Connect OneDrive'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Open Microsoft sign-in and enter this one-time code:',
              ),
              const SizedBox(height: 14),
              SelectableText(
                code.userCode,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(code.verificationUri.toString()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(code.verificationUri),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open sign-in'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('I approved it'),
            ),
          ],
        ),
      );
      if (proceed == true) {
        final success = await controller.oneDriveService.pollForSignIn(code);
        if (!success) {
          throw StateError('OneDrive authorization did not complete.');
        }
        await _refreshOneDriveStatus();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('OneDrive connected.')));
        }
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _sync(AppController controller) async {
    try {
      final result = await controller.synchronizeOneDrive();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced ${result.uploadedBytes} bytes · ${result.appliedRows} remote changes · '
              '${result.conflicts} conflicts',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _importData(AppController controller) async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select legacy JSON files',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: true,
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final files = <ImportSourceFile>[];
      for (final selected in selection.files) {
        final bytes =
            selected.bytes ??
            (selected.path == null
                ? null
                : await File(selected.path!).readAsBytes());
        if (bytes != null) {
          files.add(ImportSourceFile(name: selected.name, bytes: bytes));
        }
      }
      if (files.isEmpty) {
        throw StateError('The selected files could not be read.');
      }
      final preview = await controller.previewImport(files);
      if (!mounted) return;
      final approved = await _showImportPreview(preview);
      if (approved == true) {
        final result = await controller.commitImport(preview);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Import completed: ${result.inserted.values.fold(0, (a, b) => a + b)} rows.',
              ),
            ),
          );
        }
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<bool?> _showImportPreview(
    LegacyImportPreview preview,
  ) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Review import'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Detected: ${preview.sourceKinds.join(', ')}'),
              const SizedBox(height: 12),
              for (final entry in preview.counts.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.key.replaceAll('_', ' ')),
                  trailing: Text('${entry.value}'),
                ),
              if (preview.duplicates.isNotEmpty) ...[
                const Divider(),
                Text(
                  'Duplicates / merges',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final item in preview.duplicates) Text('• $item'),
              ],
              if (preview.warnings.isNotEmpty) ...[
                const Divider(),
                Text('Warnings', style: Theme.of(context).textTheme.titleSmall),
                for (final item in preview.warnings) Text('• $item'),
              ],
              if (preview.alreadyImported)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('This exact source has already been imported.'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: preview.canImport
              ? () => Navigator.pop(dialogContext, true)
              : null,
          child: const Text('Import'),
        ),
      ],
    ),
  );
}

class _ApiKeyCard extends StatefulWidget {
  const _ApiKeyCard({required this.provider});

  final AiProvider provider;

  @override
  State<_ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends State<_ApiKeyCard> {
  final _key = TextEditingController();
  bool _visible = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final configured = controller.hasApiKey[widget.provider] == true;
    return Card(
      child: ExpansionTile(
        leading: Icon(configured ? Icons.key : Icons.key_off_outlined),
        title: Text(_providerLabel(widget.provider)),
        subtitle: Text(configured ? 'Key configured' : 'No key configured'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          TextField(
            controller: _key,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: configured ? 'Replace API key' : 'API key',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _visible = !_visible),
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (configured)
                TextButton(
                  onPressed: () async {
                    await controller.saveApiKey(widget.provider, '');
                    _key.clear();
                  },
                  child: const Text('Remove'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _key.text.trim().isEmpty
                    ? null
                    : () async {
                        try {
                          await controller.saveApiKey(
                            widget.provider,
                            _key.text,
                          );
                          _key.clear();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${_providerLabel(widget.provider)} key saved.',
                                ),
                              ),
                            );
                          }
                        } on Object catch (error) {
                          if (context.mounted) {
                            await showAppError(context, error);
                          }
                        }
                      },
                child: const Text('Save key'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _providerLabel(AiProvider provider) => switch (provider) {
    AiProvider.openai => 'OpenAI',
    AiProvider.anthropic => 'Anthropic',
    AiProvider.gemini => 'Google Gemini',
  };
}

class _ModelConfigurationCard extends StatefulWidget {
  const _ModelConfigurationCard({
    required this.task,
    required this.title,
    required this.settings,
    required this.allowTools,
    super.key,
  });

  final AiTask task;
  final String title;
  final AiTaskSettings? settings;
  final bool allowTools;

  @override
  State<_ModelConfigurationCard> createState() =>
      _ModelConfigurationCardState();
}

class _ModelConfigurationCardState extends State<_ModelConfigurationCard> {
  late AiProvider _provider;
  String? _model;
  String? _reasoning;
  bool _web = false;
  bool _code = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.settings?.provider ?? AiProvider.openai;
    _model = widget.settings?.model;
    _reasoning = widget.settings?.reasoningLevel;
    _web = widget.settings?.webSearch ?? false;
    _code = widget.settings?.codeExecution ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final models =
        controller.availableModels[_provider] ?? const <AiModelInfo>[];
    final modelIds = models.map((item) => item.id).toSet();
    final selectedModel =
        modelIds.contains(_model) || (models.isEmpty && _model != null)
        ? _model
        : null;
    final capabilities = selectedModel == null
        ? const ModelCapabilities()
        : controller.capabilityRegistry.forModel(_provider, selectedModel);
    if (_reasoning != null &&
        !capabilities.reasoningLevels.contains(_reasoning)) {
      _reasoning = null;
    }
    if (!capabilities.webSearch) _web = false;
    if (!capabilities.codeExecution) _code = false;

    return Card(
      child: ExpansionTile(
        leading: Icon(
          widget.task == AiTask.advisor
              ? Icons.psychology_outlined
              : Icons.document_scanner_outlined,
        ),
        title: Text(widget.title),
        subtitle: Text(
          widget.settings == null
              ? 'Not configured'
              : '${widget.settings!.provider.name} · ${widget.settings!.model}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          DropdownButtonFormField<AiProvider>(
            initialValue: _provider,
            decoration: const InputDecoration(labelText: 'Provider'),
            items: [
              for (final provider in AiProvider.values)
                DropdownMenuItem(value: provider, child: Text(provider.name)),
            ],
            onChanged: (value) => setState(() {
              _provider = value ?? _provider;
              _model = null;
              _reasoning = null;
              _web = false;
              _code = false;
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'model-${_provider.name}-$selectedModel-${models.length}',
                  ),
                  initialValue: selectedModel,
                  decoration: const InputDecoration(labelText: 'Model'),
                  isExpanded: true,
                  items: [
                    if (models.isEmpty && _model != null)
                      DropdownMenuItem(value: _model, child: Text(_model!)),
                    for (final model in models)
                      DropdownMenuItem(
                        value: model.id,
                        child: Text(
                          model.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _model = value;
                    _reasoning = null;
                    _web = false;
                    _code = false;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Load current models from provider',
                onPressed:
                    controller.busy || controller.hasApiKey[_provider] != true
                    ? null
                    : () async {
                        try {
                          final loaded = await controller.loadModels(_provider);
                          if (mounted) {
                            setState(() {
                              if (_model == null && loaded.isNotEmpty) {
                                _model = loaded.first.id;
                              }
                            });
                          }
                        } on Object catch (error) {
                          if (context.mounted) {
                            await showAppError(context, error);
                          }
                        }
                      },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (capabilities.reasoningLevels.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              key: ValueKey('reasoning-$_model-$_reasoning'),
              initialValue: _reasoning,
              decoration: const InputDecoration(labelText: 'Reasoning level'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Provider default'),
                ),
                for (final level in capabilities.reasoningLevels)
                  DropdownMenuItem<String?>(value: level, child: Text(level)),
              ],
              onChanged: (value) => setState(() => _reasoning = value),
            ),
          ],
          if (widget.allowTools && selectedModel != null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Provider web search'),
              subtitle: Text(
                capabilities.webSearch
                    ? 'Available for this documented model'
                    : 'Not enabled for this model',
              ),
              value: _web,
              onChanged: capabilities.webSearch
                  ? (value) => setState(() => _web = value)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Provider code sandbox'),
              subtitle: Text(
                capabilities.codeExecution
                    ? 'Can calculate and create temporary provider files; no app database access'
                    : 'Not enabled for this model',
              ),
              value: _code,
              onChanged: capabilities.codeExecution
                  ? (value) => setState(() => _code = value)
                  : null,
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: selectedModel == null
                  ? null
                  : () async {
                      try {
                        await controller.saveTaskSettings(
                          widget.task,
                          AiTaskSettings(
                            provider: _provider,
                            model: selectedModel,
                            reasoningLevel: _reasoning,
                            webSearch: widget.allowTools && _web,
                            codeExecution: widget.allowTools && _code,
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${widget.title} settings saved.'),
                            ),
                          );
                        }
                      } on Object catch (error) {
                        if (context.mounted) await showAppError(context, error);
                      }
                    },
              child: const Text('Save configuration'),
            ),
          ),
        ],
      ),
    );
  }
}
