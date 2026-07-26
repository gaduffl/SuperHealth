import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../ui/advisor_screen.dart';
import '../ui/common.dart';
import '../ui/dashboard_screen.dart';
import '../ui/dialogs.dart';
import '../ui/health_screen.dart';
import '../ui/settings_screen.dart';
import '../ui/tracking_screen.dart';
import 'app_controller.dart';
import 'app_localizations.dart';
import 'app_theme.dart';

class SuperHealthApp extends StatelessWidget {
  const SuperHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<AppController>().appearanceSettings;
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
      theme: buildAppTheme(brightness: Brightness.light, settings: appearance),
      darkTheme: buildAppTheme(
        brightness: Brightness.dark,
        settings: appearance,
      ),
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
              Icon(Icons.health_and_safety_outlined, size: 56),
              SizedBox(height: 18),
              CircularProgressIndicator(),
              SizedBox(height: 12),
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
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.health_and_safety_outlined,
                      size: 58,
                    ),
                  ),
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

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  var _index = 0;

  static const _screens = [
    DashboardScreen(),
    TrackingScreen(),
    HealthScreen(),
    AdvisorScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final strings = AppLocalizations.of(context);
    final titles = [
      strings.today,
      strings.supplements,
      strings.health,
      strings.advisor,
      strings.settings,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titles[_index]),
            Text(
              controller.activeProfile!.displayName,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: strings.switchProfile,
            icon: CircleAvatar(
              radius: 17,
              child: Text(
                controller.activeProfile!.displayName.characters.first
                    .toUpperCase(),
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
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: strings.today,
          ),
          NavigationDestination(
            icon: Icon(Icons.medication_outlined),
            selectedIcon: Icon(Icons.medication),
            label: strings.supplements,
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: strings.health,
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: strings.advisor,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: strings.settings,
          ),
        ],
      ),
    );
  }
}
