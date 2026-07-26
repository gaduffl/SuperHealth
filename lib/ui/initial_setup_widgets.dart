import 'package:flutter/material.dart';

import '../app/app_localizations.dart';
import '../app/initial_setup_progress.dart';

typedef SetupAction = Future<void> Function();

/// A small, durable-progress checklist. It deliberately represents only
/// derived facts supplied by [InitialSetupProgress], never optimistic taps.
class InitialSetupChecklistCard extends StatelessWidget {
  const InitialSetupChecklistCard({
    required this.progress,
    required this.onCreateProfile,
    required this.onImportJson,
    required this.onSkipJson,
    required this.onAttachPdfs,
    required this.onSkipPdfs,
    required this.onSetUpCloud,
    required this.onSkipCloud,
    required this.onSetUpAdvisor,
    required this.onSkipAdvisor,
    super.key,
  });

  final InitialSetupProgress progress;
  final VoidCallback onCreateProfile;
  final SetupAction onImportJson;
  final SetupAction onSkipJson;
  final SetupAction onAttachPdfs;
  final SetupAction onSkipPdfs;
  final SetupAction onSetUpCloud;
  final SetupAction onSkipCloud;
  final VoidCallback onSetUpAdvisor;
  final SetupAction onSkipAdvisor;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.initialSetup,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 3),
            Text(
              strings.initialSetupDescription,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _SetupRow(
              title: strings.setupProfile,
              complete: progress.profileExists,
              primaryLabel: strings.createFirstProfile,
              onPrimary: onCreateProfile,
            ),
            _SetupRow(
              title: strings.setupLegacyJson,
              complete: progress.legacyJsonHandled,
              primaryLabel: strings.importData,
              onPrimary: onImportJson,
              primaryEnabled: progress.profileExists,
              skipLabel: strings.skipForNow,
              onSkip: onSkipJson,
            ),
            _SetupRow(
              title: strings.setupPdfs,
              complete: progress.legacyPdfsHandled,
              primaryLabel: strings.attachPdfs,
              onPrimary: onAttachPdfs,
              primaryEnabled: progress.profileExists,
              skipLabel: strings.skipForNow,
              onSkip: onSkipPdfs,
            ),
            _SetupRow(
              title: strings.setupCloud,
              complete: progress.cloudHandled,
              primaryLabel: strings.setUp,
              onPrimary: onSetUpCloud,
              skipLabel: strings.skipForNow,
              onSkip: onSkipCloud,
            ),
            _SetupRow(
              title: strings.setupAdvisor,
              complete: progress.advisorHandled,
              primaryLabel: strings.setUp,
              onPrimary: onSetUpAdvisor,
              skipLabel: strings.skipForNow,
              onSkip: onSkipAdvisor,
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    required this.title,
    required this.complete,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryEnabled = true,
    this.skipLabel,
    this.onSkip,
  });

  final String title;
  final bool complete;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final bool primaryEnabled;
  final String? skipLabel;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context);
    return Semantics(
      label: '$title: ${complete ? strings.done : strings.initialSetup}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  complete ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: complete ? scheme.primary : scheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title)),
                if (complete)
                  Text(
                    strings.done,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: scheme.primary),
                  ),
              ],
            ),
            if (!complete)
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 0,
                  children: [
                    TextButton(
                      onPressed: primaryEnabled ? onPrimary : null,
                      child: Text(primaryLabel),
                    ),
                    if (onSkip != null)
                      TextButton(onPressed: onSkip, child: Text(skipLabel!)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Session-dismissible dashboard reminder. The persistent checklist remains in
/// Settings, so dismissing this never changes any setup fact.
class DashboardSetupPrompt extends StatefulWidget {
  const DashboardSetupPrompt({required this.onOpenSettings, super.key});

  final VoidCallback onOpenSettings;

  @override
  State<DashboardSetupPrompt> createState() => _DashboardSetupPromptState();
}

class _DashboardSetupPromptState extends State<DashboardSetupPrompt> {
  var _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.checklist_outlined),
            title: Text(strings.finishSetup),
            subtitle: Text(strings.finishSetupDescription),
            onTap: widget.onOpenSettings,
            trailing: IconButton(
              tooltip: strings.cancel,
              onPressed: () => setState(() => _dismissed = true),
              icon: const Icon(Icons.close),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: TextButton(
                onPressed: widget.onOpenSettings,
                child: Text(strings.settings),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
