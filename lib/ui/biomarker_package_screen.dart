import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';

String _packageText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

/// Manages the bundles a lab sells — "großes Blutbild" and the like.
///
/// A package is a lab's offering rather than a person's, so it sits beside the
/// biomarker catalog and is shared across profiles.
class BiomarkerPackageScreen extends StatelessWidget {
  const BiomarkerPackageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final packages = controller.biomarkerPackages;
    return Scaffold(
      appBar: AppBar(
        title: Text(_packageText(context, 'Test packages', 'Testpakete')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBiomarkerPackageDialog(context, controller),
        icon: const Icon(Icons.add),
        label: Text(_packageText(context, 'New package', 'Neues Paket')),
      ),
      body: packages.isEmpty
          ? EmptyState(
              icon: Icons.inventory_2_outlined,
              title: _packageText(
                context,
                'No test packages yet',
                'Noch keine Testpakete',
              ),
              message: _packageText(
                context,
                'Record a bundle your lab sells — a small blood count, a thyroid '
                    'panel — and a plan that needs several of its tests is costed '
                    'at the bundle price instead of the sum.',
                'Erfasse ein Paket deines Labors — kleines Blutbild, '
                    'Schilddrüsenpanel — dann wird ein Plan, der mehrere seiner '
                    'Tests braucht, zum Paketpreis statt zur Summe berechnet.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              children: [
                for (final package in packages)
                  Builder(
                    builder: (context) {
                      final members =
                          controller.biomarkerPackageMembers[package.id] ??
                          const <String>{};
                      return ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(package.name),
                        subtitle: Text(
                          [
                            package.hasPrice
                                ? '${package.priceEur!.toStringAsFixed(2)} €'
                                : _packageText(
                                    context,
                                    'No price',
                                    'Kein Preis',
                                  ),
                            _packageText(
                              context,
                              '${members.length} test(s)',
                              '${members.length} Test(s)',
                            ),
                            if (package.labName?.isNotEmpty ?? false)
                              package.labName!,
                          ].join(' · '),
                        ),
                        onTap: () => showBiomarkerPackageDialog(
                          context,
                          controller,
                          existing: package,
                          members: members,
                        ),
                        trailing: IconButton(
                          tooltip: _packageText(context, 'Delete', 'Löschen'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              controller.deleteBiomarkerPackage(package),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

Future<void> showBiomarkerPackageDialog(
  BuildContext context,
  AppController controller, {
  BiomarkerPackage? existing,
  Set<String> members = const {},
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final price = TextEditingController(
    text: existing?.hasPrice ?? false
        ? existing!.priceEur!.toStringAsFixed(2)
        : '',
  );
  final lab = TextEditingController(text: existing?.labName ?? '');
  final selected = {...members};
  final search = TextEditingController();

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final query = search.text.trim().toLowerCase();
        final candidates = controller.biomarkers
            .where(
              (item) =>
                  query.isEmpty ||
                  item.displayName.toLowerCase().contains(query),
            )
            .toList();
        return AlertDialog(
          title: Text(
            existing == null
                ? _packageText(context, 'New package', 'Neues Paket')
                : _packageText(context, 'Edit package', 'Paket bearbeiten'),
          ),
          content: SizedBox(
            width: 640,
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: _packageText(context, 'Name', 'Name'),
                    hintText: 'Großes Blutbild',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _packageText(
                            context,
                            'Bundle price (€)',
                            'Paketpreis (€)',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lab,
                        decoration: InputDecoration(
                          labelText: _packageText(context, 'Lab', 'Labor'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    labelText: _packageText(
                      context,
                      'Tests in this package (${selected.length} selected)',
                      'Tests in diesem Paket (${selected.length} ausgewählt)',
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final biomarker in candidates)
                        CheckboxListTile(
                          dense: true,
                          value: selected.contains(biomarker.id),
                          onChanged: (value) => setState(() {
                            if (value ?? false) {
                              selected.add(biomarker.id);
                            } else {
                              selected.remove(biomarker.id);
                            }
                          }),
                          title: Text(biomarker.displayName),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_packageText(context, 'Cancel', 'Abbrechen')),
            ),
            FilledButton(
              // A package needs a name and at least two tests: one test is
              // that test's own price under another name.
              onPressed: name.text.trim().isEmpty || selected.length < 2
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: Text(_packageText(context, 'Save', 'Speichern')),
            ),
          ],
        );
      },
    ),
  );

  if (saved == true) {
    final now = DateTime.now();
    final parsed = double.tryParse(price.text.trim().replaceAll(',', '.'));
    await controller.saveBiomarkerPackage(
      BiomarkerPackage(
        id: existing?.id ?? controller.repository.newId(),
        name: name.text.trim(),
        priceEur: parsed,
        labName: lab.text.trim().isEmpty ? null : lab.text.trim(),
        // Stamped only when a price is present, matching how a biomarker's
        // own price records when it was last verified.
        priceCheckedAt: parsed == null ? existing?.priceCheckedAt : now,
        notes: existing?.notes ?? '',
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
      selected,
    );
  }
  name.dispose();
  price.dispose();
  lab.dispose();
  search.dispose();
}
