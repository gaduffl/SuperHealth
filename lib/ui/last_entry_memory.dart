import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_localizations.dart';

/// Remembers the number last typed into a repeated amount field.
///
/// Topping up a product usually means entering the figure entered last time —
/// the same tin, the same jar. But not always, so the remembered value is only
/// ever *shown*: the field itself opens empty, and the number reaches it only
/// by being typed or tapped. That keeps a stale figure from being saved by
/// habit while still answering "how much was it again?".
///
/// This is interface convenience, so it lives in shared preferences next to the
/// other per-profile view state rather than in the health record.
class LastEntryMemory {
  const LastEntryMemory._();

  /// The stock amount last entered for [supplementId] in [mode].
  ///
  /// Modes are kept apart on purpose: "set the total to 40" and "add 120" are
  /// different figures, and offering one where the other belongs would be
  /// worse than offering nothing.
  static String stockSlot({
    required String supplementId,
    required String mode,
  }) => 'stock.$supplementId.$mode';

  static String _key(String profileId, String slot) =>
      'last_entry.$profileId.$slot';

  static Future<double?> read(String profileId, String slot) async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getDouble(_key(profileId, slot));
    return value != null && value.isFinite ? value : null;
  }

  static Future<void> write(String profileId, String slot, double value) async {
    if (!value.isFinite) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_key(profileId, slot), value);
  }

  static Future<void> forget(String profileId, String slot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(profileId, slot));
  }
}

/// The plain, parseable spelling of a remembered amount.
///
/// Localized formatting is for reading; what goes into a numeric field has to
/// survive [parseOptionalDouble], which does not know thousand separators.
String plainAmountText(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toString();

/// A quiet reminder of what was entered here last time.
///
/// Deliberately not a prefilled value: it reports, and only fills the field
/// when the offer is tapped.
class LastEntryHint extends StatelessWidget {
  const LastEntryHint({super.key, required this.label, this.onUse});

  final String label;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.history, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          if (onUse != null)
            TextButton(
              onPressed: onUse,
              child: Text(strings.pick('Use', 'Übernehmen')),
            ),
        ],
      ),
    );
  }
}
