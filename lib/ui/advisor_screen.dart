import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../app/shell_navigation.dart';
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
  int? _handledRequestToken;

  /// Picks up a question handed over from another screen and asks it.
  ///
  /// The advisor needs a configured model, so an unconfigured app leaves the
  /// text in the box rather than dropping the question.
  void _applyRequest(ShellNavigation navigation, {required bool canAsk}) {
    final request = navigation.request;
    final prompt = request?.prompt;
    if (request == null ||
        prompt == null ||
        request.section != AppSection.advisor ||
        request.token == _handledRequestToken) {
      return;
    }
    _handledRequestToken = request.token;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      navigation.completeRequest(request.token);
      _usePrompt(prompt);
      if (canAsk) await _send();
    });
  }

  @override
  void dispose() {
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final strings = AppLocalizations.of(context);
    final settings = controller.advisorSettings;
    _applyRequest(
      context.watch<ShellNavigation>(),
      canAsk: settings != null && !controller.busy,
    );
    if (settings == null) {
      return PageBody(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: EmptyState(
            icon: Icons.psychology_alt_outlined,
            title: strings.configureAdvisor,
            message: strings.configureAdvisorDescription,
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
                      strings.providerReasoning(
                        settings.provider.name,
                        settings.model,
                        settings.reasoningLevel,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  if (settings.webSearch)
                    Tooltip(
                      message: strings.webSearchEnabled,
                      child: Icon(Icons.public, size: 18),
                    ),
                  if (settings.codeExecution) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: strings.codeExecutionEnabled,
                      child: Icon(Icons.terminal, size: 18),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _ConversationBar(
            controller: controller,
            onBrowse: _browseConversations,
          ),
          if (controller.workspaceProposals.isNotEmpty)
            Material(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.rule_folder_outlined),
                title: Text(
                  strings.pendingFileProposals(
                    controller.workspaceProposals.length,
                  ),
                ),
                subtitle: Text(strings.proposalSafetyCopy),
                trailing: const Icon(Icons.chevron_right),
                onTap: _reviewFileProposals,
              ),
            ),
          Expanded(
            child: _ThreadView(
              controller: controller,
              scroll: _scroll,
              onPrompt: _usePrompt,
            ),
          ),
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
                          hintText: strings.askHealthData,
                          helperText: _contextHelper(context, controller),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: strings.send,
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

  /// The context line under the composer.
  ///
  /// Once a message has been sent, the provider's reported token counts
  /// replace the app's pre-flight estimate: one is measured, the other is a
  /// byte-based approximation, and showing them together would imply both are
  /// equally solid.
  String _contextHelper(BuildContext context, AppController controller) {
    final strings = AppLocalizations.of(context);
    final usage = controller.lastTokenUsage;
    if (usage != null && !usage.isEmpty) {
      final input = usage.inputTokens;
      final output = usage.outputTokens;
      return strings.pick(
        'Last message: ${input ?? '?'} in / ${output ?? '?'} out tokens',
        'Letzte Nachricht: ${input ?? '?'} rein / ${output ?? '?'} raus Token',
      );
    }
    if (controller.lastContextBytes == null) return strings.completeProfileSent;
    return strings.lastContext(
      controller.lastContextBytes!,
      controller.lastContextTokens,
    );
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

  /// Lists every conversation and lets one be opened or deleted.
  Future<void> _browseConversations() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.75,
        // Reads the controller rather than closing over the list, so a delete
        // inside the sheet updates the sheet.
        child: Consumer<AppController>(
          builder: (context, controller, _) {
            final strings = AppLocalizations.of(context);
            final conversations = controller.advisorConversations;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    strings.advisorConversations,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Expanded(
                  child: conversations.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: EmptyState(
                            icon: Icons.forum_outlined,
                            title: strings.advisorNoConversations,
                            message: strings.advisorNoConversationsDescription,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          itemCount: conversations.length,
                          itemBuilder: (context, index) {
                            final conversation = conversations[index];
                            final active =
                                conversation.id ==
                                controller.activeConversationId;
                            return ListTile(
                              selected: active,
                              leading: Icon(
                                active
                                    ? Icons.forum
                                    : Icons.chat_bubble_outline,
                              ),
                              title: Text(
                                conversation.title.isEmpty
                                    ? strings.advisorUntitledConversation
                                    : conversation.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                strings.advisorConversationSummary(
                                  conversation.messageCount,
                                  DateFormat.yMMMd().add_Hm().format(
                                    conversation.lastMessageAt,
                                  ),
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: strings.delete,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteConversation(
                                  context,
                                  controller,
                                  conversation,
                                ),
                              ),
                              onTap: () async {
                                final navigator = Navigator.of(context);
                                await controller.openAdvisorConversation(
                                  conversation.id,
                                );
                                navigator.pop();
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteConversation(
    BuildContext context,
    AppController controller,
    AdvisorConversation conversation,
  ) async {
    final strings = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.advisorDeleteConversation),
        content: Text(strings.advisorDeleteConversationDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.deleteAdvisorConversation(conversation.id);
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
                AppLocalizations.of(context).advisorFileProposals,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context).advisorFileProposalsDescription,
              ),
              const SizedBox(height: 12),
              if (controller.workspaceProposals.isEmpty)
                EmptyState(
                  icon: Icons.task_alt,
                  title: AppLocalizations.of(context).noPendingFileChanges,
                  message: AppLocalizations.of(
                    context,
                  ).noPendingFileChangesDescription,
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
                                child: Text(
                                  AppLocalizations.of(context).reject,
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: controller.busy
                                    ? null
                                    : () => _confirmFileProposal(
                                        sheetContext,
                                        proposal,
                                      ),
                                child: Text(
                                  AppLocalizations.of(context).reviewAndApply,
                                ),
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
        title: Text(
          AppLocalizations.of(
            dialogContext,
          ).confirmFileOperation(proposal.operation.name),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(AppLocalizations.of(dialogContext).exactPath),
              SelectableText(
                proposal.relativePath,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(proposal.summary),
              if (proposal.bytes != null) ...[
                const SizedBox(height: 12),
                Text(AppLocalizations.of(dialogContext).completeNewContent),
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
            child: Text(AppLocalizations.of(dialogContext).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              AppLocalizations.of(
                dialogContext,
              ).confirmOperation(proposal.operation.name),
            ),
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
            SnackBar(
              content: Text(
                AppLocalizations.of(context).updatedFile(proposal.relativePath),
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (mounted) await showAppError(context, error);
      }
    }
  }
}

/// The message thread, including the question still being answered.
///
/// The welcome panel only stands in for an *idle* empty conversation. Once a
/// question is in flight the thread has something in it, and showing the
/// welcome text plus a progress bar instead made a sent question look lost —
/// it is gone from the input box and not yet in the database, so there was
/// nowhere it appeared.
class _ThreadView extends StatelessWidget {
  const _ThreadView({
    required this.controller,
    required this.scroll,
    required this.onPrompt,
  });

  final AppController controller;
  final ScrollController scroll;
  final void Function(String) onPrompt;

  @override
  Widget build(BuildContext context) {
    final pending = controller.pendingAdvisorQuestion;
    final messages = controller.advisorMessages;
    if (messages.isEmpty && pending == null) {
      return _AdvisorWelcome(onPrompt: onPrompt);
    }
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
      // One extra row for the question in flight and the indicator under it.
      itemCount: messages.length + (pending == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index < messages.length) {
          return _MessageBubble(message: messages[index]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MessageBubble(
              message: AdvisorMessage(
                id: 'pending',
                profileId: controller.activeProfile?.id ?? '',
                conversationId: controller.activeConversationId,
                role: 'user',
                content: pending!,
                createdAt: DateTime.now(),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        );
      },
    );
  }
}

/// Names the conversation being read, and offers the two ways out of it.
///
/// Above the messages rather than in an app bar, because this screen has none
/// — it is a section of the shell. Which conversation you are in is the kind of
/// thing that has to be visible without tapping anything, or a question lands
/// in the wrong one.
class _ConversationBar extends StatelessWidget {
  const _ConversationBar({required this.controller, required this.onBrowse});

  final AppController controller;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final current = controller.advisorConversations
        .where((item) => item.id == controller.activeConversationId)
        .firstOrNull;
    // No entry in the list means nothing has been said in it yet.
    final title = current == null
        ? strings.advisorNewConversation
        : (current.title.isEmpty
              ? strings.advisorUntitledConversation
              : current.title);
    return Material(
      color: scheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: onBrowse,
                icon: const Icon(Icons.forum_outlined, size: 20),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: strings.advisorNewConversation,
              // Disabled mid-turn: the answer would be saved into the
              // conversation the question was asked in, not the new one, and
              // the screen would show neither.
              onPressed: controller.busy
                  ? null
                  : controller.startNewAdvisorConversation,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvisorWelcome extends StatelessWidget {
  const _AdvisorWelcome({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return ListView(
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
          strings.advisorWelcomeTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          strings.advisorWelcomeDescription,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        for (final prompt in [
          strings.welcomePromptSupplements,
          strings.welcomePromptPatterns,
          strings.welcomePromptBiomarkers,
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
                    if (_safeWebUri(message.citations[index]) case final uri?)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.open_in_new, size: 14),
                        label: Text(
                          AppLocalizations.of(context).sourceNumber(index + 1),
                        ),
                        onPressed: () => launchUrl(uri),
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

Uri? _safeWebUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return uri;
}
