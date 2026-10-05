import '../domain/entities.dart';

/// The whole active-profile record, parsed once per advisor turn.
///
/// Built from `completeProfileSnapshot(scope: agent)` — serialized rows, not a
/// database handle — so the advisor's tools stay inside the rule that the AI
/// layer holds data and never a connection. It lives on the device: the
/// digest summarises it and tools return slices of it, and it is never sent
/// as a whole.
class AgentSnapshot {
  AgentSnapshot._({
    required this.profileId,
    required this.profile,
    required this.supplements,
    required this.schedules,
    required this.intakes,
    required this.events,
    required this.documents,
    required this.measurements,
    required this.biomarkers,
    required this.ranges,
    required this.records,
    required this.targets,
    required this.lists,
    required this.labPlans,
    required this.labPlanItems,
    required this.labPackageOffers,
  });

  factory AgentSnapshot.fromSnapshot(
    Map<String, Object?> source, {
    required String profileId,
  }) {
    if (source['active_profile_id'] != profileId) {
      throw StateError('Health context returned the wrong active profile.');
    }
    final data = source['data'];
    if (data is! Map) {
      throw StateError('Repository returned no health data map.');
    }
    List<Map<String, Object?>> rows(String section) {
      final value = data[section];
      if (value is! List) return const [];
      return [
        for (final row in value)
          if (row is Map) Map<String, Object?>.from(row),
      ];
    }

    final profileRow = data['profile'];
    if (profileRow is! Map) throw StateError('Active profile not found.');
    final listItems = [
      for (final row in rows('biomarker_list_items'))
        BiomarkerListItem.fromMap(row),
    ];
    return AgentSnapshot._(
      profileId: profileId,
      profile: Profile.fromMap(Map<String, Object?>.from(profileRow)),
      supplements: [
        for (final row in rows('supplements')) Supplement.fromMap(row),
      ],
      schedules: [
        for (final row in rows('supplement_schedules'))
          SupplementSchedule.fromMap(row),
      ],
      intakes: [
        for (final row in rows('supplement_intakes'))
          SupplementIntake.fromMap(row),
      ],
      events: [
        for (final row in rows('health_events')) HealthEvent.fromMap(row),
      ],
      documents: [
        for (final row in rows('documents')) HealthDocument.fromMap(row),
      ],
      measurements: [
        for (final row in rows('measurements')) Measurement.fromMap(row),
        for (final row in rows('calculated_measurements'))
          Measurement.fromMap(row),
      ],
      biomarkers: [
        for (final row in rows('biomarker_catalog')) Biomarker.fromMap(row),
      ],
      ranges: [
        for (final row in rows('biomarker_ranges'))
          BiomarkerReferenceRange.fromMap(row),
      ],
      records: [
        for (final row in rows('conditions_medications_goals_history'))
          NamedHealthRecord.fromMap(row),
      ],
      targets: [
        for (final row in rows('profile_biomarker_targets'))
          ProfileBiomarkerTarget.fromMap(row),
      ],
      lists: [
        for (final row in rows('biomarker_lists'))
          BiomarkerList.fromMap(row, [
            for (final item in listItems)
              if (item.listId == row['id']) item,
          ]),
      ],
      labPlans: rows('lab_plans'),
      labPlanItems: rows('lab_plan_items'),
      labPackageOffers: rows('lab_package_offers'),
    );
  }

  final String profileId;
  final Profile profile;
  final List<Supplement> supplements;
  final List<SupplementSchedule> schedules;
  final List<SupplementIntake> intakes;
  final List<HealthEvent> events;
  final List<HealthDocument> documents;

  /// Reported and calculated measurements together; a calculated row says so
  /// in its conversion status.
  final List<Measurement> measurements;

  /// The whole catalog, including markers never measured.
  final List<Biomarker> biomarkers;
  final List<BiomarkerReferenceRange> ranges;
  final List<NamedHealthRecord> records;
  final List<ProfileBiomarkerTarget> targets;
  final List<BiomarkerList> lists;
  final List<Map<String, Object?>> labPlans;
  final List<Map<String, Object?>> labPlanItems;
  final List<Map<String, Object?>> labPackageOffers;

  late final Map<String, Biomarker> biomarkersById = {
    for (final item in biomarkers) item.id: item,
  };

  late final Map<String, Supplement> supplementsById = {
    for (final item in supplements) item.id: item,
  };

  late final Map<String, HealthDocument> documentsById = {
    for (final item in documents) item.id: item,
  };
}
