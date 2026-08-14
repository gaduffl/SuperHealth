import 'package:flutter/foundation.dart';

/// The destinations the app shell can be driven to from anywhere in the UI.
///
/// The Today overview's summary tiles are shortcuts, so they need a way to open
/// the screen that owns the number they show — and, where it matters, to arrive
/// with the right filter already applied.
enum AppSection {
  catalog,
  weeklyPlan,
  stock,
  intakeHistory,
  journal,
  biomarkers,
  labs,
  healthContext,
  advisor,
  settings,
}

/// Optional pre-filters a destination can honour on arrival.
enum SectionFilter {
  /// Stock list scrolled to, and limited to, the products running low.
  lowStock,

  /// Biomarker view limited to the markers that are due or overdue.
  dueBiomarkers,

  /// Biomarker view limited to the latest results below their target.
  belowTarget,

  /// Biomarker view limited to the latest results above their target.
  aboveTarget,

  /// Biomarker view limited to markers with no usable range or no measurement.
  withoutUsableRange,
}

/// Which shell tab owns a section.
///
/// There is no entry for the day's doses: they live on the Today screen that
/// hosts the shortcuts, so that tile scrolls the page rather than navigating.
int tabIndexForSection(AppSection section) => switch (section) {
  AppSection.catalog ||
  AppSection.weeklyPlan ||
  AppSection.stock ||
  AppSection.intakeHistory => 1,
  AppSection.journal ||
  AppSection.biomarkers ||
  AppSection.labs ||
  AppSection.healthContext => 2,
  AppSection.advisor => 3,
  AppSection.settings => 4,
};

/// The destinations a mode puts in the bottom bar, as canonical tab indices.
///
/// Easy mode drops the supplements tab. Setting products up is something a
/// person does a few times a year, so it does not need a permanent seat beside
/// the daily loop; its entry point moves to a button on the calm home.
///
/// The indices stay canonical in both modes, which is the point of returning
/// them rather than a second numbering: [tabIndexForSection] and every deep
/// link that drives it keep meaning exactly one thing, and only the bar is
/// shorter.
List<int> shellTabsFor({required bool easyMode}) =>
    easyMode ? const [0, 2, 3, 4] : const [0, 1, 2, 3, 4];

/// Which tab inside the supplements screen owns a section.
int? supplementsTabForSection(AppSection section) => switch (section) {
  AppSection.catalog => 0,
  AppSection.weeklyPlan => 1,
  AppSection.stock => 2,
  AppSection.intakeHistory => 3,
  _ => null,
};

/// Which tab inside the health screen owns a section.
int? healthTabForSection(AppSection section) => switch (section) {
  AppSection.journal => 0,
  AppSection.biomarkers || AppSection.labs => 1,
  AppSection.healthContext => 2,
  _ => null,
};

/// A single pending "open this section" request.
@immutable
class SectionRequest {
  const SectionRequest({
    required this.section,
    required this.token,
    this.filter,
    this.prompt,
  });

  final AppSection section;
  final SectionFilter? filter;

  /// A question to hand to the advisor, set when a shortcut wants the advisor
  /// to answer something specific rather than just opening the screen.
  final String? prompt;

  /// Increments on every request so a screen can tell a repeated tap on the
  /// same tile apart from the request it already handled.
  final int token;
}

/// Routes deep links from summary tiles to the screen that owns them.
class ShellNavigation extends ChangeNotifier {
  var _tabIndex = 0;
  SectionRequest? _request;
  var _nextToken = 1;

  int get tabIndex => _tabIndex;
  SectionRequest? get request => _request;

  /// Switches the bottom navigation tab without issuing a section request.
  void selectTab(int index) {
    if (_tabIndex == index) return;
    _tabIndex = index;
    notifyListeners();
  }

  /// Opens [section], switching the shell tab and asking the owning screen to
  /// select its own sub-tab and apply [filter].
  void go(AppSection section, {SectionFilter? filter, String? prompt}) {
    _tabIndex = tabIndexForSection(section);
    _request = SectionRequest(
      section: section,
      filter: filter,
      prompt: prompt,
      token: _nextToken++,
    );
    notifyListeners();
  }

  /// Opens the advisor with [question] already asked.
  void askAdvisor(String question) => go(AppSection.advisor, prompt: question);

  /// Marks the current request as handled so it is not replayed on rebuild.
  void completeRequest(int token) {
    if (_request?.token != token) return;
    _request = null;
  }
}
