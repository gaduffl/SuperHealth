import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../app/shell_navigation.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'design.dart';
import 'dialogs.dart';
import 'initial_setup_widgets.dart';
import 'settings_screen.dart';
import 'tracking_screen.dart';

/// Easy mode's Today screen.
///
/// The full Today screen answers "how am I doing" with a tile grid, a day
/// strip, an attention list, and a privacy card. This one answers a shorter
/// question — what do I take now, and who do I ask — with targets big enough
/// to hit without aiming. Nothing it leaves out is removed from the app; it is
/// simply not on the screen someone opens twenty times a week.
///
/// Skipping a dose is the one action that did not survive the cut. Recording
/// "I deliberately did not take this" is a distinction that matters to someone
/// analysing adherence later, and the person this screen is for is not that
/// someone: for them it is a second button that has to be understood before
/// the first one can be pressed.
class CalmHomeScreen extends StatefulWidget {
  const CalmHomeScreen({super.key, this.clock = DateTime.now});

  /// The source of "now", injected so a test can turn the calendar over
  /// without waiting for a real midnight.
  final DateTime Function() clock;

  @override
  State<CalmHomeScreen> createState() => _CalmHomeScreenState();
}

class _CalmHomeScreenState extends State<CalmHomeScreen>
    with WidgetsBindingObserver {
  static const _insights = SupplementInsights();

  late DateTime _today;

  Timer? _rolloverTimer;

  @override
  void initState() {
    super.initState();
    _today = widget.clock();
    WidgetsBinding.instance.addObserver(this);
    _scheduleRollover();
  }

  @override
  void dispose() {
    _rolloverTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The app is backgrounded overnight far more often than it is restarted,
    // so resuming is the usual way a screen called Today ends up on yesterday.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_syncToCurrentDay);
      _scheduleRollover();
    }
  }

  /// Safe to call during build: it only assigns when the date turned over.
  void _syncToCurrentDay() {
    final now = widget.clock();
    if (_sameDay(_today, now)) return;
    _today = now;
  }

  /// Wakes the screen at the next midnight, for the app left open across it.
  void _scheduleRollover() {
    _rolloverTimer?.cancel();
    final now = widget.clock();
    final nextDay = DateTime(now.year, now.month, now.day + 1);
    _rolloverTimer = Timer(
      nextDay.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        setState(_syncToCurrentDay);
        _scheduleRollover();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final navigation = context.read<ShellNavigation>();
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = controller.activeProfile!;
    _syncToCurrentDay();
    final now = widget.clock();

    final doses = _insights.dosesForDay(
      day: _today,
      schedules: controller.schedules,
      supplements: controller.supplements,
      intakes: controller.intakes,
    )..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final pending = doses.where((item) => item.intake == null).toList();
    final takenCount = doses.length - pending.length;

    return PageBody(
      child: RefreshIndicator(
        onRefresh: controller.refreshActiveData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
          children: [
            Text(
              strings.greeting(_partOfDay(now), profile.displayName),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.formatDashboardDate(now),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!controller.initialSetupProgress.isComplete) ...[
              const SizedBox(height: 16),
              DashboardSetupPrompt(
                onOpenSettings: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(strings.settings)),
                      body: const SettingsScreen(),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (doses.isEmpty)
              _NothingPlannedCard(controller: controller)
            else ...[
              _ProgressCard(taken: takenCount, total: doses.length),
              const SizedBox(height: 8),
              for (final dose in doses)
                CalmDoseRow(dose: dose, controller: controller),
              if (pending.length > 1) ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: controller.busy
                      ? null
                      : () => _recordAll(context, controller, pending),
                  icon: const Icon(Icons.done_all),
                  label: Text(strings.pick('Take all', 'Alle nehmen')),
                ),
              ],
            ],
            const SizedBox(height: 28),
            _BigAction(
              icon: Icons.forum_outlined,
              label: strings.pick('Ask a question', 'Eine Frage stellen'),
              onPressed: () => navigation.go(AppSection.advisor),
            ),
            const SizedBox(height: 12),
            _BigAction(
              icon: Icons.document_scanner_outlined,
              label: strings.pick(
                'Add a lab report',
                'Laborbericht hinzufügen',
              ),
              onPressed: () => navigation.go(AppSection.labs),
            ),
            const SizedBox(height: 12),
            // A pushed route rather than a permanent seat in the bottom bar:
            // setting products up is something a person does a few times a
            // year, and it does not need to compete with the daily loop.
            _BigAction(
              icon: Icons.medication_outlined,
              label: strings.pick('My supplements', 'Meine Präparate'),
              filled: false,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(strings.supplements)),
                    body: const TrackingScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recordAll(
    BuildContext context,
    AppController controller,
    List<ScheduledDoseStatus> pending,
  ) async {
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final recorded = <SupplementIntake>[];
    try {
      for (final dose in pending) {
        await controller.logIntake(
          supplement: dose.supplement,
          dose: dose.schedule.dose,
          unit: dose.schedule.unit,
          takenAt: DateTime.now(),
          schedule: dose.schedule,
        );
        final match = controller.intakes.firstWhereOrNull(
          (item) => item.scheduleId == dose.schedule.id && !item.deleted,
        );
        if (match != null) recorded.add(match);
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
      return;
    }
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(strings.pick('All recorded.', 'Alles erfasst.')),
        action: recorded.isEmpty
            ? null
            : SnackBarAction(
                label: strings.pick('Undo', 'Rückgängig'),
                onPressed: () async {
                  for (final intake in recorded) {
                    await controller.deleteIntake(intake);
                  }
                },
              ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static AppDayPeriod _partOfDay(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return AppDayPeriod.morning;
    if (hour < 18) return AppDayPeriod.afternoon;
    return AppDayPeriod.evening;
  }
}

/// How much of today is done, in one sentence and one bar.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.taken, required this.total});

  final int taken;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppLocalizations.of(context);
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      color: theme.colorScheme.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.trackingProgress(taken, total),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : taken / total,
              minHeight: 14,
              backgroundColor: theme.colorScheme.onPrimaryContainer.withValues(
                alpha: 0.18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One dose, sized to be pressed without looking for it.
///
/// Public so a widget test can find it without reaching into the screen.
class CalmDoseRow extends StatelessWidget {
  const CalmDoseRow({required this.dose, required this.controller, super.key});

  final ScheduledDoseStatus dose;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final done = dose.intake != null;
    final accent = seriesColorFor(
      dose.supplement.name,
      colorMode: controller.colorMode,
    );
    return SurfaceCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: done || controller.busy ? null : () => _record(context),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? colors.primary.withValues(alpha: 0.16)
                  : accent.withValues(alpha: 0.16),
            ),
            child: Icon(
              done ? Icons.check_circle : Icons.medication_outlined,
              size: 30,
              color: done ? colors.primary : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose.supplement.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    // Struck through would read as an error. Fading is enough
                    // to say "handled" while keeping the name legible.
                    color: done ? colors.onSurfaceVariant : colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatAmountWithUnit(
                    strings,
                    amount: dose.schedule.dose,
                    unit: dose.schedule.unit,
                    form: dose.supplement.form,
                  ),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (done)
            IconButton(
              tooltip: strings.undoCheckIn,
              iconSize: 28,
              style: IconButton.styleFrom(minimumSize: const Size(60, 56)),
              onPressed: controller.busy
                  ? null
                  : () => _undo(context, dose.intake!),
              icon: const Icon(Icons.undo),
            )
          else
            IconButton.filled(
              tooltip: strings.markTaken,
              iconSize: 30,
              style: IconButton.styleFrom(minimumSize: const Size(68, 60)),
              onPressed: controller.busy ? null : () => _record(context),
              icon: const Icon(Icons.check),
            ),
        ],
      ),
    );
  }

  Future<void> _record(BuildContext context) async {
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    try {
      await controller.logIntake(
        supplement: dose.supplement,
        dose: dose.schedule.dose,
        unit: dose.schedule.unit,
        takenAt: DateTime.now(),
        schedule: dose.schedule,
      );
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
      return;
    }
    final recorded = controller.intakes.firstWhereOrNull(
      (item) => item.scheduleId == dose.schedule.id && !item.deleted,
    );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          strings.pick(
            '${dose.supplement.name} recorded.',
            '${dose.supplement.name} erfasst.',
          ),
        ),
        action: recorded == null
            ? null
            : SnackBarAction(
                label: strings.pick('Undo', 'Rückgängig'),
                onPressed: () => controller.deleteIntake(recorded),
              ),
      ),
    );
  }

  Future<void> _undo(BuildContext context, SupplementIntake intake) async {
    try {
      await controller.deleteIntake(intake);
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }
}

/// Shown when the day has no doses at all — including the very first day,
/// when nothing has been set up yet.
class _NothingPlannedCard extends StatelessWidget {
  const _NothingPlannedCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.pick(
              'Nothing to take today',
              'Heute ist nichts einzunehmen',
            ),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings.pick(
              'Add a supplement and it will appear here on the days you take it.',
              'Füge ein Präparat hinzu — es erscheint hier an den Tagen, an denen du es nimmst.',
            ),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => showAddSupplementDialog(context, controller),
            icon: const Icon(Icons.add),
            label: Text(
              strings.pick('Add a supplement', 'Präparat hinzufügen'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width action, tall enough that it does not need to be aimed at.
class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 14),
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    );
    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(onPressed: onPressed, child: child)
          : OutlinedButton(onPressed: onPressed, child: child),
    );
  }
}
