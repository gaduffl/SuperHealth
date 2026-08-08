import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../app/shell_navigation.dart';
import '../biomarkers/biomarker_status_service.dart';
import '../domain/entities.dart';
import 'check_in_dialog.dart';
import 'common.dart';
import 'design.dart';
import 'dialogs.dart';
import 'initial_setup_widgets.dart';
import 'settings_screen.dart';

/// The Today screen.
///
/// Opens with SuperHealth's overview tiles — every one of them a shortcut into
/// the screen that owns the number — then continues with the day-by-day dosing
/// workflow carried over from Supplement Manager.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.clock = DateTime.now});

  /// The source of "now", injected so a test can turn the calendar over
  /// without waiting for a real midnight.
  final DateTime Function() clock;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  static const _insights = SupplementInsights();

  /// Anchors the "today's doses" tile, which sits on the screen it links to and
  /// so has to scroll rather than navigate.
  final _dayPlanKey = GlobalKey();

  late DateTime _selectedDay;

  /// The calendar day this screen last synchronised to.
  ///
  /// The app is not restarted daily — it is left open, or backgrounded for
  /// days — and a `_selectedDay` captured at launch would still be showing that
  /// launch day a week later, under a header rendering the real date. Reviewing
  /// a past day stays put while the owner works, but only until the date turns
  /// over; a screen called Today that opens on yesterday is worse than one that
  /// forgets a selection.
  late DateTime _dayAnchor;

  Timer? _rolloverTimer;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.clock();
    _dayAnchor = _selectedDay;
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
    // Resuming is the common way a stale day becomes visible: the app was
    // backgrounded yesterday and reopened this morning.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(_syncToCurrentDay);
      _scheduleRollover();
    }
  }

  /// Moves the selection to today when the date has turned over since it was
  /// made. Safe to call during build: it only assigns when the day changed.
  void _syncToCurrentDay() {
    final now = widget.clock();
    if (_sameDay(_dayAnchor, now)) return;
    _dayAnchor = now;
    _selectedDay = now;
  }

  /// Wakes the screen at the next midnight, for the app left open and visible
  /// across it — nothing else would rebuild, so the date would silently rot.
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

  Future<void> _scrollToDayPlan() async {
    final target = _dayPlanKey.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final navigation = context.read<ShellNavigation>();
    final strings = AppLocalizations.of(context);
    final profile = controller.activeProfile!;
    // Before anything reads it: opening the app after midnight rebuilds here
    // first, so this is what makes "Today" mean today rather than launch day.
    _syncToCurrentDay();
    final now = widget.clock();
    final viewingToday = _sameDay(_selectedDay, now);

    final doses = _insights.dosesForDay(
      day: _selectedDay,
      schedules: controller.schedules,
      supplements: controller.supplements,
      intakes: controller.intakes,
    );
    final dayIntakes =
        controller.intakes
            .where(
              (item) => !item.deleted && _sameDay(item.takenAt, _selectedDay),
            )
            .toList()
          ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final takenCount = doses.where((item) => item.taken).length;
    final progress = doses.isEmpty ? null : takenCount / doses.length;

    return PageBody(
      child: RefreshIndicator(
        onRefresh: controller.refreshActiveData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            Text(
              strings.greeting(_partOfDay(now), profile.displayName),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 2),
            Text(
              strings.formatDashboardDate(now),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!controller.initialSetupProgress.isComplete) ...[
              const SizedBox(height: 12),
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
            const SizedBox(height: 16),
            // Hiding screens makes the app smaller, not easier. The loop that
            // matters — report in, status out, question answered — is four
            // navigations deep in the full app; here it is one.
            if (controller.visibility.leadWithLabReport) ...[
              _LabReportCard(controller: controller, navigation: navigation),
              const SizedBox(height: 16),
            ],
            _OverviewTiles(
              controller: controller,
              navigation: navigation,
              onShowDayPlan: _scrollToDayPlan,
            ),
            SectionHeader(
              key: _dayPlanKey,
              title: strings.pick('Your day', 'Dein Tag'),
              subtitle: strings.pick(
                'Pick a day to review or complete its doses.',
                'Wähle einen Tag, um Dosen zu prüfen oder nachzutragen.',
              ),
            ),
            if (controller.visibility.pastDayEditing)
              DayStrip(
                selectedDay: _selectedDay,
                onSelected: (day) => setState(() => _selectedDay = day),
                weekdayLabel: (day) =>
                    strings.formatTrackingWeekday(day).substring(0, 2),
                dayLabel: (day) =>
                    strings.formatNumber(day.day.toDouble(), decimalDigits: 0),
                semanticLabel: strings.formatTrackingDate,
                markerFor: (day) => _completionFor(controller, day),
              ),
            const SizedBox(height: 8),
            _YourDayCard(
              day: _selectedDay,
              doses: doses,
              dayIntakes: dayIntakes,
              takenCount: takenCount,
              progress: progress,
              busy: controller.busy,
              onLogPeriod: (period) =>
                  _logAllForPeriod(context, controller, doses, period),
              onLogExtra: controller.supplements.isEmpty
                  ? () => showAddSupplementDialog(context, controller)
                  : () => _logManualIntake(context, controller),
              onAnalyze: doses.isEmpty && dayIntakes.isEmpty
                  ? null
                  : () => _analyzeDay(
                      context,
                      controller,
                      navigation,
                      doses,
                      dayIntakes,
                    ),
              onOpenCheckIn: () => showDailyCheckInDialog(
                context,
                controller,
                day: _selectedDay,
              ),
            ),
            for (final period in DosePeriod.values)
              _PeriodBlock(
                period: period,
                doses: doses.where((item) => item.period == period).toList(),
                extras: _unscheduledFor(dayIntakes, doses, period),
                controller: controller,
                selectedDay: _selectedDay,
                viewingToday: viewingToday,
              ),
            if (doses.isEmpty && dayIntakes.isEmpty)
              EmptyState(
                icon: Icons.event_available_outlined,
                title: strings.noDosesForThisDay,
                message: controller.schedules.isEmpty
                    ? strings.addScheduleFromCatalog
                    : strings.scheduleFreeDay,
                action: FilledButton.tonalIcon(
                  onPressed: () => navigation.go(AppSection.catalog),
                  icon: const Icon(Icons.medication_outlined),
                  label: Text(strings.catalog),
                ),
              ),
            _NeedsAttention(
              controller: controller,
              doses: doses,
              navigation: navigation,
            ),
            SectionHeader(
              title: strings.privacyBoundary,
              subtitle: strings.privacyBoundaryDescription,
            ),
            SurfaceCard(
              color: Theme.of(
                context,
              ).colorScheme.secondaryContainer.withValues(alpha: 0.5),
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(strings.keysNeverSynced),
                subtitle: Text(strings.keysNeverSyncedDescription),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The share of a day's due doses that are recorded, for the day strip bar.
  double? _completionFor(AppController controller, DateTime day) {
    final doses = _insights.dosesForDay(
      day: day,
      schedules: controller.schedules,
      supplements: controller.supplements,
      intakes: controller.intakes,
    );
    if (doses.isEmpty) return null;
    return doses.where((item) => item.taken).length / doses.length;
  }

  /// Intakes recorded in a block that no scheduled dose accounts for.
  List<SupplementIntake> _unscheduledFor(
    List<SupplementIntake> dayIntakes,
    List<ScheduledDoseStatus> doses,
    DosePeriod period,
  ) {
    final claimed = {
      for (final dose in doses)
        if (dose.intake != null) dose.intake!.id,
    };
    return dayIntakes
        .where(
          (item) =>
              !claimed.contains(item.id) &&
              _insights.periodOfHour(item.takenAt.hour) == period,
        )
        .toList();
  }

  Future<void> _logAllForPeriod(
    BuildContext context,
    AppController controller,
    List<ScheduledDoseStatus> doses,
    DosePeriod period,
  ) async {
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final pending = doses
        .where((item) => item.period == period && item.intake == null)
        .toList();
    if (pending.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings.pick(
              'Everything in this block is already recorded.',
              'In diesem Block ist bereits alles erfasst.',
            ),
          ),
        ),
      );
      return;
    }
    final recorded = <SupplementIntake>[];
    try {
      for (final dose in pending) {
        await controller.logIntake(
          supplement: dose.supplement,
          dose: dose.schedule.dose,
          unit: dose.schedule.unit,
          takenAt: _timestampFor(dose),
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
        content: Text(
          strings.pick(
            'Recorded ${pending.length} dose(s).',
            '${pending.length} Dosis/Dosen erfasst.',
          ),
        ),
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

  /// Records against the dose's own due time when back-filling a past day, so
  /// the entry lands in the block a person is actually looking at.
  DateTime _timestampFor(ScheduledDoseStatus dose) {
    final now = DateTime.now();
    return _sameDay(dose.dueAt, now) ? now : dose.dueAt;
  }

  /// Hands the day's supplements and their components to the advisor.
  ///
  /// Supplement Manager ran its own one-off analysis call. Routing through the
  /// advisor instead keeps a single BYOK code path, one place where the health
  /// context is assembled, and the answer in the conversation history.
  void _analyzeDay(
    BuildContext context,
    AppController controller,
    ShellNavigation navigation,
    List<ScheduledDoseStatus> doses,
    List<SupplementIntake> dayIntakes,
  ) {
    final strings = AppLocalizations.of(context);
    final lines = <String>{};
    for (final dose in doses) {
      lines.add(
        _describe(
          strings,
          dose.supplement,
          dose.schedule.dose,
          dose.schedule.unit,
          taken: dose.taken,
        ),
      );
    }
    for (final intake in dayIntakes.where((item) => !item.skipped)) {
      final supplement = controller.supplements.firstWhereOrNull(
        (item) => item.id == intake.supplementId,
      );
      if (supplement == null) continue;
      lines.add(
        _describe(strings, supplement, intake.dose, intake.unit, taken: true),
      );
    }
    if (lines.isEmpty) return;
    final question = strings.pick(
      'Review my supplement intake for ${strings.formatTrackingDate(_selectedDay)}. '
          'Flag interactions, duplicate active ingredients, and anything above '
          'a commonly cited upper limit. Plan for the day:\n'
          '${lines.join('\n')}',
      'Prüfe meine Supplement-Einnahme für '
          '${strings.formatTrackingDate(_selectedDay)}. Weise auf '
          'Wechselwirkungen, doppelte Wirkstoffe und alles über einer üblichen '
          'Obergrenze hin. Plan für den Tag:\n'
          '${lines.join('\n')}',
    );
    navigation.askAdvisor(question);
  }

  /// One line per product: dose, status, and the components it contributes.
  String _describe(
    AppLocalizations strings,
    Supplement supplement,
    double dose,
    String unit, {
    required bool taken,
  }) {
    final components = [
      for (final ingredient in supplement.ingredients)
        [
          ingredient['name'],
          ingredient['amount'],
          ingredient['unit'],
        ].where((item) => item != null && '$item'.isNotEmpty).join(' '),
    ].where((item) => item.isNotEmpty);
    final status = taken
        ? strings.pick('recorded', 'erfasst')
        : strings.pick('planned', 'geplant');
    return '- ${supplement.name} '
        '${formatAmountWithUnit(strings, amount: dose, unit: unit, form: supplement.form)} ($status)'
        '${components.isEmpty ? '' : ' — ${components.join(', ')}'}';
  }

  Future<void> _logManualIntake(
    BuildContext context,
    AppController controller,
  ) async {
    final strings = AppLocalizations.of(context);
    final active = controller.supplements
        .where((item) => item.active && !item.deleted)
        .toList();
    final product = await showModalBottomSheet<Supplement>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(strings.whichSupplement),
              subtitle: Text(
                strings.pick(
                  'Records an unplanned dose for the selected day.',
                  'Erfasst eine ungeplante Dosis für den gewählten Tag.',
                ),
              ),
            ),
            for (final item in active)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: seriesColorFor(
                    item.name,
                    colorMode: controller.colorMode,
                  ).withValues(alpha: 0.18),
                  child: const Icon(Icons.medication_outlined, size: 20),
                ),
                title: Text(item.name),
                subtitle: item.brand.isEmpty ? null : Text(item.brand),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
          ],
        ),
      ),
    );
    if (product == null || !context.mounted) return;
    final now = DateTime.now();
    await showLogIntakeDialog(
      context,
      controller,
      product,
      initialTakenAt: _sameDay(_selectedDay, now)
          ? now
          : DateTime(
              _selectedDay.year,
              _selectedDay.month,
              _selectedDay.day,
              now.hour,
              now.minute,
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

/// The overview tiles. Each one opens the screen that owns its number, with
/// the matching filter already applied where one exists.
class _OverviewTiles extends StatelessWidget {
  const _OverviewTiles({
    required this.controller,
    required this.navigation,
    required this.onShowDayPlan,
  });

  final AppController controller;
  final ShellNavigation navigation;
  final VoidCallback onShowDayPlan;

  @override
  Widget build(BuildContext context) {
    const insights = SupplementInsights();
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final profile = controller.activeProfile!;
    final now = DateTime.now();

    final latestMeasurements = <String, Measurement>{};
    for (final measurement in controller.measurements) {
      final existing = latestMeasurements[measurement.biomarkerId];
      if (existing == null || measurement.takenAt.isAfter(existing.takenAt)) {
        latestMeasurements[measurement.biomarkerId] = measurement;
      }
    }
    final statusService = BiomarkerStatusService();
    final latestStatuses = [
      for (final biomarker in controller.biomarkers)
        statusService.evaluate(
          biomarker: biomarker,
          measurement: latestMeasurements[biomarker.id],
          profile: profile,
          targets: controller.profileTargets,
          referenceRanges: controller.biomarkerRanges,
          now: now,
        ),
    ];
    final belowCount = latestStatuses.where((item) => item.isBelow).length;
    final aboveCount = latestStatuses.where((item) => item.isAbove).length;
    final unavailableCount = latestStatuses
        .where((item) => item.kind == BiomarkerStatusKind.unavailable)
        .length;
    final noComparisonRangeCount = latestStatuses
        .where((item) => item.kind == BiomarkerStatusKind.noComparisonRange)
        .length;
    final neverMeasuredCount = latestStatuses
        .where((item) => item.kind == BiomarkerStatusKind.neverMeasured)
        .length;
    final activeSupplements = controller.supplements
        .where((item) => item.active && !item.deleted)
        .length;
    final scheduledToday = insights.dosesForDay(
      day: now,
      schedules: controller.schedules,
      supplements: controller.supplements,
      intakes: controller.intakes,
    );
    final lowStock = insights
        .stockProjections(
          supplements: controller.supplements,
          householdSchedules: controller.householdSchedules,
          stockLevels: controller.stockLevels,
        )
        .where((item) => item.low)
        .length;
    final journalDays = controller.events
        .where((event) => !event.deleted)
        .map(
          (event) => DateTime(
            event.observedAt.year,
            event.observedAt.month,
            event.observedAt.day,
          ),
        )
        .toSet()
        .length;

    final tiles = <Widget>[
      StatTile(
        label: strings.todayDoses,
        value: strings.doseProgress(
          scheduledToday.where((item) => item.taken).length,
          scheduledToday.length,
        ),
        icon: Icons.medication_outlined,
        detail: strings.activeProducts(activeSupplements),
        onTap: onShowDayPlan,
      ),
      StatTile(
        label: strings.biomarkersDue,
        value: '${controller.dueBiomarkers.length}',
        icon: Icons.science_outlined,
        detail: strings.measured(latestMeasurements.length),
        tone: controller.dueBiomarkers.isEmpty ? null : colors.error,
        onTap: () => navigation.go(
          AppSection.biomarkers,
          filter: SectionFilter.dueBiomarkers,
        ),
      ),
      StatTile(
        label: strings.lowStock,
        value: '$lowStock',
        icon: Icons.inventory_2_outlined,
        detail: strings.householdInventory,
        tone: lowStock == 0 ? null : colors.error,
        onTap: () =>
            navigation.go(AppSection.stock, filter: SectionFilter.lowStock),
      ),
      StatTile(
        label: strings.labPlans,
        value: '${controller.labPlans.length}',
        icon: Icons.checklist_outlined,
        detail: controller.labPlans.isEmpty
            ? strings.createFirstPlan
            : strings.savedChecklists,
        onTap: () => navigation.go(AppSection.labs),
      ),
      StatTile(
        label: strings.latestBelow,
        value: '$belowCount',
        icon: Icons.arrow_downward_outlined,
        detail: strings.comparisonDescription,
        onTap: () => navigation.go(
          AppSection.biomarkers,
          filter: SectionFilter.belowTarget,
        ),
      ),
      StatTile(
        label: strings.latestAbove,
        value: '$aboveCount',
        icon: Icons.arrow_upward_outlined,
        detail: strings.comparisonDescription,
        onTap: () => navigation.go(
          AppSection.biomarkers,
          filter: SectionFilter.aboveTarget,
        ),
      ),
      StatTile(
        label: strings.rangeUnavailable,
        value:
            '${noComparisonRangeCount + unavailableCount + neverMeasuredCount}',
        icon: Icons.help_outline,
        detail: [
          strings.pick(
            '$noComparisonRangeCount no range',
            '$noComparisonRangeCount ohne Bereich',
          ),
          if (unavailableCount > 0) strings.unavailableCount(unavailableCount),
          strings.neverMeasuredCount(neverMeasuredCount),
        ].join(' · '),
        onTap: () => navigation.go(
          AppSection.biomarkers,
          filter: SectionFilter.withoutUsableRange,
        ),
      ),
      StatTile(
        label: strings.journal,
        value: '$journalDays',
        icon: Icons.event_note_outlined,
        detail: strings.pick('Days recorded', 'Erfasste Tage'),
        onTap: () => navigation.go(AppSection.journal),
      ),
    ];

    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
      childAspectRatio: 1.22,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }
}

enum _YourDayMenuAction { analyze }

/// One compact home for the selected day's supplement and check-in workflow.
class _YourDayCard extends StatelessWidget {
  const _YourDayCard({
    required this.day,
    required this.doses,
    required this.dayIntakes,
    required this.takenCount,
    required this.progress,
    required this.busy,
    required this.onLogPeriod,
    required this.onLogExtra,
    required this.onAnalyze,
    required this.onOpenCheckIn,
  });

  final DateTime day;
  final List<ScheduledDoseStatus> doses;
  final List<SupplementIntake> dayIntakes;
  final int takenCount;
  final double? progress;
  final bool busy;
  final ValueChanged<DosePeriod> onLogPeriod;
  final VoidCallback onLogExtra;
  final VoidCallback? onAnalyze;
  final VoidCallback onOpenCheckIn;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final openPeriods = [
      for (final period in DosePeriod.values)
        if (doses.any((item) => item.period == period && item.intake == null))
          period,
    ];
    final scheduledIntakeIds = {
      for (final dose in doses)
        if (dose.intake != null) dose.intake!.id,
    };
    final extraCount = dayIntakes
        .where(
          (intake) =>
              !intake.skipped && !scheduledIntakeIds.contains(intake.id),
        )
        .length;
    final entries = _dailyCheckInSummaries(controller, day, strings);
    final symptomCount = entries
        .where((entry) => entry.kind == EventKind.symptom)
        .length;
    final tagCount = entries.length - symptomCount;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.formatTrackingDate(day),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      doses.isEmpty
                          ? strings.nothingScheduled
                          : strings.trackingProgress(takenCount, doses.length),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ProgressRing(
                value: progress,
                label: progress == null
                    ? '—'
                    : strings.formatPercent(progress!),
                size: 78,
                strokeWidth: 9,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.medication_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.pick('Supplements', 'Supplemente'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                strings.doseProgress(takenCount, doses.length),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            doses.isEmpty
                ? strings.nothingScheduled
                : openPeriods.isEmpty
                ? strings.pick(
                    'Every scheduled dose has been recorded.',
                    'Alle geplanten Dosen wurden erfasst.',
                  )
                : strings.pick(
                    'Record everything still open in a part of the day.',
                    'Erfasse alles Offene eines Tagesabschnitts.',
                  ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (openPeriods.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final period in openPeriods)
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : () => onLogPeriod(period),
                    icon: Icon(_periodIcon(period), size: 18),
                    label: Text(periodLabel(strings, period)),
                  ),
              ],
            ),
          ],
          if (extraCount > 0) ...[
            const SizedBox(height: 8),
            Chip(
              avatar: const Icon(Icons.add_task, size: 17),
              label: Text(
                strings.pick(
                  '$extraCount extra recorded',
                  '$extraCount zusätzlich erfasst',
                ),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy ? null : onLogExtra,
                icon: const Icon(Icons.add),
                label: Text(strings.pick('Log extra', 'Extra loggen')),
              ),
              PopupMenuButton<_YourDayMenuAction>(
                enabled: onAnalyze != null,
                tooltip: strings.pick(
                  'More day actions',
                  'Weitere Tagesaktionen',
                ),
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) {
                  if (value == _YourDayMenuAction.analyze) onAnalyze?.call();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _YourDayMenuAction.analyze,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.auto_awesome),
                      title: Text(
                        strings.pick('Analyze day', 'Tag analysieren'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.self_improvement_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.pick('Daily check-in', 'Täglicher Check-in'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (entries.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 17, color: colors.primary),
                    const SizedBox(width: 4),
                    Text(
                      strings.pick('Done', 'Erledigt'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            entries.isEmpty
                ? strings.pick(
                    'Record symptoms and selected tags once a day to build '
                        'up trends and correlations.',
                    'Erfasse Symptome und ausgewählte Tags einmal täglich, '
                        'um Trends und Korrelationen aufzubauen.',
                  )
                : _savedCheckInSummary(
                    strings,
                    symptomCount: symptomCount,
                    tagCount: tagCount,
                  ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final event in entries.take(4))
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(event.label),
                  ),
                if (entries.length > 4)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('+${entries.length - 4}'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onOpenCheckIn,
              icon: const Icon(Icons.edit_note_outlined),
              label: Text(
                entries.isEmpty
                    ? strings.pick('Check in', 'Check-in')
                    : strings.pick('Edit check-in', 'Check-in bearbeiten'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DailyCheckInSummary {
  const _DailyCheckInSummary({required this.kind, required this.label});

  final EventKind kind;
  final String label;
}

List<_DailyCheckInSummary> _dailyCheckInSummaries(
  AppController controller,
  DateTime day,
  AppLocalizations strings,
) {
  final definitionsById = {
    for (final definition in controller.eventDefinitions)
      definition.id: definition,
  };
  final grouped = <String, List<HealthEvent>>{};
  for (final event in controller.events.where(
    (item) =>
        !item.deleted &&
        _YourDayCard._sameDay(item.observedAt, day) &&
        (item.kind == EventKind.symptom ||
            (definitionsById[item.definitionId]?.includeInCheckIn ?? false)),
  )) {
    final key =
        event.definitionId ??
        '${event.kind.name}:${event.name.trim().toLowerCase()}';
    grouped.putIfAbsent(key, () => []).add(event);
  }

  final result = <_DailyCheckInSummary>[];
  for (final entry in grouped.entries) {
    final events = entry.value
      ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    final latest = events.last;
    final definition = definitionsById[latest.definitionId];
    if (latest.kind == EventKind.symptom) {
      final score = latest.score ?? latest.numericValue?.round();
      final scoreLabel = score == null
          ? latest.name
          : score > 5
          ? strings.pick(
              '${latest.name} $score/10 (legacy)',
              '${latest.name} $score/10 (alt)',
            )
          : '${latest.name} $score/5';
      result.add(
        _DailyCheckInSummary(kind: EventKind.symptom, label: scoreLabel),
      );
      continue;
    }

    final label = switch (definition?.valueMode ?? TagValueMode.occurrence) {
      TagValueMode.occurrence => latest.name,
      TagValueMode.intensity =>
        latest.score == null
            ? latest.name
            : latest.score! > 5
            ? strings.pick(
                '${latest.name} ${latest.score}/10 (legacy)',
                '${latest.name} ${latest.score}/10 (alt)',
              )
            : '${latest.name} ${latest.score}/5',
      TagValueMode.amount => _amountCheckInLabel(strings, definition, events),
    };
    result.add(_DailyCheckInSummary(kind: EventKind.tag, label: label));
  }
  result.sort((a, b) {
    if (a.kind != b.kind) return a.kind == EventKind.symptom ? -1 : 1;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return result;
}

String _amountCheckInLabel(
  AppLocalizations strings,
  HealthEventDefinition? definition,
  List<HealthEvent> events,
) {
  final name = definition?.name ?? events.last.name;
  final unit = definition?.defaultUnit ?? events.last.unit ?? '';
  final total = events.fold<double>(
    0,
    (sum, event) => sum + (event.numericValue ?? 0),
  );
  final parts = <String>[name];
  final portion = definition?.portionAmount;
  final portionLabel = definition?.portionLabel?.trim();
  if (portion != null &&
      portion > 0 &&
      portionLabel != null &&
      portionLabel.isNotEmpty) {
    parts.add(
      '${_formatCheckInNumber(strings, total / portion)}× $portionLabel',
    );
  }
  parts.add('${_formatCheckInNumber(strings, total)} $unit'.trim());
  return parts.join(' · ');
}

String _formatCheckInNumber(AppLocalizations strings, double value) =>
    strings.formatNumber(
      value,
      decimalDigits: value == value.truncateToDouble() ? 0 : 1,
    );

String _savedCheckInSummary(
  AppLocalizations strings, {
  required int symptomCount,
  required int tagCount,
}) {
  if (symptomCount > 0 && tagCount > 0) {
    return strings.pick(
      '$symptomCount symptom score(s) and $tagCount tag(s) saved for this day.',
      '$symptomCount Symptombewertung(en) und $tagCount Tag(s) für diesen Tag gespeichert.',
    );
  }
  if (symptomCount > 0) {
    return strings.pick(
      '$symptomCount symptom score(s) saved for this day.',
      '$symptomCount Symptombewertung(en) für diesen Tag gespeichert.',
    );
  }
  return strings.pick(
    '$tagCount tag(s) saved for this day.',
    '$tagCount Tag(s) für diesen Tag gespeichert.',
  );
}

/// One part of the day, with its scheduled doses and any extra intakes.
class _PeriodBlock extends StatelessWidget {
  const _PeriodBlock({
    required this.period,
    required this.doses,
    required this.extras,
    required this.controller,
    required this.selectedDay,
    required this.viewingToday,
  });

  final DosePeriod period;
  final List<ScheduledDoseStatus> doses;
  final List<SupplementIntake> extras;
  final AppController controller;
  final DateTime selectedDay;
  final bool viewingToday;

  @override
  Widget build(BuildContext context) {
    if (doses.isEmpty && extras.isEmpty) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    final taken = doses.where((item) => item.taken).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TimeBlockHeader(
          icon: _periodIcon(period),
          title: periodLabel(strings, period),
          trailing: strings.doseProgress(taken, doses.length),
        ),
        for (final dose in doses)
          _DoseTile(
            dose: dose,
            controller: controller,
            viewingToday: viewingToday,
          ),
        for (final intake in extras)
          _ExtraIntakeTile(intake: intake, controller: controller),
        if (doses.isNotEmpty && taken == doses.length)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(
              children: [
                Icon(
                  Icons.celebration_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  strings.pick('All recorded.', 'Alles erfasst.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A scheduled dose. Swipe right to record it, swipe left to skip it.
class _DoseTile extends StatelessWidget {
  const _DoseTile({
    required this.dose,
    required this.controller,
    required this.viewingToday,
  });

  final ScheduledDoseStatus dose;
  final AppController controller;
  final bool viewingToday;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final accent = seriesColorFor(
      dose.supplement.name,
      colorMode: controller.colorMode,
    );
    final icon = dose.taken
        ? Icons.check_circle
        : dose.skipped
        ? Icons.do_not_disturb_on
        : dose.missed
        ? Icons.error_outline
        : Icons.schedule;
    final statusColor = dose.taken
        ? colors.primary
        : dose.skipped
        ? colors.outline
        : dose.missed
        ? colors.error
        : colors.secondary;

    final tile = SurfaceCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: dose.intake != null || controller.busy
          ? null
          : () => _record(context, skipped: false),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: accent.withValues(alpha: 0.16),
            child: Icon(icon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose.supplement.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    formatAmountWithUnit(
                      strings,
                      amount: dose.schedule.dose,
                      unit: dose.schedule.unit,
                      form: dose.supplement.form,
                    ),
                    dose.schedule.timeOfDay,
                    if (dose.schedule.instructions.isNotEmpty)
                      dose.schedule.instructions,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (dose.intake != null)
            IconButton(
              tooltip: strings.undoCheckIn,
              onPressed: controller.busy
                  ? null
                  : () => _undo(context, dose.intake!),
              icon: const Icon(Icons.undo),
            )
          else
            Wrap(
              spacing: 2,
              children: [
                IconButton.outlined(
                  tooltip: strings.skipDose,
                  onPressed: controller.busy
                      ? null
                      : () => _record(context, skipped: true),
                  icon: const Icon(Icons.close),
                ),
                IconButton.filled(
                  tooltip: strings.markTaken,
                  onPressed: controller.busy
                      ? null
                      : () => _record(context, skipped: false),
                  icon: const Icon(Icons.check),
                ),
              ],
            ),
        ],
      ),
    );

    if (dose.intake != null) return tile;
    return Dismissible(
      key: ValueKey('dose-${dose.schedule.id}-${dose.dueAt.toIso8601String()}'),
      // Recording is the action, not removal: the tile is rebuilt from state,
      // so the dismissal itself is always vetoed.
      confirmDismiss: (direction) async {
        await _record(
          context,
          skipped: direction == DismissDirection.endToStart,
        );
        return false;
      },
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: colors.primary,
        icon: Icons.check,
        label: strings.markTaken,
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: colors.outline,
        icon: Icons.do_not_disturb_on,
        label: strings.skipDose,
      ),
      child: tile,
    );
  }

  Future<void> _record(BuildContext context, {required bool skipped}) async {
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    try {
      await controller.logIntake(
        supplement: dose.supplement,
        dose: dose.schedule.dose,
        unit: dose.schedule.unit,
        takenAt: viewingToday ? DateTime.now() : dose.dueAt,
        schedule: dose.schedule,
        skipped: skipped,
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
          skipped
              ? strings.pick(
                  '${dose.supplement.name} skipped.',
                  '${dose.supplement.name} übersprungen.',
                )
              : strings.pick(
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

/// An intake that no schedule accounts for, shown so a manual log never
/// disappears from the day it belongs to.
class _ExtraIntakeTile extends StatelessWidget {
  const _ExtraIntakeTile({required this.intake, required this.controller});

  final SupplementIntake intake;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final supplement = controller.supplements.firstWhereOrNull(
      (item) => item.id == intake.supplementId,
    );
    return SurfaceCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onTap: supplement == null
          ? null
          : () => showLogIntakeDialog(
              context,
              controller,
              supplement,
              existing: intake,
            ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors.secondaryContainer,
            child: Icon(
              intake.skipped ? Icons.do_not_disturb_on : Icons.add_task,
              size: 20,
              color: colors.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplement?.name ?? strings.deletedSupplement,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatAmountWithUnit(strings, amount: intake.dose, unit: intake.unit, form: supplement?.form)} · '
                  '${strings.formatTime(intake.takenAt)} · '
                  '${strings.pick('unplanned', 'ungeplant')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: strings.delete,
            onPressed: controller.busy
                ? null
                : () => controller.deleteIntake(intake),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.symmetric(horizontal: 22),
    alignment: alignment,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(AppRadius.large),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color)),
      ],
    ),
  );
}

/// The follow-up list: doses still open, biomarkers due, and stock running out.
class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({
    required this.controller,
    required this.doses,
    required this.navigation,
  });

  final AppController controller;
  final List<ScheduledDoseStatus> doses;
  final ShellNavigation navigation;

  @override
  Widget build(BuildContext context) {
    const insights = SupplementInsights();
    final strings = AppLocalizations.of(context);
    final lowStock = insights
        .stockProjections(
          supplements: controller.supplements,
          householdSchedules: controller.householdSchedules,
          stockLevels: controller.stockLevels,
        )
        .where((item) => item.low)
        .toList();
    if (controller.dueBiomarkers.isEmpty && lowStock.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: strings.needsAttention,
          subtitle: strings.needsAttentionDescription,
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final due in controller.dueBiomarkers.take(3))
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: Text(strings.due(due.biomarker.displayName)),
                  subtitle: Text(
                    [
                      listMembershipLabel(strings, due.listNames),
                      due.lastMeasuredAt == null
                          ? strings.neverMeasured
                          : strings.daysOverdue(due.daysOverdue),
                    ].join(' · '),
                  ),
                  onTap: () => navigation.go(
                    AppSection.biomarkers,
                    filter: SectionFilter.dueBiomarkers,
                  ),
                ),
              for (final item in lowStock.take(3))
                ListTile(
                  leading: Icon(
                    Icons.inventory_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(strings.low(item.supplement.name)),
                  subtitle: Text(
                    strings.remaining(
                      item.unitsOnHand,
                      unitLabel(
                        strings,
                        unit: item.supplement.stockUnit,
                        form: item.supplement.form,
                      ),
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () => showAdjustStockDialog(
                      context,
                      controller,
                      item.supplement,
                      purchase: true,
                    ),
                    child: Text(strings.refill),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The label used for a part of the day across Today and the weekly plan.
String periodLabel(AppLocalizations strings, DosePeriod period) =>
    switch (period) {
      DosePeriod.morning => strings.pick('Morning', 'Morgen'),
      DosePeriod.midday => strings.pick('Midday', 'Mittag'),
      DosePeriod.evening => strings.pick('Evening', 'Abend'),
      DosePeriod.bedtime => strings.pick('Bedtime', 'Nacht'),
    };

IconData _periodIcon(DosePeriod period) => switch (period) {
  DosePeriod.morning => Icons.wb_twilight,
  DosePeriod.midday => Icons.wb_sunny_outlined,
  DosePeriod.evening => Icons.wb_incandescent_outlined,
  DosePeriod.bedtime => Icons.bedtime_outlined,
};

/// The one card easy mode leads with: a lab report in, and a question about it
/// out. Both halves are one tap from Today rather than four navigations deep.
class _LabReportCard extends StatelessWidget {
  const _LabReportCard({required this.controller, required this.navigation});

  final AppController controller;
  final ShellNavigation navigation;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final service = BiomarkerStatusService();
    final profile = controller.activeProfile;
    final latest = <String, Measurement>{};
    for (final measurement in controller.measurements) {
      final existing = latest[measurement.biomarkerId];
      if (existing == null || measurement.takenAt.isAfter(existing.takenAt)) {
        latest[measurement.biomarkerId] = measurement;
      }
    }
    final now = DateTime.now();
    // Only markers with a result: an unmeasured one has no status to report,
    // and counting it would make the catalog look like unfinished work.
    final attention = profile == null
        ? const <Biomarker>[]
        : controller.biomarkers.where((item) {
            if (!latest.containsKey(item.id)) return false;
            final status = service.evaluate(
              biomarker: item,
              measurement: latest[item.id],
              profile: profile,
              targets: controller.profileTargets,
              referenceRanges: controller.biomarkerRanges,
              now: now,
            );
            return status.isBelow || status.isAbove;
          }).toList();

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.pick('Your lab results', 'Deine Laborwerte'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              latest.isEmpty
                  ? strings.pick(
                      'Add a lab report and every value is read out for you.',
                      'Füge einen Laborbericht hinzu — alle Werte werden für dich ausgelesen.',
                    )
                  : attention.isEmpty
                  ? strings.pick(
                      'All ${latest.length} recorded values are in their normal range.',
                      'Alle ${latest.length} erfassten Werte liegen im Normalbereich.',
                    )
                  : strings.pick(
                      '${attention.length} of ${latest.length} values are outside their normal range.',
                      '${attention.length} von ${latest.length} Werten liegen außerhalb des Normalbereichs.',
                    ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => navigation.go(AppSection.labs),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: Text(
                    strings.pick('Add a lab report', 'Laborbericht hinzufügen'),
                  ),
                ),
                if (latest.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => navigation.askAdvisor(
                      strings.pick(
                        'Please explain my latest lab results in plain language, '
                            'and tell me what to do about anything outside its range.',
                        'Bitte erkläre meine neuesten Laborwerte in einfacher Sprache '
                            'und sage mir, was ich bei Werten außerhalb des Bereichs tun soll.',
                      ),
                    ),
                    icon: const Icon(Icons.forum_outlined),
                    label: Text(
                      strings.pick(
                        'Ask about my results',
                        'Zu meinen Werten fragen',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
