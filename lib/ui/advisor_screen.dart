import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../domain/entities.dart';
import '../workspace/safe_workspace_service.dart';
import 'common.dart';

class AdvisorScreen extends StatefulWidget {
  const AdvisorScreen({super.key});

  @override
  State<AdvisorScreen> createState() => _AdvisorScreenState();
}

class _AdvisorScreenState extends State<AdvisorScreen> {
  final _message = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final settings = controller.advisorSettings;
    if (settings == null) {
      return const PageBody(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: EmptyState(
            icon: Icons.psychology_alt_outlined,
            title: 'Configure the advisor',
            message:
                'Add a provider API key and choose an advisor model in Settings.',
          ),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });

    return PageBody(
      child: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${settings.provider.name} · ${settings.model}'
                      '${settings.reasoningLevel == null ? '' : ' · ${settings.reasoningLevel} reasoning'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  if (settings.webSearch)
                    const Tooltip(
                      message: 'Web search enabled',
                      child: Icon(Icons.public, size: 18),
                    ),
                  if (settings.codeExecution) ...[
                    const SizedBox(width: 8),
                    const Tooltip(
                      message: 'Provider sandbox code enabled',
                      child: Icon(Icons.terminal, size: 18),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (controller.workspaceProposals.isNotEmpty)
            Material(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.rule_folder_outlined),
                title: Text(
                  '${controller.workspaceProposals.length} file change'
                  '${controller.workspaceProposals.length == 1 ? '' : 's'} awaiting approval',
                ),
                subtitle: const Text(
                  'Nothing is written until you review and confirm it.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _reviewFileProposals,
              ),
            ),
          Expanded(
            child: controller.advisorMessages.isEmpty
                ? _AdvisorWelcome(onPrompt: _usePrompt)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
                    itemCount: controller.advisorMessages.length,
                    itemBuilder: (context, index) => _MessageBubble(
                      message: controller.advisorMessages[index],
                    ),
                  ),
          ),
          if (controller.busy) const LinearProgressIndicator(minHeight: 2),
          Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _message,
                        minLines: 1,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Ask about your health data…',
                          helperText: controller.lastContextBytes == null
                              ? 'The complete active profile is sent with each request.'
                              : 'Last context: ${(controller.lastContextBytes! / 1024).toStringAsFixed(1)} KB '
                                    '(~${controller.lastContextTokens} tokens)',
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: controller.busy ? null : _send,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _usePrompt(String prompt) {
    _message.text = prompt;
    _message.selection = TextSelection.collapsed(offset: prompt.length);
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    _message.clear();
    try {
      await context.read<AppController>().askAdvisor(text);
    } on Object catch (error) {
      if (mounted) {
        _message.text = text;
        await showAppError(context, error);
      }
    }
  }

  Future<void> _reviewFileProposals() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.82,
        child: Consumer<AppController>(
          builder: (context, controller, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              Text(
                'Advisor file proposals',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'Review the exact operation, path, and content. These files are separate from the health database.',
              ),
              const SizedBox(height: 12),
              if (controller.workspaceProposals.isEmpty)
                const EmptyState(
                  icon: Icons.task_alt,
                  title: 'No pending file changes',
                  message: 'All proposals have been applied or rejected.',
                )
              else
                for (final proposal in controller.workspaceProposals)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Chip(
                                label: Text(
                                  proposal.operation.name.toUpperCase(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SelectableText(
                                  proposal.relativePath,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ],
                          ),
                          Text(proposal.summary),
                          if (proposal.bytes != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 180),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  const Utf8Decoder(
                                    allowMalformed: true,
                                  ).convert(proposal.bytes!),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => controller
                                    .rejectWorkspaceProposal(proposal.id),
                                child: const Text('Reject'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: controller.busy
                                    ? null
                                    : () => _confirmFileProposal(
                                        sheetContext,
                                        proposal,
                                      ),
                                child: const Text('Review & apply'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmFileProposal(
    BuildContext sheetContext,
    WorkspaceProposal proposal,
  ) async {
    final approved = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: Text('${proposal.operation.name} file?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Exact path'),
              SelectableText(
                proposal.relativePath,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(proposal.summary),
              if (proposal.bytes != null) ...[
                const SizedBox(height: 12),
                const Text('Complete new content'),
                Container(
                  constraints: const BoxConstraints(maxHeight: 320),
                  padding: const EdgeInsets.all(10),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      const Utf8Decoder(
                        allowMalformed: true,
                      ).convert(proposal.bytes!),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Confirm ${proposal.operation.name}'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) {
      try {
        await context.read<AppController>().approveWorkspaceProposal(
          proposal.id,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${proposal.relativePath} updated.')),
          );
        }
      } on Object catch (error) {
        if (mounted) await showAppError(context, error);
      }
    }
  }
}

class _AdvisorWelcome extends StatelessWidget {
  const _AdvisorWelcome({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SizedBox(height: 28),
      Icon(
        Icons.psychology_alt_outlined,
        size: 56,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 14),
      Text(
        'Your health research partner',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      Text(
        'The advisor can reason across your complete active-profile history. '
        'It labels evidence and uncertainty, but does not replace medical care.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 24),
      for (final prompt in const [
        'Review my current supplements for possible duplications, interactions, and monitoring needs.',
        'What patterns in my recent symptoms and tags are worth investigating?',
        'Summarize the most important gaps in my current biomarker history.',
      ])
        Card(
          child: ListTile(
            title: Text(prompt),
            trailing: const Icon(Icons.north_west),
            onTap: () => onPrompt(prompt),
          ),
        ),
    ],
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AdvisorMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.role == 'user';
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: user ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 4),
            bottomRight: Radius.circular(user ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(message.content),
            if (message.citations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var index = 0; index < message.citations.length; index++)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.open_in_new, size: 14),
                      label: Text('Source ${index + 1}'),
                      onPressed: () =>
                          launchUrl(Uri.parse(message.citations[index])),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
