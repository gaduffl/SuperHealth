import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../biomarkers/biomarker_status_service.dart';
import '../biomarkers/unit_conversion_service.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'dialogs.dart';
import 'reference_range_tools.dart';

String _detailText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

String _detailStatusLabel(BuildContext context, BiomarkerStatus status) {
  final german = switch (status.label) {
    'Never measured' => 'Noch nie gemessen',
    'No comparison range' => 'Kein Vergleichsbereich',
    'Unavailable' => 'Nicht verfügbar',
    'Below personal target' => 'Unter persönlichem Zielbereich',
    'Above personal target' => 'Über persönlichem Zielbereich',
    'In personal target' => 'Im persönlichen Zielbereich',
    'In stored optimal band' => 'Im gespeicherten Optimalbereich',
    'Below stored reference' => 'Unter gespeichertem Referenzbereich',
    'Above stored reference' => 'Über gespeichertem Referenzbereich',
    'Within stored reference' => 'Im gespeicherten Referenzbereich',
    'Below stored optimal band' => 'Unter gespeichertem Optimalbereich',
    'Above stored optimal band' => 'Über gespeichertem Optimalbereich',
    'Below lab range' => 'Unter Laborbereich',
    'Above lab range' => 'Über Laborbereich',
    'Within lab range' => 'Im Laborbereich',
    _ => status.label,
  };
  return _detailText(context, status.label, german);
}

String _detailStatusDetail(BuildContext context, BiomarkerStatus status) {
  final german = status.detail
      .replaceAll('No recorded result', 'Kein Ergebnis gespeichert')
      .replaceAll(
        'The reported value or unit cannot be evaluated safely',
        'Der angegebene Wert oder die Einheit kann nicht sicher ausgewertet werden',
      )
      .replaceAll(
        'Result recorded, but no personal target, stored reference, or lab range is available',
        'Ergebnis gespeichert, aber kein persönlicher Ziel-, Referenz- oder Laborbereich verfügbar',
      )
      .replaceAll(
        'A comparison range exists but cannot be evaluated safely',
        'Ein Vergleichsbereich ist vorhanden, kann aber nicht sicher ausgewertet werden',
      )
      .replaceAll('Personal target:', 'Persönlicher Zielbereich:')
      .replaceAll('Borderline:', 'Grenzbereich:')
      .replaceAll('Stored reference:', 'Gespeicherte Referenz:')
      .replaceAll('Stored optimal:', 'Gespeicherter Optimalbereich:')
      .replaceAll('Lab-reported range:', 'Vom Labor angegebener Bereich:');
  return _detailText(context, status.detail, german);
}

Future<void> showBiomarkerDetail(
  BuildContext context,
  Biomarker biomarker,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  // The id, not the object: the sheet re-reads the biomarker on every build so
  // an edit made from inside it is visible the moment it is saved.
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: _BiomarkerDetail(biomarkerId: biomarker.id),
  ),
);

class _BiomarkerDetail extends StatelessWidget {
  const _BiomarkerDetail({required this.biomarkerId});

  /// Identity, never a captured copy.
  ///
  /// This sheet used to hold the `Biomarker` it was opened with and read a
  /// non-listening `AppController`, so it was frozen at open time. Its own
  /// "Edit" action then re-seeded the dialog from that frozen copy: a saved
  /// price was written to the database and immediately disappeared from the
  /// form, which is indistinguishable from the save having failed.
  final String biomarkerId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final biomarker = controller.biomarkers.firstWhereOrNull(
      (item) => item.id == biomarkerId && !item.deleted,
    );
    // Deleted from the sheet's own menu, or from elsewhere while it was open.
    if (biomarker == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final profile = controller.activeProfile!;
    final statusService = BiomarkerStatusService();
    final unitConversions = UnitConversionService();
    final values =
        controller.measurements
            .where((item) => item.biomarkerId == biomarker.id)
            .toList()
          ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    Measurement? trendAnchor;
    for (final value in values.reversed) {
      if (value.canonicalValue?.isFinite == true &&
          value.canonicalUnit?.trim().isNotEmpty == true) {
        trendAnchor = value;
        break;
      }
    }
    final trendUnit = switch (trendAnchor) {
      final anchor? => unitConversions.normalizeUnit(
        anchor.canonicalUnit ?? '',
      ),
      null => null,
    };
    final comparable = trendUnit == null
        ? <Measurement>[]
        : values
              .where((item) {
                final canonicalUnit = item.canonicalUnit?.trim();
                return item.canonicalValue?.isFinite == true &&
                    canonicalUnit != null &&
                    canonicalUnit.isNotEmpty &&
                    unitConversions.normalizeUnit(canonicalUnit) == trendUnit;
              })
              .toList(growable: false);
    final daily = _dailyAverages(comparable);
    final latest = values.isEmpty ? null : values.last;
    final trendLatest = comparable.isEmpty ? null : comparable.last;
    final previousTrend = comparable.length < 2
        ? null
        : comparable[comparable.length - 2];
    final excludedFromTrend = values.length - comparable.length;
    final matchingTargets =
        controller.profileTargets
            .where(
              (candidate) =>
                  !candidate.deleted &&
                  candidate.profileId == profile.id &&
                  candidate.biomarkerId == biomarker.id,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final target = matchingTargets.isEmpty ? null : matchingTargets.first;
    final ranges = controller.biomarkerRanges
        .where((item) => item.biomarkerId == biomarker.id)
        .toList(growable: false);
    final latestStatus = statusService.evaluate(
      biomarker: biomarker,
      measurement: latest,
      profile: profile,
      targets: controller.profileTargets,
      referenceRanges: controller.biomarkerRanges,
      now: now,
    );
    final trendBand = trendUnit == null
        ? null
        : statusService.convertUsedBand(
            status: latestStatus,
            biomarker: biomarker,
            toUnit: trendUnit,
          );
    final hasComparisonBounds =
        latestStatus.usedLow != null || latestStatus.usedHigh != null;
    final comparisonLabel = switch (latestStatus.source) {
      BiomarkerStatusSource.personalTarget => _detailText(
        context,
        'Personal target',
        'Persönliches Ziel',
      ),
      BiomarkerStatusSource.storedReferenceRange =>
        latestStatus.kind == BiomarkerStatusKind.inStoredOptimal
            ? _detailText(
                context,
                'Stored optimal',
                'Gespeicherter Optimalbereich',
              )
            : _detailText(context, 'Stored range', 'Gespeicherter Bereich'),
      BiomarkerStatusSource.labReportedRange => _detailText(
        context,
        'Lab range',
        'Laborbereich',
      ),
      BiomarkerStatusSource.none => _detailText(
        context,
        'Comparison range unavailable',
        'Vergleichsbereich nicht verfügbar',
      ),
    };
    final comparisonValue = hasComparisonBounds
        ? '${latestStatus.usedLow ?? '…'}–${latestStatus.usedHigh ?? '…'}'
        : '—';
    final comparisonDetail =
        hasComparisonBounds && latestStatus.unit?.trim().isNotEmpty == true
        ? latestStatus.unit!
        : _detailText(
            context,
            'No usable comparison bounds',
            'Keine verwendbaren Vergleichsgrenzen',
          );
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      biomarker.displayName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      [
                        if (biomarker.category.isNotEmpty) biomarker.category,
                        if (biomarker.defaultUnit.isNotEmpty)
                          biomarker.defaultUnit,
                        // Shown here because this is where it is edited from,
                        // and a price you cannot see is a price you cannot
                        // tell was saved. It also drives the lab plan tiers.
                        if (biomarker.hasPrice)
                          '${biomarker.priceEur!.toStringAsFixed(2)} €'
                              '${biomarker.labName?.trim().isNotEmpty == true ? ' · ${biomarker.labName!.trim()}' : ''}'
                        else
                          _detailText(context, 'No price', 'Kein Preis'),
                        if (biomarker.isTemporary)
                          _detailText(
                            context,
                            'Temporary mapping',
                            'Temporäre Zuordnung',
                          ),
                      ].join(' · '),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () =>
                    showAddMeasurementDialog(context, controller, biomarker),
                icon: const Icon(Icons.add),
                label: Text(_detailText(context, 'Result', 'Ergebnis')),
              ),
              PopupMenuButton<String>(
                tooltip: _detailText(
                  context,
                  'Biomarker actions',
                  'Biomarkeraktionen',
                ),
                onSelected: (value) async {
                  if (value == 'edit') {
                    await showAddBiomarkerDialog(
                      context,
                      controller,
                      existing: biomarker,
                    );
                  } else if (value == 'target') {
                    await showProfileTargetDialog(
                      context,
                      controller,
                      biomarker,
                      existing: target,
                    );
                  } else if (value == 'delete_target') {
                    final targetToDelete = target;
                    if (targetToDelete != null) {
                      await controller.deleteProfileTarget(targetToDelete);
                    }
                  } else if (value == 'delete') {
                    await controller.deleteBiomarker(biomarker);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(
                      _detailText(context, 'Edit test', 'Test bearbeiten'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'target',
                    child: Text(
                      target == null
                          ? _detailText(context, 'Set target', 'Ziel festlegen')
                          : _detailText(
                              context,
                              'Edit target',
                              'Ziel bearbeiten',
                            ),
                    ),
                  ),
                  if (target != null)
                    PopupMenuItem(
                      value: 'delete_target',
                      child: Text(
                        _detailText(
                          context,
                          'Remove personal target',
                          'Persönliches Ziel entfernen',
                        ),
                      ),
                    ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      _detailText(context, 'Delete test', 'Test löschen'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (biomarker.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                biomarker.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (excludedFromTrend > 0)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(
                  trendUnit == null
                      ? _detailText(
                          context,
                          '$excludedFromTrend result(s) excluded from trends',
                          '$excludedFromTrend Ergebnis(se) aus Trends ausgeschlossen',
                        )
                      : _detailText(
                          context,
                          '$excludedFromTrend result(s) excluded from the $trendUnit trend',
                          '$excludedFromTrend Ergebnis(se) aus dem $trendUnit-Trend ausgeschlossen',
                        ),
                ),
                subtitle: Text(
                  trendUnit == null
                      ? _detailText(
                          context,
                          'No result has both a finite canonical value and a usable canonical unit.',
                          'Kein Ergebnis besitzt sowohl einen endlichen kanonischen Wert als auch eine verwendbare kanonische Einheit.',
                        )
                      : _detailText(
                          context,
                          'Trend and change use only finite canonical values in $trendUnit. Results without one, or in another canonical unit, remain in history.',
                          'Trend und Änderung verwenden nur endliche kanonische Werte in $trendUnit. Andere Ergebnisse bleiben im Verlauf erhalten.',
                        ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: _detailText(context, 'Latest', 'Neuester Wert'),
                  value: latest == null ? '—' : _displayValue(latest),
                  detail: latest == null
                      ? _detailText(context, 'No result', 'Kein Ergebnis')
                      : AppLocalizations.of(
                          context,
                        ).formatHistoryDate(latest.takenAt),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  label: _detailText(context, 'Change', 'Änderung'),
                  value: trendLatest == null
                      ? _detailText(
                          context,
                          'Not comparable',
                          'Nicht vergleichbar',
                        )
                      : previousTrend == null
                      ? '—'
                      : _signed(
                          trendLatest.canonicalValue! -
                              previousTrend.canonicalValue!,
                        ),
                  detail: trendUnit == null
                      ? _detailText(
                          context,
                          'No usable canonical unit',
                          'Keine verwendbare kanonische Einheit',
                        )
                      : previousTrend == null
                      ? _detailText(
                          context,
                          'Need 2 results · $trendUnit',
                          '2 Ergebnisse nötig · $trendUnit',
                        )
                      : trendUnit,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  label: comparisonLabel,
                  value: comparisonValue,
                  detail: comparisonDetail,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Card(
            child: Semantics(
              label:
                  '${_detailText(context, 'Latest status', 'Neuester Status')}: '
                  '${_detailStatusLabel(context, latestStatus)}. '
                  '${_detailStatusDetail(context, latestStatus)}',
              child: ListTile(
                leading: Icon(_statusIcon(latestStatus)),
                title: Text(_detailStatusLabel(context, latestStatus)),
                subtitle: Text(_detailStatusDetail(context, latestStatus)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
              child: daily.length < 2
                  ? SizedBox(
                      height: 180,
                      child: Center(
                        child: Text(
                          trendUnit == null
                              ? _detailText(
                                  context,
                                  'No finite canonical results are available for a trend.',
                                  'Für einen Trend sind keine endlichen kanonischen Ergebnisse verfügbar.',
                                )
                              : comparable.length > 1
                              ? _detailText(
                                  context,
                                  'Comparable results in $trendUnit fall on one calendar day. Add a result on another day to show a trend.',
                                  'Vergleichbare Ergebnisse in $trendUnit liegen am selben Kalendertag. Füge an einem anderen Tag ein Ergebnis hinzu.',
                                )
                              : _detailText(
                                  context,
                                  'Add at least two comparable results in $trendUnit to show a trend.',
                                  'Füge mindestens zwei vergleichbare Ergebnisse in $trendUnit hinzu.',
                                ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            _detailText(
                              context,
                              'Trend unit: $trendUnit',
                              'Trendeinheit: $trendUnit',
                            ),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                        SizedBox(
                          height: 220,
                          child: CustomPaint(
                            painter: _TrendPainter(
                              values: daily,
                              lineColor: Theme.of(context).colorScheme.primary,
                              gridColor: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                              textColor: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              refLow: trendBand?.low,
                              refHigh: trendBand?.high,
                              bandColor: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                            ),
                            size: Size.infinite,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _detailText(
                      context,
                      'Ranges & targets',
                      'Bereiche und Ziele',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: _detailText(
                    context,
                    'Import or export ranges',
                    'Bereiche importieren oder exportieren',
                  ),
                  onPressed: () => showReferenceRangeExchange(
                    context,
                    controller,
                    biomarker,
                  ),
                  icon: const Icon(Icons.import_export_outlined),
                ),
                IconButton(
                  tooltip: _detailText(
                    context,
                    'Add reference range',
                    'Referenzbereich hinzufügen',
                  ),
                  onPressed: () =>
                      showReferenceRangeEditor(context, controller, biomarker),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          if (target != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(
                  '${_detailText(context, 'Personal', 'Persönlich')} · '
                  '${target.low ?? '…'}–${target.high ?? '…'} ${target.unit}',
                ),
                subtitle: Text(
                  [
                    target.source,
                    if (target.notes.isNotEmpty) target.notes,
                  ].join(' · '),
                ),
                onTap: () => showProfileTargetDialog(
                  context,
                  controller,
                  biomarker,
                  existing: target,
                ),
              ),
            ),
          for (final range in ranges)
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(
                  '${range.rangeType} · ${range.low ?? '…'}–${range.high ?? '…'} ${range.unit}',
                ),
                subtitle: Text(
                  [
                    if (range.evidenceLabel?.isNotEmpty == true)
                      range.evidenceLabel!,
                    if (range.optimalLow != null || range.optimalHigh != null)
                      '${_detailText(context, 'Optimal', 'Optimal')} '
                          '${range.optimalLow ?? '…'}–${range.optimalHigh ?? '…'}',
                    if (range.notes.isNotEmpty) range.notes,
                  ].join(' · '),
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: _detailText(
                    context,
                    'Reference range actions',
                    'Aktionen für Referenzbereich',
                  ),
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await showReferenceRangeEditor(
                        context,
                        controller,
                        biomarker,
                        existing: range,
                      );
                    } else if (action == 'delete') {
                      final confirmed = await showConfirmAction(
                        context,
                        title: _detailText(
                          context,
                          'Delete this reference range?',
                          'Diesen Referenzbereich löschen?',
                        ),
                        message: _detailText(
                          context,
                          'The range is kept as a sync tombstone.',
                          'Der Bereich bleibt als Synchronisierungs-Löschmarker erhalten.',
                        ),
                        confirmLabel: _detailText(context, 'Delete', 'Löschen'),
                        destructive: true,
                      );
                      if (confirmed) {
                        await controller.repository.softDelete(
                          'biomarker_ranges',
                          range.id,
                        );
                        await controller.refreshActiveData();
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(_detailText(context, 'Edit', 'Bearbeiten')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(_detailText(context, 'Delete', 'Löschen')),
                    ),
                  ],
                ),
                onTap: () => showReferenceRangeEditor(
                  context,
                  controller,
                  biomarker,
                  existing: range,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
            child: Text(
              _detailText(context, 'History', 'Verlauf'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (values.isEmpty)
            Card(
              child: ListTile(
                title: Text(
                  _detailText(
                    context,
                    'No recorded results',
                    'Keine gespeicherten Ergebnisse',
                  ),
                ),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final value in values.reversed)
                    Builder(
                      builder: (context) {
                        final status = statusService.evaluate(
                          biomarker: biomarker,
                          measurement: value,
                          profile: profile,
                          targets: controller.profileTargets,
                          referenceRanges: controller.biomarkerRanges,
                          now: now,
                        );
                        final document = value.documentId == null
                            ? null
                            : controller.documents.firstWhereOrNull(
                                (item) => item.id == value.documentId,
                              );
                        return ListTile(
                          isThreeLine:
                              value.notes.trim().isNotEmpty ||
                              value.documentId != null,
                          title: Text(_displayValue(value)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  DateFormat(
                                    'dd.MM.yyyy',
                                  ).format(value.takenAt),
                                  if (value.labRefLow != null ||
                                      value.labRefHigh != null)
                                    '${_detailText(context, 'Lab ref', 'Laborreferenz')} '
                                        '${value.labRefLow ?? '…'}–${value.labRefHigh ?? '…'}',
                                  if (value.extractionConfidence != null)
                                    '${_detailText(context, 'Parse', 'Extraktion')} '
                                        '${(value.extractionConfidence! * 100).round()}%',
                                  if (value.conversionStatus == 'unsupported')
                                    _detailText(
                                      context,
                                      'No safe conversion to standard unit',
                                      'Keine sichere Umrechnung in die Standardeinheit',
                                    ),
                                  _detailStatusLabel(context, status),
                                ].join(' · '),
                              ),
                              // Its own line rather than the tail of that
                              // chain: a remark is the reason a reading looks
                              // the way it does, and appended last it was the
                              // first thing an overflowing row dropped.
                              if (value.notes.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    value.notes.trim(),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          fontStyle: FontStyle.italic,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                  ),
                                ),
                              if (value.documentId != null)
                                _SourceDocumentLink(
                                  document: document,
                                  page: value.page,
                                ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: _detailText(
                              context,
                              'Result actions',
                              'Ergebnisaktionen',
                            ),
                            onSelected: (action) async {
                              if (action == 'edit') {
                                await showAddMeasurementDialog(
                                  context,
                                  controller,
                                  biomarker,
                                  existing: value,
                                );
                              } else if (action == 'delete') {
                                await controller.deleteMeasurement(value);
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text(
                                  _detailText(context, 'Edit', 'Bearbeiten'),
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  _detailText(context, 'Delete', 'Löschen'),
                                ),
                              ),
                            ],
                            child: _StatusIndicator(status: status),
                          ),
                          onTap: () => showAddMeasurementDialog(
                            context,
                            controller,
                            biomarker,
                            existing: value,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_DailyValue> _dailyAverages(List<Measurement> values) {
    final grouped = <DateTime, List<double>>{};
    for (final value in values) {
      final day = DateTime(
        value.takenAt.year,
        value.takenAt.month,
        value.takenAt.day,
      );
      grouped.putIfAbsent(day, () => []).add(value.canonicalValue!);
    }
    return grouped.entries
        .map(
          (entry) => _DailyValue(
            entry.key,
            entry.value.reduce((a, b) => a + b) / entry.value.length,
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  String _signed(double value) =>
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}';

  String _displayValue(Measurement value) {
    final raw = '${value.value} ${value.unit}';
    if (value.conversionStatus != 'converted' ||
        value.canonicalValue == null ||
        value.canonicalUnit == null) {
      return raw;
    }
    return '$raw · ${value.canonicalValue!.toStringAsPrecision(5)} ${value.canonicalUnit}';
  }
}

/// The report a reading was extracted from, and a way to open it.
///
/// A parsed number is a claim about a document. Being able to reach that
/// document from the number is what makes the claim checkable — otherwise
/// verifying one surprising value means hunting through the report list by
/// date and hoping.
class _SourceDocumentLink extends StatelessWidget {
  const _SourceDocumentLink({required this.document, this.page});

  final HealthDocument? document;

  /// The page the value was read from, when the parser recorded one.
  final int? page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = document;
    // The measurement names a document the catalog no longer has. Saying so
    // is better than a link that goes nowhere.
    if (source == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          _detailText(
            context,
            'Source report is no longer available',
            'Quellbericht ist nicht mehr verfügbar',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final label = [
      source.fileName,
      if (page != null) _detailText(context, 'page $page', 'Seite $page'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: () => _open(context, source),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 15,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hands the file to the system so it opens in a PDF viewer.
  ///
  /// A report that exists only in OneDrive has no local file to open yet, and
  /// the honest answer there is to say which sync brings it back rather than
  /// to fail silently.
  Future<void> _open(BuildContext context, HealthDocument source) async {
    final path = source.localPath?.trim() ?? '';
    if (path.isEmpty || !File(path).existsSync()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            source.oneDriveItemId == null
                ? _detailText(
                    context,
                    'The PDF for ${source.fileName} is not stored on this device.',
                    'Die PDF-Datei für ${source.fileName} liegt nicht auf diesem Gerät.',
                  )
                : _detailText(
                    context,
                    '${source.fileName} is in OneDrive and arrives with the next sync.',
                    '${source.fileName} liegt in OneDrive und kommt mit der nächsten Synchronisierung.',
                  ),
          ),
        ),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: source.mimeType)],
        subject: source.fileName,
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.detail});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});

  final BiomarkerStatus status;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Status: ${_detailStatusLabel(context, status)}. '
        '${_detailStatusDetail(context, status)}',
    child: Icon(_statusIcon(status), size: 18),
  );
}

IconData _statusIcon(BiomarkerStatus status) => switch (status.kind) {
  BiomarkerStatusKind.below => Icons.arrow_downward_outlined,
  BiomarkerStatusKind.above => Icons.arrow_upward_outlined,
  BiomarkerStatusKind.inPersonalTarget ||
  BiomarkerStatusKind.inStoredOptimal => Icons.track_changes_outlined,
  BiomarkerStatusKind.withinStoredReference ||
  BiomarkerStatusKind.withinLabRange => Icons.check_circle_outline,
  BiomarkerStatusKind.neverMeasured => Icons.remove_circle_outline,
  BiomarkerStatusKind.noComparisonRange => Icons.rule_folder_outlined,
  BiomarkerStatusKind.unavailable => Icons.help_outline,
};

class _DailyValue {
  const _DailyValue(this.date, this.value);

  final DateTime date;
  final double value;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.textColor,
    required this.bandColor,
    this.refLow,
    this.refHigh,
  });

  final List<_DailyValue> values;
  final Color lineColor;
  final Color gridColor;
  final Color textColor;
  final Color bandColor;
  final double? refLow;
  final double? refHigh;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 46.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 28.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    var minY = values.map((item) => item.value).reduce(math.min);
    var maxY = values.map((item) => item.value).reduce(math.max);
    if (refLow != null) minY = math.min(minY, refLow!);
    if (refHigh != null) maxY = math.max(maxY, refHigh!);
    final padding = (maxY - minY).abs() * 0.12;
    minY -= padding == 0 ? 1 : padding;
    maxY += padding == 0 ? 1 : padding;

    double y(double value) =>
        chart.bottom - ((value - minY) / (maxY - minY)) * chart.height;
    double x(int index) =>
        chart.left + index / (values.length - 1) * chart.width;

    if (refLow != null || refHigh != null) {
      final bandTop = y(refHigh ?? maxY).clamp(chart.top, chart.bottom);
      final bandBottom = y(refLow ?? minY).clamp(chart.top, chart.bottom);
      canvas.drawRect(
        Rect.fromLTRB(chart.left, bandTop, chart.right, bandBottom),
        Paint()..color = bandColor.withValues(alpha: 0.45),
      );
    }
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final gridY = chart.top + chart.height * index / 4;
      canvas.drawLine(
        Offset(chart.left, gridY),
        Offset(chart.right, gridY),
        gridPaint,
      );
      final label = (maxY - (maxY - minY) * index / 4).toStringAsFixed(1);
      _text(canvas, label, Offset(0, gridY - 6), 10);
    }

    final path = Path()..moveTo(x(0), y(values.first.value));
    for (var index = 1; index < values.length; index++) {
      path.lineTo(x(index), y(values[index].value));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var index = 0; index < values.length; index++) {
      canvas.drawCircle(
        Offset(x(index), y(values[index].value)),
        4,
        Paint()..color = lineColor,
      );
    }
    _text(
      canvas,
      DateFormat('MM/yy').format(values.first.date),
      Offset(chart.left, chart.bottom + 7),
      10,
    );
    final lastLabel = DateFormat('MM/yy').format(values.last.date);
    final painter = TextPainter(
      text: TextSpan(
        text: lastLabel,
        style: TextStyle(color: textColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(chart.right - painter.width, chart.bottom + 7),
    );
  }

  void _text(Canvas canvas, String value, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: textColor, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.refLow != refLow ||
      oldDelegate.refHigh != refHigh;
}
