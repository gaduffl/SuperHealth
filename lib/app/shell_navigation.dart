import 'package:flutter/foundation.dart';

/// The destinations the app shell can be driven to from anywhere in the UI.
///
/// The Today overview's summary tiles are shortcuts, so they need a way to open
/// the screen that owns the number they show — and, where it matters, to arrive
/// with the right filter already applied.
enum AppSection {
  todayDoses,
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
/// The day's doses live on the Today screen itself, so that section stays on
/// tab 0 rather than duplicating the workflow inside the supplements screen.
int tabIndexForSection(AppSection section) => switch (section) {
  AppSection.todayDoses => 0,
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
