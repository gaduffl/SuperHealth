/// What a profile can see, decided in one place.
///
/// Easy mode is not "the same app with fewer buttons" — it is a smaller app
/// aimed at one loop: take today's doses, import a lab report, ask what the
/// results mean. Everything that exists to *analyse* rather than to *do* is
/// hidden, because an empty analysis screen teaches nothing and a full one
/// asks for data the owner has not agreed to keep.
///
/// Screens ask a named question here rather than testing `easyMode` inline.
/// Scattered checks drift: one screen hides a tab, another leaves its entry
/// point, and the mode ends up meaning something different in each corner.
class FeatureVisibility {
  const FeatureVisibility({
    required this.supplementHistory,
    required this.stockManagement,
    required this.supplementIngredients,
    required this.symptomsAndTags,
    required this.trendsAndCorrelations,
    required this.doseUnderlay,
    required this.biomarkerCatalogAdmin,
    required this.labPlanTiers,
    required this.referenceRangeEditing,
    required this.multipleAiRoles,
    required this.maintenanceTools,
    required this.deviceBackup,
    required this.pastDayEditing,
    required this.remindersOnByDefault,
    required this.calmShell,
    required this.briefAnswers,
  });

  /// The full app: every screen, every setting.
  const FeatureVisibility.complete()
    : supplementHistory = true,
      stockManagement = true,
      supplementIngredients = true,
      symptomsAndTags = true,
      trendsAndCorrelations = true,
      doseUnderlay = true,
      biomarkerCatalogAdmin = true,
      labPlanTiers = true,
      referenceRangeEditing = true,
      multipleAiRoles = true,
      maintenanceTools = true,
      deviceBackup = true,
      pastDayEditing = true,
      remindersOnByDefault = false,
      calmShell = false,
      briefAnswers = false;

  /// The simplified app.
  const FeatureVisibility.easy()
    : supplementHistory = false,
      stockManagement = false,
      supplementIngredients = false,
      symptomsAndTags = false,
      // Correlations are computed from tags. With tags hidden there is nothing
      // to correlate, so the screen would be permanently empty.
      trendsAndCorrelations = false,
      // Needs ingredient amounts, which are not collected here.
      doseUnderlay = false,
      biomarkerCatalogAdmin = false,
      labPlanTiers = false,
      referenceRangeEditing = false,
      multipleAiRoles = false,
      maintenanceTools = false,
      // Device-wide, covering every profile: it belongs to whoever set the
      // device up, not to each person on it.
      deviceBackup = false,
      pastDayEditing = false,
      // The one thing easy mode turns *on*. A reminder that defaults to off is
      // why a schedule produces nothing, and hiding the switch instead of
      // setting it would remove the feature's whole point.
      remindersOnByDefault = true,
      calmShell = true,
      briefAnswers = true;

  factory FeatureVisibility.forProfile({required bool easyMode}) => easyMode
      ? const FeatureVisibility.easy()
      : const FeatureVisibility.complete();

  final bool supplementHistory;
  final bool stockManagement;
  final bool supplementIngredients;
  final bool symptomsAndTags;
  final bool trendsAndCorrelations;
  final bool doseUnderlay;
  final bool biomarkerCatalogAdmin;
  final bool labPlanTiers;
  final bool referenceRangeEditing;
  final bool multipleAiRoles;

  /// Unit clean-up, sync conflict resolution, token counts.
  final bool maintenanceTools;

  final bool deviceBackup;

  /// Whether days other than today can be reviewed and filled in.
  final bool pastDayEditing;

  final bool remindersOnByDefault;

  /// Whether the shell is reduced to the few things this profile actually does.
  ///
  /// Hiding sub-tabs made the screens smaller but left the app the same shape:
  /// five dense destinations, a wall of tiles on the one that opens first. This
  /// is the other half — a calm home with a handful of large targets, a shorter
  /// bottom bar, and a soft surface — for someone who wants to take today's
  /// doses and ask a question, not to run a health project.
  final bool calmShell;

  /// Whether the AI is asked for the shortest answer that is still true.
  ///
  /// Length is not thoroughness. The model still reads the complete evidence
  /// package and still names a real risk; it just stops narrating its process
  /// and stops reprinting the disclaimer the app already carries under every
  /// answer. For this profile it also drops the jargon.
  final bool briefAnswers;

  /// Whether the Today screen leads with the lab-report shortcut.
  ///
  /// Hiding screens makes the app smaller, not easier. The loop that matters —
  /// report in, status out, question answered — is four navigations deep in the
  /// full app, and easy mode exists to make it one.
  bool get leadWithLabReport => !biomarkerCatalogAdmin;
}
