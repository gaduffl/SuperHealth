import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ui/advisor_screen.dart';
import '../ui/common.dart';
import '../ui/dashboard_screen.dart';
import '../ui/dialogs.dart';
import '../ui/labs_screen.dart';
import '../ui/settings_screen.dart';
import '../ui/tracking_screen.dart';
import 'app_controller.dart';

class SuperHealthApp extends StatelessWidget {
  const SuperHealthApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SuperHealth',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const _AppGate(),
  );

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF087F78),
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
    );
  }
}

class _AppGate extends StatelessWidget {
  const _AppGate();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    if (!controller.initialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.health_and_safety_outlined, size: 56),
              SizedBox(height: 18),
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Opening your private health record…'),
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
                title: 'SuperHealth could not start',
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
  Widget build(BuildContext context) => Scaffold(
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
                  child: const Icon(Icons.health_and_safety_outlined, size: 58),
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome to SuperHealth',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  'One private place for supplements, symptoms, biomarkers, lab planning, '
                  'and a full-context AI advisor.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                const Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.people_outline),
                        title: Text('Isolated profiles'),
                        subtitle: Text(
                          'Only the selected profile enters an AI request or export.',
                        ),
                      ),
                      Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('Local-first and BYOK'),
                        subtitle: Text(
                          'No Google login, billing worker, or app-owned AI keys.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => showAddProfileDialog(
                    context,
                    context.read<AppController>(),
                  ),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Create first profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  var _index = 0;

  static const _titles = ['Today', 'Track', 'Labs', 'Advisor', 'Settings'];
  static const _screens = [
    DashboardScreen(),
    TrackingScreen(),
    LabsScreen(),
    AdvisorScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titles[_index]),
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
            tooltip: 'Switch profile',
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
              const PopupMenuItem(
                value: '__new',
                child: Row(
                  children: [
                    Icon(Icons.person_add_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('New profile'),
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_chart_outlined),
            selectedIcon: Icon(Icons.add_chart),
            label: 'Track',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Labs',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'Advisor',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
