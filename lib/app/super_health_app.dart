import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../ui/advisor_screen.dart';
import '../ui/blossom_background.dart';
import '../ui/calm_home_screen.dart';
import '../ui/common.dart';
import '../ui/dashboard_screen.dart';
import '../ui/dialogs.dart';
import '../ui/health_screen.dart';
import '../ui/design.dart';
import '../ui/settings_screen.dart';
import '../ui/stock_overview_panel.dart';
import '../ui/tracking_screen.dart';
import 'app_controller.dart';
import 'app_localizations.dart';
import 'app_theme.dart';
import 'shell_navigation.dart';

class SuperHealthApp extends StatelessWidget {
  const SuperHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final appearance = controller.appearanceSettings;
    // Read from the profile rather than a device setting: two people share one
    // device, and the calm look belongs to whoever is signed in, not to the
    // phone. Switching profiles therefore rebuilds both themes.
    final calm = controller.visibility.calmShell;
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      locale: appearance.language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: appearance.themeMode.materialThemeMode,
      theme: buildAppTheme(
        brightness: Brightness.light,
        settings: appearance,
        calm: calm,
      ),
      darkTheme: buildAppTheme(
        brightness: Brightness.dark,
        settings: appearance,
        calm: calm,
      ),
      builder: calm
          ? (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: calmTextScaler(media.textScaler),
                ),
                child: child!,
              );
            }
          : null,
      home: const _AppGate(),
    );
  }
}

class _AppGate extends StatelessWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final strings = AppLocalizations.of(context);
    if (!controller.initialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppMark(size: 92),
              const SizedBox(height: 24),
              const SizedBox(
                width: 120,
                child: LinearProgressIndicator(minHeight: 3),
              ),
              const SizedBox(height: 14),
              Text(strings.openingRecord),
            ],
          ),
        ),
      );
    }
    if (controller.initializationError case final error?) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyState(
                icon: Icons.error_outline,
                title: strings.couldNotStart,
                message: error,
              ),
            ),
          ),
        ),
      );
    }
    if (controller.activeProfile == null) return const _ProfileOnboarding();
    return const _HomeShell();
  }
}

class _ProfileOnboarding extends StatelessWidget {
  const _ProfileOnboarding();

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  const AppMark(size: 104),
                  const SizedBox(height: 24),
                  Text(
                    strings.welcome,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    strings.onboardingDescription,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: Icon(Icons.people_outline),
                          title: Text(strings.isolatedProfiles),
                          subtitle: Text(strings.isolatedProfilesDescription),
                        ),
                        Divider(height: 1),
                        ListTile(
                          leading: Icon(Icons.lock_outline),
                          title: Text(strings.localFirstByok),
                          subtitle: Text(strings.localFirstByokDescription),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.restore_page_outlined),
                      title: Text(strings.restoreOrTransferExistingData),
                      subtitle: Text(strings.restoreOrTransferDescription),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              title: Text(strings.setupExistingData),
                            ),
                            body: const SettingsScreen(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.person_add_outlined),
                      title: Text(strings.startFresh),
                      subtitle: Text(strings.startFreshDescription),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showAddProfileDialog(
                        context,
                        context.read<AppController>(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.additionalPhoneHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeShell extends StatelessWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ShellNavigation(),
    child: const _HomeShellBody(),
  );
}

class _HomeShellBody extends StatelessWidget {
  const _HomeShellBody();

  /// Keyed by the mode, because TrackingScreen and HealthScreen size their
  /// TabControllers once and a controller cannot change length. Switching
  /// profiles therefore has to rebuild them rather than mutate them.
  ///
  /// The list always has five entries at their canonical indices, even in easy
  /// mode where nothing can navigate to the supplements one. An IndexedStack
  /// builds every child, so that slot holds a placeholder rather than a
  /// two-thousand-line screen this profile can never open.
  static List<Widget> _screensFor(bool easyMode) {
    final key = ValueKey(easyMode);
    return [
      easyMode ? const CalmHomeScreen() : const DashboardScreen(),
      easyMode ? const SizedBox.shrink() : TrackingScreen(key: key),
      HealthScreen(key: key),
      const AdvisorScreen(),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final navigation = context.watch<ShellNavigation>();
    final strings = AppLocalizations.of(context);
    final visibility = controller.visibility;
    final index = navigation.tabIndex;
    final tabs = shellTabsFor(easyMode: visibility.calmShell);
    // A destination that is not in the bar can only be reached by a deep link,
    // and none of easy mode's shortcuts issue one. Falling back to Today keeps
    // the highlight honest rather than leaving the bar pointing at nothing.
    final barIndex = tabs.contains(index) ? tabs.indexOf(index) : 0;
    final titles = [
      strings.today,
      strings.supplements,
      strings.health,
      strings.advisor,
      strings.settings,
    ];
    final items = [
      BottomNavigationBarItem(icon: Icon(Icons.today), label: strings.today),
      BottomNavigationBarItem(
        icon: Icon(Icons.medication),
        label: strings.supplements,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.monitor_heart),
        label: strings.health,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.psychology),
        label: strings.advisor,
      ),
      BottomNavigationBarItem(
        icon: Icon(Icons.settings),
        label: strings.settings,
      ),
    ];
    final body = IndexedStack(
      index: index,
      children: _screensFor(controller.activeProfile?.easyMode ?? true),
    );
    return Scaffold(
      // The stock drawer counts what is left in a tub. Easy mode does not
      // track stock at all, so the button opened a permanently empty panel.
      endDrawer: visibility.stockManagement
          ? const Drawer(child: SafeArea(child: StockOverviewPanel()))
          : null,
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(titles[index]),
            Text(
              controller.activeProfile!.displayName,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (visibility.stockManagement)
            Builder(
              builder: (scaffoldContext) => IconButton(
                tooltip: strings.pick('Stock overview', 'Bestandsübersicht'),
                onPressed: () => Scaffold.of(scaffoldContext).openEndDrawer(),
                icon: const Icon(Icons.inventory_2_outlined),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: strings.switchProfile,
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                controller.activeProfile!.displayName.characters.first
                    .toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
            onSelected: (value) {
              if (value == '__new') {
                showAddProfileDialog(context, controller);
              } else {
                controller.selectProfile(value);
              }
            },
            itemBuilder: (context) => [
              for (final profile in controller.profiles)
                PopupMenuItem(
                  value: profile.id,
                  child: Row(
                    children: [
                      if (profile.id == controller.activeProfile!.id)
                        const Icon(Icons.check, size: 18)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 8),
                      Text(profile.displayName),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: '__new',
                child: Row(
                  children: [
                    Icon(Icons.person_add_outlined, size: 18),
                    SizedBox(width: 8),
                    Text(strings.newProfile),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
        bottom: controller.busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: visibility.calmShell ? BlossomBackground(child: body) : body,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: barIndex,
        onTap: (position) => navigation.selectTab(tabs[position]),
        type: BottomNavigationBarType.fixed,
        items: [for (final tab in tabs) items[tab]],
      ),
    );
  }
}
