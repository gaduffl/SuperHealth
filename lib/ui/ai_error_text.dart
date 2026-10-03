import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../ai/chatgpt_auth.dart';
import '../ai/provider_clients.dart';
import '../app/app_localizations.dart';

/// An error in the reader's language when the app knows its cause, and as it
/// arrived otherwise.
///
/// Read by `showAppError`, so every flow that reports through it — advisor,
/// lab planner, price updates, sign-in — phrases these cases the same way
/// without each screen catching them.
String appErrorText(BuildContext context, Object error, {DateTime? now}) {
  final strings = AppLocalizations.of(context);
  return switch (error) {
    ProviderUsageLimitException() => usageLimitErrorText(
      strings,
      error,
      now: now ?? DateTime.now(),
    ),
    ChatGptAuthException() => chatGptAuthErrorText(strings, error),
    _ => error.toString(),
  };
}

/// The usage limit with its reset in local time, and the way around it.
///
/// The time alone on the day it lifts, the date as well otherwise: "resets at
/// 14:30" read the next morning would point at the wrong 14:30.
String usageLimitErrorText(
  AppLocalizations strings,
  ProviderUsageLimitException error, {
  required DateTime now,
}) {
  final resetsAt = error.resetsAt?.toLocal();
  if (resetsAt == null) {
    return strings.pick(
      'ChatGPT usage limit reached. Try again later, or choose an API-key '
          'provider for this role in Settings.',
      'ChatGPT-Nutzungsgrenze erreicht. Versuche es später erneut oder wähle '
          'in den Einstellungen für diese Rolle einen Anbieter mit '
          'API-Schlüssel.',
    );
  }
  final today = now.toLocal();
  final time = DateFormat('HH:mm').format(resetsAt);
  final sameDay =
      resetsAt.year == today.year &&
      resetsAt.month == today.month &&
      resetsAt.day == today.day;
  if (sameDay) {
    return strings.pick(
      'ChatGPT usage limit reached – it resets at $time. Until then, choose an '
          'API-key provider for this role in Settings.',
      'ChatGPT-Nutzungsgrenze erreicht – sie wird um $time zurückgesetzt. Bis '
          'dahin kannst du in den Einstellungen für diese Rolle einen Anbieter '
          'mit API-Schlüssel wählen.',
    );
  }
  final date = DateFormat('dd.MM.yyyy').format(resetsAt);
  return strings.pick(
    'ChatGPT usage limit reached – it resets on $date at $time. Until then, '
        'choose an API-key provider for this role in Settings.',
    'ChatGPT-Nutzungsgrenze erreicht – sie wird am $date um $time '
        'zurückgesetzt. Bis dahin kannst du in den Einstellungen für diese '
        'Rolle einen Anbieter mit API-Schlüssel wählen.',
  );
}

/// A sign-in failure in the reader's language.
String chatGptAuthErrorText(
  AppLocalizations strings,
  ChatGptAuthException error,
) {
  final text = switch (error.failure) {
    ChatGptAuthFailure.deviceLoginUnavailable => strings.pick(
      'OpenAI does not offer device-code sign-in right now. Try again later.',
      'OpenAI bietet die Anmeldung per Gerätecode gerade nicht an. Versuche '
          'es später erneut.',
    ),
    ChatGptAuthFailure.codeExpired => strings.pick(
      'The code expired before it was approved. Start the sign-in again.',
      'Der Code ist abgelaufen, bevor er bestätigt wurde. Starte die '
          'Anmeldung erneut.',
    ),
    ChatGptAuthFailure.cancelled => strings.pick(
      'Sign-in cancelled.',
      'Anmeldung abgebrochen.',
    ),
    ChatGptAuthFailure.rejected => strings.pick(
      'OpenAI refused the sign-in.',
      'OpenAI hat die Anmeldung abgelehnt.',
    ),
    ChatGptAuthFailure.sessionExpired => strings.pick(
      'The ChatGPT sign-in has expired. Sign in again.',
      'Die ChatGPT-Anmeldung ist abgelaufen. Melde dich erneut an.',
    ),
    ChatGptAuthFailure.unreachable => strings.pick(
      'OpenAI could not be reached. Check the connection and try again.',
      'OpenAI ist nicht erreichbar. Prüfe die Verbindung und versuche es '
          'erneut.',
    ),
    ChatGptAuthFailure.notSignedIn => strings.pick(
      'Sign in with ChatGPT first.',
      'Melde dich zuerst mit ChatGPT an.',
    ),
  };
  return error.detail == null ? text : '$text (${error.detail})';
}
