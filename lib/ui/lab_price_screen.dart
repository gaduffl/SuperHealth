import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/lab_price_service.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';

String _priceText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

class LabSelectionField extends StatelessWidget {
  const LabSelectionField({
    required this.labs,
    required this.value,
    required this.onChanged,
    super.key,
  });
  final List<String> labs;
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value ?? '',
    isExpanded: true,
    decoration: InputDecoration(
      labelText: _priceText(context, 'Laboratory prices', 'Laborpreise'),
    ),
    items: [
      DropdownMenuItem(
        value: '',
        child: Text(
          _priceText(
            context,
            'Existing catalog prices',
            'Bisherige Katalogpreise',
          ),
        ),
      ),
      for (final lab in labs) DropdownMenuItem(value: lab, child: Text(lab)),
    ],
    onChanged: (value) => onChanged(value == '' ? null : value),
  );
}

/// Collects a source, asks the pricing model, and hands the result to review.
///
/// Kept separate from the lab planner: pricing needs no health records at all,
/// so none are sent, and it runs on its own model setting rather than whatever
/// the advisor happens to be pointed at.
class LabPriceScreen extends StatefulWidget {
  const LabPriceScreen({super.key});

  @override
  State<LabPriceScreen> createState() => _LabPriceScreenState();
}

class _LabPriceScreenState extends State<LabPriceScreen> {
  final _url = TextEditingController();
  final _lab = TextEditingController();
  final _instructions = TextEditingController();
  final _search = TextEditingController();
  final _fields = <String, TextEditingController>{};
  final _fieldFocus = <String, FocusNode>{};
  final _edits = <String, String>{};
  final _invalid = <String>{};
  final _newLabs = <String>[];
  bool _initialized = false;
  int _labSelectorRevision = 0;
  bool _missingOnly = false;
  bool _packagesOnly = false;
  String? _fetched;
  String? _error;
  bool _working = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _lab.text = context.read<AppController>().labNames.firstOrNull ?? '';
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _lab.dispose();
    _instructions.dispose();
    _search.dispose();
    for (final field in _fields.values) {
      field.dispose();
    }
    for (final focus in _fieldFocus.values) {
      focus.dispose();
    }
    super.dispose();
  }

  Future<bool> _discardChanges() async {
    if (_edits.isEmpty) return true;
    return showConfirmAction(
      context,
      title: _priceText(
        context,
        'Discard price changes?',
        'Preisänderungen verwerfen?',
      ),
      message: _priceText(
        context,
        '${_edits.length} price change(s) have not been saved.',
        '${_edits.length} Preisänderung(en) sind noch nicht gespeichert.',
      ),
      confirmLabel: _priceText(context, 'Discard', 'Verwerfen'),
      destructive: true,
    );
  }

  void _clearEdits() {
    FocusScope.of(context).unfocus();
    _edits.clear();
    _invalid.clear();
    _error = null;
  }

  Future<void> _selectLab(String name) async {
    if (labKey(name) == labKey(_lab.text)) return;
    if (!await _discardChanges()) {
      if (mounted) setState(() => _labSelectorRevision++);
      return;
    }
    if (!mounted) return;
    setState(() {
      _clearEdits();
      _lab.text = name;
      _url.clear();
      _instructions.clear();
      _fetched = null;
    });
  }

  Future<void> _addLab(AppController controller) async {
    final name = TextEditingController();
    final route = DialogRoute<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_priceText(context, 'Add laboratory', 'Labor hinzufügen')),
        content: TextField(
          controller: name,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: _priceText(context, 'Laboratory name', 'Laborname'),
            hintText: 'Bioscientia Mainz',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_priceText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, name.text.trim());
              }
            },
            child: Text(
              _priceText(context, 'Add laboratory', 'Labor hinzufügen'),
            ),
          ),
        ],
      ),
    );
    final added = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    name.dispose();
    if (added == null || !mounted) return;
    final existing = [
      ...controller.labNames,
      ..._newLabs,
    ].where((lab) => labKey(lab) == labKey(added)).firstOrNull;
    if (existing == null) setState(() => _newLabs.add(added));
    await _selectLab(existing ?? added);
  }

  Future<void> _fetch(AppController controller) async {
    setState(() {
      _working = true;
      _error = null;
      _fetched = null;
    });
    try {
      final text = await controller.fetchLabPriceSource(_url.text);
      if (mounted) setState(() => _fetched = text);
    } on Object catch (error) {
      if (mounted) setState(() => _error = sanitizeAppErrorMessage('$error'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _propose(AppController controller) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final proposals = await controller.proposeLabPrices(
        labName: _lab.text.trim(),
        sourceText: _fetched,
        sourceUrl: _url.text.trim().isEmpty ? null : _url.text.trim(),
        instructions: _instructions.text,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LabPriceReviewScreen(proposals: proposals),
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = sanitizeAppErrorMessage('$error'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save(AppController controller) async {
    final markers = <String, double>{};
    final packages = <String, double>{};
    _invalid.clear();
    for (final entry in _edits.entries) {
      final value = double.tryParse(entry.value.trim().replaceAll(',', '.'));
      if (value == null || !value.isFinite || value <= 0) {
        _invalid.add(entry.key);
      } else {
        (entry.key.startsWith('p:') ? packages : markers)[entry.key.substring(
              2,
            )] =
            value;
      }
    }
    if (_invalid.isNotEmpty) {
      setState(
        () => _error = _priceText(
          context,
          'Enter a positive EUR price for each changed row. Nothing has been saved.',
          'Gib für jede geänderte Zeile einen positiven Euro-Preis ein. Es wurde nichts gespeichert.',
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _error = null;
    });
    final count = _edits.length;
    try {
      await controller.saveLabPriceValues(
        labName: _lab.text,
        biomarkerPrices: markers,
        packagePrices: packages,
      );
      if (!mounted) return;
      setState(_clearEdits);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _priceText(
              context,
              '$count price(s) saved.',
              '$count Preis(e) gespeichert.',
            ),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _error = sanitizeAppErrorMessage('$error'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editPrice(AppController controller, _PriceEntry entry) async {
    final selected = entry.key;
    final lab = _lab.text;
    final stored = controller
        .pricesForLab(lab)
        .priceFor(selected.substring(2), isPackage: entry.isPackage);
    final price = TextEditingController(
      text: entry.price?.toStringAsFixed(2) ?? '',
    );
    final source = TextEditingController(text: stored?.sourceUrl ?? '');
    String? error;
    var saving = false;
    final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(_priceText(context, 'Price · $lab', 'Preis · $lab')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: price,
                  autofocus: true,
                  enabled: !saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _priceText(
                      context,
                      'Price in EUR',
                      'Preis in EUR',
                    ),
                    errorText: error,
                  ),
                ),
                TextField(
                  controller: source,
                  enabled: !saving,
                  decoration: InputDecoration(
                    labelText: _priceText(
                      context,
                      'Source URL (optional)',
                      'Quellen-URL (optional)',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: Text(_priceText(context, 'Cancel', 'Abbrechen')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final value = double.tryParse(
                        price.text.trim().replaceAll(',', '.'),
                      );
                      if (value == null || !value.isFinite || value <= 0) {
                        setState(
                          () => error = _priceText(
                            context,
                            'Enter a positive EUR price.',
                            'Gib einen positiven Euro-Preis ein.',
                          ),
                        );
                        return;
                      }
                      setState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await controller.saveLabPrice(
                          labName: lab,
                          targetId: selected.substring(2),
                          isPackage: selected.startsWith('p:'),
                          priceEur: value,
                          sourceUrl: source.text.trim().isEmpty
                              ? null
                              : source.text.trim(),
                        );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } on Object catch (failure) {
                        if (dialogContext.mounted) {
                          setState(() {
                            saving = false;
                            error = '$failure';
                          });
                        }
                      }
                    },
              child: Text(_priceText(context, 'Save price', 'Preis speichern')),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    // The fields remain mounted during the dialog's closing animation.
    await route.completed;
    price.dispose();
    source.dispose();
  }

  Widget _priceRow(AppController controller, _PriceEntry entry, bool enabled) {
    // Include the lab in the field identity so changing laboratories cannot
    // reuse another laboratory's unsaved input or cursor.
    final fieldKey = '${labKey(_lab.text)}:${entry.key}';
    final initial = entry.price?.toStringAsFixed(2) ?? '';
    final field = _fields.putIfAbsent(
      fieldKey,
      () => TextEditingController(text: initial),
    );
    final focus = _fieldFocus.putIfAbsent(fieldKey, () => FocusNode());
    if (!_edits.containsKey(entry.key) &&
        !focus.hasFocus &&
        field.text != initial) {
      field.text = initial;
    }
    final strings = AppLocalizations.of(context);
    final checked = entry.checkedAt == null
        ? null
        : strings.formatHistoryDate(entry.checkedAt!.toLocal());
    return Card(
      key: ValueKey('row-${entry.key}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.isPackage)
                        Text(
                          _priceText(context, 'Test package', 'Testpaket'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      Text(
                        entry.name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.price == null
                            ? _priceText(
                                context,
                                'Price missing',
                                'Preis fehlt',
                              )
                            : checked == null
                            ? _priceText(
                                context,
                                'Not yet checked',
                                'Noch nicht geprüft',
                              )
                            : _priceText(
                                context,
                                'Checked $checked',
                                'Geprüft $checked',
                              ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: ValueKey('price-${entry.key}'),
                    controller: field,
                    focusNode: focus,
                    enabled: enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: _priceText(context, 'Price (€)', 'Preis (€)'),
                      hintText: '—',
                      errorText: _invalid.contains(entry.key)
                          ? _priceText(
                              context,
                              'Invalid price',
                              'Ungültiger Preis',
                            )
                          : null,
                    ),
                    onChanged: (value) => setState(() {
                      final parsed = double.tryParse(
                        value.trim().replaceAll(',', '.'),
                      );
                      if (value == initial ||
                          (parsed != null && parsed == entry.price)) {
                        _edits.remove(entry.key);
                      } else {
                        _edits[entry.key] = value;
                      }
                      _invalid.remove(entry.key);
                      _error = null;
                    }),
                  ),
                ),
              ],
            ),
            if (_edits.containsKey(entry.key))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _priceText(
                    context,
                    'Unsaved change',
                    'Ungespeicherte Änderung',
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: enabled && _edits.isEmpty
                    ? () => _editPrice(controller, entry)
                    : null,
                icon: const Icon(Icons.link, size: 16),
                label: Text(
                  _priceText(
                    context,
                    'Price details / source',
                    'Preisdetails / Quelle',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiImport(AppController controller, bool enabled) => ExpansionTile(
    key: ValueKey('import-${labKey(_lab.text)}'),
    leading: const Icon(Icons.auto_awesome_outlined),
    title: Text(
      _priceText(context, 'Import prices with AI', 'Preise mit KI übernehmen'),
    ),
    subtitle: Text(
      _priceText(
        context,
        'From a website or pasted price list',
        'Aus einer Webseite oder eingefügten Preisliste',
      ),
    ),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            Text(
              _priceText(
                context,
                'Only the biomarker catalog is sent — no measurements, supplements or symptoms. Review proposals before saving.',
                'Es wird nur der Biomarkerkatalog gesendet — keine Messwerte, Ergänzungen oder Symptome. Vorschläge vor dem Speichern prüfen.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              enabled: enabled && _edits.isEmpty,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() => _fetched = null),
              decoration: InputDecoration(
                labelText: _priceText(
                  context,
                  'Lab price list address (optional)',
                  'Adresse der Laborpreisliste (optional)',
                ),
                hintText: 'https://…',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed:
                    enabled && _edits.isEmpty && _url.text.trim().isNotEmpty
                    ? () => _fetch(controller)
                    : null,
                icon: const Icon(Icons.download_outlined),
                label: Text(_priceText(context, 'Fetch page', 'Seite laden')),
              ),
            ),
            if (_fetched != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _priceText(
                          context,
                          'Read ${_fetched!.length} characters. First lines:',
                          '${_fetched!.length} Zeichen gelesen. Erste Zeilen:',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _fetched!.split('\n').take(8).join('\n'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _instructions,
              enabled: enabled && _edits.isEmpty,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: _priceText(
                  context,
                  'Notes or a pasted price list (optional)',
                  'Hinweise oder eingefügte Preisliste (optional)',
                ),
                hintText: _priceText(
                  context,
                  'Paste the lab’s prices here.',
                  'Füge hier die Preise des Labors ein.',
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: enabled && _edits.isEmpty
                  ? () => _propose(controller)
                  : null,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                _priceText(context, 'Suggest prices', 'Preise vorschlagen'),
              ),
            ),
            if (_edits.isNotEmpty)
              Text(
                _priceText(
                  context,
                  'Save or discard your price changes first.',
                  'Speichere oder verwirf zuerst deine Preisänderungen.',
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _searchField() => TextField(
    controller: _search,
    enabled: !_working,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      labelText: _priceText(
        context,
        'Search tests or packages',
        'Tests oder Pakete suchen',
      ),
      suffixIcon: _search.text.isEmpty
          ? null
          : IconButton(
              tooltip: _priceText(context, 'Clear search', 'Suche löschen'),
              onPressed: () => setState(_search.clear),
              icon: const Icon(Icons.close),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final lab = _lab.text;
    final enabled = !_working && !controller.busy;
    final labs = <String, String>{
      for (final name in [...controller.labNames, ..._newLabs])
        labKey(name): name,
      if (lab.isNotEmpty) labKey(lab): lab,
    }.values.toList();
    final pricing = controller.pricesForLab(lab);
    final entries = <_PriceEntry>[
      for (final marker in pricing.catalog(controller.biomarkers))
        if (!marker.deleted && !marker.isCalculated)
          _PriceEntry(
            key: 'm:${marker.id}',
            name: marker.displayName,
            searchText:
                '${marker.displayName} ${marker.canonicalName} ${marker.synonyms.join(' ')}',
            price: marker.hasPrice ? marker.priceEur : null,
            checkedAt: marker.priceCheckedAt,
          ),
      for (final package in pricing.packages(controller.biomarkerPackages))
        if (!package.deleted)
          _PriceEntry(
            key: 'p:${package.id}',
            name: package.name,
            searchText: package.name,
            price: package.hasPrice ? package.priceEur : null,
            checkedAt: package.priceCheckedAt,
          ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final markers = entries.where((entry) => !entry.isPackage).toList();
    final priced = markers.where((entry) => entry.price != null).length;
    final query = _search.text.trim().toLowerCase();
    final visible = entries
        .where(
          (entry) =>
              (!_missingOnly || entry.price == null) &&
              (!_packagesOnly || entry.isPackage) &&
              (query.isEmpty || entry.searchText.toLowerCase().contains(query)),
        )
        .toList();
    return PopScope(
      canPop: _edits.isEmpty && !_working,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _working) return;
        if (await _discardChanges() && mounted) {
          setState(_clearEdits);
          // PopScope must rebuild with canPop before requesting the pop again.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _priceText(context, 'Manage lab prices', 'Laborpreise pflegen'),
          ),
          bottom: lab.isEmpty
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(80),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: _searchField(),
                  ),
                ),
        ),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (labs.isNotEmpty)
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'selected-lab-$lab-$_labSelectorRevision',
                        ),
                        initialValue: lab.isEmpty ? null : lab,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _priceText(context, 'Laboratory', 'Labor'),
                        ),
                        items: [
                          for (final name in labs)
                            DropdownMenuItem(value: name, child: Text(name)),
                        ],
                        onChanged: enabled
                            ? (value) {
                                if (value != null) _selectLab(value);
                              }
                            : null,
                      ),
                    TextButton.icon(
                      onPressed: enabled ? () => _addLab(controller) : null,
                      icon: const Icon(Icons.add),
                      label: Text(
                        _priceText(
                          context,
                          'Add laboratory',
                          'Labor hinzufügen',
                        ),
                      ),
                    ),
                    if (lab.isNotEmpty) ...[
                      Text(
                        _priceText(
                          context,
                          '$priced of ${markers.length} tests priced · ${markers.length - priced} missing',
                          '$priced von ${markers.length} Tests mit Preis · ${markers.length - priced} fehlen',
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _priceText(
                          context,
                          'Edit prices below and save your changes together.',
                          'Preise unten ändern und die Änderungen gemeinsam speichern.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilterChip(
                            label: Text(
                              _priceText(
                                context,
                                'Missing prices',
                                'Fehlende Preise',
                              ),
                            ),
                            selected: _missingOnly,
                            onSelected: !_working
                                ? (value) =>
                                      setState(() => _missingOnly = value)
                                : null,
                          ),
                          FilterChip(
                            label: Text(
                              _priceText(
                                context,
                                'Test packages',
                                'Testpakete',
                              ),
                            ),
                            selected: _packagesOnly,
                            onSelected: !_working
                                ? (value) =>
                                      setState(() => _packagesOnly = value)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_working)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (lab.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.science_outlined,
                  title: _priceText(
                    context,
                    'Choose a laboratory',
                    'Wähle ein Labor',
                  ),
                  message: _priceText(
                    context,
                    'Add a laboratory to enter its test and package prices.',
                    'Füge ein Labor hinzu, um seine Test- und Paketpreise einzutragen.',
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(child: _aiImport(controller, enabled)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    visible.isEmpty
                        ? _priceText(
                            context,
                            'No tests match your filters.',
                            'Keine Tests passen zu deinen Filtern.',
                          )
                        : _priceText(
                            context,
                            '${visible.length} tests / packages',
                            '${visible.length} Tests / Pakete',
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) =>
                      _priceRow(controller, visible[index], enabled),
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: _edits.isEmpty
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _priceText(
                          context,
                          '${_edits.length} unsaved change(s) · $lab',
                          '${_edits.length} ungespeicherte Änderung(en) · $lab',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          TextButton(
                            onPressed: enabled
                                ? () async {
                                    if (await _discardChanges() && mounted) {
                                      setState(_clearEdits);
                                    }
                                  }
                                : null,
                            child: Text(
                              _priceText(context, 'Discard', 'Verwerfen'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: enabled
                                  ? () => _save(controller)
                                  : null,
                              icon: const Icon(Icons.save_outlined),
                              label: Text(
                                _priceText(
                                  context,
                                  'Save ${_edits.length} prices',
                                  '${_edits.length} Preise speichern',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _PriceEntry {
  const _PriceEntry({
    required this.key,
    required this.name,
    required this.searchText,
    this.price,
    this.checkedAt,
  });
  final String key;
  final String name;
  final String searchText;
  final double? price;
  final DateTime? checkedAt;
  bool get isPackage => key.startsWith('p:');
}

/// Shows every proposed price with what it was read from, and applies the
/// subset the owner ticks.
class LabPriceReviewScreen extends StatefulWidget {
  const LabPriceReviewScreen({required this.proposals, super.key});

  final LabPriceProposalSet proposals;

  @override
  State<LabPriceReviewScreen> createState() => _LabPriceReviewScreenState();
}

class _LabPriceReviewScreenState extends State<LabPriceReviewScreen> {
  late final Set<LabPriceProposal> _approved = {
    // Confident means sourced, in euros, and not a surprise against what is
    // stored. Everything else starts unticked and has to be read.
    ...widget.proposals.confident,
  };

  Future<void> _apply() async {
    final controller = context.read<AppController>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // The template is resolved before the await; the count is filled in after.
    // Reading the context across the gap is what the lint is there to stop.
    final template = _priceText(
      context,
      '{n} price(s) updated.',
      '{n} Preis(e) aktualisiert.',
    );
    final applied = await controller.applyLabPrices(_approved.toList());
    messenger.showSnackBar(
      SnackBar(content: Text(template.replaceFirst('{n}', '$applied'))),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final set = widget.proposals;
    final usage = set.usage;
    return Scaffold(
      appBar: AppBar(
        title: Text(_priceText(context, 'Review prices', 'Preise prüfen')),
      ),
      body: set.isEmpty
          ? EmptyState(
              icon: Icons.euro_outlined,
              title: _priceText(
                context,
                'No prices were found',
                'Es wurden keine Preise gefunden',
              ),
              message: _priceText(
                context,
                'Try a different address, or paste the price list as text.',
                'Versuche eine andere Adresse oder füge die Preisliste als Text ein.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              children: [
                if (usage != null && !usage.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '${usage.inputTokens ?? 0} in · ${usage.outputTokens ?? 0} out',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                // A partial result must not look complete: the batches that
                // failed are named, so a missing marker has an explanation.
                if (set.failedBatches.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      _priceText(
                        context,
                        'Could not read ${set.failedBatches.length} batch(es): '
                            '${set.failedBatches.join('; ')}',
                        '${set.failedBatches.length} Gruppe(n) konnten nicht gelesen werden: '
                            '${set.failedBatches.join('; ')}',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (set.unknownTargetIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      _priceText(
                        context,
                        '${set.unknownTargetIds.length} price(s) named a biomarker '
                            'that is not in your catalog and were dropped.',
                        '${set.unknownTargetIds.length} Preis(e) nannten einen Biomarker, '
                            'der nicht in deinem Katalog ist, und wurden verworfen.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if (set.confident.isNotEmpty)
                  _Section(
                    title: _priceText(context, 'Sourced', 'Mit Quelle'),
                    subtitle: _priceText(
                      context,
                      'Read from the source, in euros, close to what you had.',
                      'Aus der Quelle gelesen, in Euro, nahe am bisherigen Wert.',
                    ),
                    proposals: set.confident,
                    approved: _approved,
                    onChanged: _toggle,
                  ),
                if (set.needsReview.isNotEmpty)
                  _Section(
                    title: _priceText(context, 'Check these', 'Diese prüfen'),
                    subtitle: _priceText(
                      context,
                      'The lab planner costs its tiers from these numbers.',
                      'Der Laborplaner berechnet seine Stufen aus diesen Zahlen.',
                    ),
                    proposals: set.needsReview,
                    approved: _approved,
                    onChanged: _toggle,
                  ),
              ],
            ),
      bottomNavigationBar: set.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _approved.isEmpty || controller.busy
                      ? null
                      : _apply,
                  child: Text(
                    _priceText(
                      context,
                      'Apply ${_approved.length} price(s)',
                      '${_approved.length} Preis(e) übernehmen',
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  void _toggle(LabPriceProposal proposal, bool selected) => setState(() {
    if (selected) {
      _approved.add(proposal);
    } else {
      _approved.remove(proposal);
    }
  });
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.proposals,
    required this.approved,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<LabPriceProposal> proposals;
  final Set<LabPriceProposal> approved;
  final void Function(LabPriceProposal, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        for (final proposal in proposals)
          CheckboxListTile(
            value: approved.contains(proposal),
            onChanged: proposal.currency != 'EUR'
                ? null
                : (value) => onChanged(proposal, value ?? false),
            title: Row(
              children: [
                if (proposal.isPackage) ...[
                  const Icon(Icons.inventory_2_outlined, size: 16),
                  const SizedBox(width: 6),
                ],
                Expanded(child: Text(proposal.targetName)),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${proposal.oldPriceEur == null ? '—' : '${proposal.oldPriceEur!.toStringAsFixed(2)} €'}'
                  ' → ${proposal.newPriceEur.toStringAsFixed(2)} ${proposal.currency}'
                  '${proposal.labName.isEmpty ? '' : ' · ${proposal.labName}'}',
                ),
                if (proposal.quote.isNotEmpty)
                  Text(
                    '“${proposal.quote}”',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                if (proposal.reviewReasons.isNotEmpty)
                  Text(
                    proposal.reviewReasons
                        .map(
                          (reason) => _priceText(
                            context,
                            reason.englishLabel,
                            reason.germanLabel,
                          ),
                        )
                        .join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
            isThreeLine: true,
          ),
      ],
    );
  }
}
