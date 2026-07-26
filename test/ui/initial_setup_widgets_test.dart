import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/app/initial_setup_progress.dart';
import 'package:super_health/ui/initial_setup_widgets.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [AppLocalizations.delegate],
    home: Scaffold(body: child),
  );

  testWidgets('setup checklist disables imports until a profile exists', (
    tester,
  ) async {
    var skippedJson = 0;
    await tester.pumpWidget(
      app(
        InitialSetupChecklistCard(
          progress: const InitialSetupProgress.empty(),
          onCreateProfile: () {},
          onImportJson: () async {},
          onSkipJson: () async {
            skippedJson++;
          },
          onAttachPdfs: () async {},
          onSkipPdfs: () async {},
          onSetUpCloud: () async {},
          onSkipCloud: () async {},
          onSetUpAdvisor: () {},
          onSkipAdvisor: () async {},
        ),
      ),
    );

    final importButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Import'),
    );
    final attachButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Attach'),
    );
    expect(importButton.onPressed, isNull);
    expect(attachButton.onPressed, isNull);

    await tester.tap(find.widgetWithText(TextButton, 'Skip for now').first);
    await tester.pump();
    expect(skippedJson, 1);
  });

  testWidgets('dashboard setup prompt can be dismissed without changing data', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      app(DashboardSetupPrompt(onOpenSettings: () => opened++)),
    );

    await tester.tap(find.text('Settings'));
    expect(opened, 1);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Finish setting up SuperHealth'), findsNothing);
  });

  testWidgets('German setup actions fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: SingleChildScrollView(
            child: InitialSetupChecklistCard(
              progress: const InitialSetupProgress.empty(),
              onCreateProfile: () {},
              onImportJson: () async {},
              onSkipJson: () async {},
              onAttachPdfs: () async {},
              onSkipPdfs: () async {},
              onSetUpCloud: () async {},
              onSkipCloud: () async {},
              onSetUpAdvisor: () {},
              onSkipAdvisor: () async {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Vorerst überspringen'), findsWidgets);
  });

  test('new setup translations remain complete in English and German', () {
    expect(AppLocalizations.translationsComplete, isTrue);
    expect(
      AppLocalizations.forLocale(const Locale('de')).restoreSyncDecisionTitle,
      isNotEmpty,
    );
  });
}
