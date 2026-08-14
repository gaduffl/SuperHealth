import 'package:flutter/material.dart';

import '../app/app_localizations.dart';

const _redactedErrorValue = '[redacted]';
const _maxErrorMessageLength = 1200;

/// Produces an actionable, display-safe version of an error message.
///
/// Provider and HTTP libraries can include request headers, OAuth callback
/// URLs, or response payloads in their exception text. Keep the useful error
/// detail while making credential-shaped values safe to show in the UI.
String sanitizeAppErrorMessage(String rawMessage) {
  var message = rawMessage.replaceFirst(
    RegExp(r'^(Exception|StateError):\s*'),
    '',
  );

  message = message.replaceAllMapped(
    RegExp(
      r'''(\bauthorization\b\s*[:=]\s*(?:["']?\s*)?(?:bearer\s+)?)([^"'\s,;}\r\n]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}$_redactedErrorValue',
  );
  message = message.replaceAllMapped(
    RegExp(r'(\bbearer\s+)([^\s,;}\r\n]+)', caseSensitive: false),
    (match) => '${match.group(1)}$_redactedErrorValue',
  );
  message = message.replaceAllMapped(
    RegExp(
      r'''(\b(?:x-api-key|x-goog-api-key|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|authorization[_-]?code)\b["']?\s*[:=]\s*["']?)([^"'\s,;}&\r\n]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}$_redactedErrorValue',
  );
  message = message.replaceAllMapped(
    RegExp(
      r'([?&](?:key|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|authorization[_-]?code|code)=)([^&#\s]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}$_redactedErrorValue',
  );

  if (message.length > _maxErrorMessageLength) {
    return '${message.substring(0, _maxErrorMessageLength)}… [truncated]';
  }
  return message;
}

Future<void> showAppError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  final message = sanitizeAppErrorMessage(error.toString());
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> showConfirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final strings = AppLocalizations.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    )
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel ?? strings.confirm),
            ),
          ],
        ),
      ) ??
      false;
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null)
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackAction = action != null && constraints.maxWidth < 520;
          if (stackAction) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: action!),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              ?action,
            ],
          );
        },
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    ),
  );
}

/// The one place SuperHealth says it is not a doctor.
///
/// It used to be said by the model instead, which meant it was said in every
/// answer, in slightly different words each time, alongside three or four other
/// caveats that were equally true for everyone. That is how a real warning —
/// this interaction, this value, this profile — gets skimmed past. The prompts
/// now forbid the boilerplate outright, which is only defensible because the
/// statement lives here permanently, under every answer and every plan.
class StandingSafetyNotice extends StatelessWidget {
  const StandingSafetyNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            strings.pick(
              'SuperHealth is not a doctor. Get medical care for anything '
                  'severe, sudden, or worrying.',
              'SuperHealth ist kein Arzt. Bei starken, plötzlichen oder '
                  'beunruhigenden Beschwerden ärztliche Hilfe holen.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? detail;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          if (detail != null)
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    ),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 980),
      child: child,
    ),
  );
}

double? parseOptionalDouble(String value) {
  if (value.trim().isEmpty) return null;
  final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
  return parsed != null && parsed.isFinite ? parsed : null;
}

int? parseOptionalInt(String value) =>
    value.trim().isEmpty ? null : int.tryParse(value.trim());

/// The placeholder stored when a product has no unit of its own.
///
/// It exists so the database always has a value, but it is an internal token,
/// not something to put in front of a person: "3 unit" reads as a bug.
const genericStockUnit = 'unit';

/// The unit to show next to an amount of [supplement].
///
/// A unit a person typed themselves is shown exactly as they typed it — it is
/// their vocabulary, in their language. Only the internal placeholder is
/// replaced: first by the product's form ("capsule", "Kapsel", "scoop"), and
/// otherwise by a localized generic word.
String unitLabel(
  AppLocalizations strings, {
  required String unit,
  String? form,
}) {
  final trimmed = unit.trim();
  if (trimmed.isNotEmpty && trimmed.toLowerCase() != genericStockUnit) {
    return trimmed;
  }
  final fallback = form?.trim() ?? '';
  if (fallback.isNotEmpty) return fallback;
  return strings.pick('units', 'Einheiten');
}

/// An amount with its resolved unit, the way it should read in a list row.
String formatAmountWithUnit(
  AppLocalizations strings, {
  required double amount,
  required String unit,
  String? form,
  int decimalDigits = 1,
}) =>
    '${strings.formatNumber(amount, decimalDigits: decimalDigits)} '
    '${unitLabel(strings, unit: unit, form: form)}';

/// Names the lists a biomarker belongs to.
///
/// One or two lists are worth naming outright; beyond that the names crowd out
/// the overdue figure that actually decides whether to book a test.
String listMembershipLabel(AppLocalizations strings, List<String> listNames) {
  if (listNames.isEmpty) return strings.pick('No list', 'Keine Liste');
  if (listNames.length <= 2) return listNames.join(', ');
  return strings.pick(
    '${listNames.first} +${listNames.length - 1} more',
    '${listNames.first} +${listNames.length - 1} weitere',
  );
}
