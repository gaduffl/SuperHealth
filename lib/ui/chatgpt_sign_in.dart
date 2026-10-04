import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_models.dart';
import '../ai/chatgpt_auth.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import 'common.dart';

String _text(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

/// Signs in to a ChatGPT subscription in place of an API key.
///
/// A card in the providers list with its button always on screen, not a
/// collapsed tile: it is a credential like the keys beside it, and a sign-in
/// that has to be expanded before it shows a button is easy to miss.
class ChatGptSignInCard extends StatelessWidget {
  const ChatGptSignInCard({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final signedIn = controller.hasApiKey[AiProvider.chatgpt] == true;
    final account = controller.chatGptAccount;
    final who = [
      ?account?.email,
      if (account?.planType case final plan?) _planLabel(plan),
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(signedIn ? Icons.verified_user_outlined : Icons.login),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(context, 'ChatGPT subscription', 'ChatGPT-Abo'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        signedIn
                            ? who.isEmpty
                                  ? _text(context, 'Signed in', 'Angemeldet')
                                  : _text(
                                      context,
                                      'Signed in as $who',
                                      'Angemeldet als $who',
                                    )
                            : _text(
                                context,
                                'Not signed in',
                                'Nicht angemeldet',
                              ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _text(
                context,
                'Use your ChatGPT plan instead of an API key. Runs count '
                    'against your plan\'s Codex usage limits rather than API '
                    'billing. Works for the advisor, lab planning and price '
                    'updates; lab document parsing still needs an API key.',
                'Nutze dein ChatGPT-Abo statt eines API-Schlüssels. Läufe '
                    'zählen gegen die Codex-Nutzungsgrenzen deines Abos statt '
                    'gegen API-Abrechnung. Funktioniert für Beratung, '
                    'Laborplanung und Preis-Aktualisierung; die Analyse von '
                    'Labordokumenten braucht weiterhin einen API-Schlüssel.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: signedIn
                  ? TextButton(
                      onPressed: () => _signOut(context, controller),
                      child: Text(_text(context, 'Sign out', 'Abmelden')),
                    )
                  : FilledButton.icon(
                      onPressed: () => _signIn(context, controller),
                      icon: const Icon(Icons.login),
                      label: Text(
                        _text(
                          context,
                          'Sign in with ChatGPT',
                          'Mit ChatGPT anmelden',
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext context, AppController controller) async {
    try {
      final code = await controller.startChatGptSignIn();
      if (!context.mounted) return;
      final result = await showDialog<Object?>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _ChatGptSignInDialog(code: code, controller: controller),
      );
      if (!context.mounted) return;
      if (result == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                context,
                'Signed in with ChatGPT.',
                'Mit ChatGPT angemeldet.',
              ),
            ),
          ),
        );
      } else if (result != null && result != false) {
        await showAppError(context, result);
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }

  Future<void> _signOut(BuildContext context, AppController controller) async {
    try {
      await controller.signOutChatGpt();
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }
}

/// `plus` → `Plus`. OpenAI's raw plan names are lower-case identifiers.
String _planLabel(String plan) => plan.isEmpty
    ? plan
    : '${plan[0].toUpperCase()}${plan.substring(1).replaceAll('_', ' ')}';

/// Shows the code and waits for it to be approved, closing itself when it is.
///
/// It polls while open instead of asking the person to come back and confirm,
/// because on a phone they leave for the browser and return by switching apps;
/// the sign-in should simply be done when they get back.
class _ChatGptSignInDialog extends StatefulWidget {
  const _ChatGptSignInDialog({required this.code, required this.controller});

  final ChatGptDeviceCode code;
  final AppController controller;

  @override
  State<_ChatGptSignInDialog> createState() => _ChatGptSignInDialogState();
}

class _ChatGptSignInDialogState extends State<_ChatGptSignInDialog> {
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_wait());
  }

  @override
  void dispose() {
    // A back gesture closes the dialog without the Cancel button; the polling
    // must stop either way.
    _cancelled = true;
    super.dispose();
  }

  Future<void> _wait() async {
    try {
      await widget.controller.completeChatGptSignIn(
        widget.code,
        isCancelled: () => _cancelled,
      );
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted && !_cancelled) Navigator.pop(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = widget.code.verificationUri;
    return AlertDialog(
      title: Text(
        _text(context, 'Sign in with ChatGPT', 'Mit ChatGPT anmelden'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _text(
              context,
              'Open the OpenAI page, sign in to ChatGPT and enter this '
                  'one-time code:',
              'Öffne die OpenAI-Seite, melde dich bei ChatGPT an und gib '
                  'diesen Einmalcode ein:',
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            widget.code.userCode,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(uri.toString()),
          const SizedBox(height: 14),
          Row(
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _text(
                    context,
                    'Waiting for approval…',
                    'Warte auf Bestätigung …',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The one phishing route this flow has: someone else's code, typed
          // into this account. Codex warns about it the same way.
          Text(
            _text(
              context,
              'Only enter this code if you started this sign-in in '
                  'SuperHealth yourself.',
              'Gib diesen Code nur ein, wenn du diese Anmeldung selbst in '
                  'SuperHealth gestartet hast.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.pop(context, false);
          },
          child: Text(_text(context, 'Cancel', 'Abbrechen')),
        ),
        TextButton.icon(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: widget.code.userCode)),
          icon: const Icon(Icons.copy),
          label: Text(_text(context, 'Copy code', 'Code kopieren')),
        ),
        FilledButton.icon(
          onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new),
          label: Text(_text(context, 'Open sign-in', 'Anmeldung öffnen')),
        ),
      ],
    );
  }
}
