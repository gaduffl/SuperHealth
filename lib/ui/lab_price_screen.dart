import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/lab_price_service.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import 'common.dart';

String _priceText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

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
  final _instructions = TextEditingController();

  String? _fetched;
  String? _error;
  bool _working = false;

  @override
  void dispose() {
    _url.dispose();
    _instructions.dispose();
    super.dispose();
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
      if (mounted) setState(() => _error = '$error');
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
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final priced = controller.biomarkers
        .where((item) => !item.deleted && item.priceEur != null)
        .length;
    final total = controller.biomarkers.where((item) => !item.deleted).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _priceText(context, 'Update lab prices', 'Laborpreise aktualisieren'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            _priceText(
              context,
              '$priced of $total biomarkers have a price.',
              '$priced von $total Biomarkern haben einen Preis.',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _priceText(
              context,
              'Only the biomarker catalog is sent — no measurements, '
                  'supplements or symptoms. Nothing is saved until you approve it.',
              'Es wird nur der Biomarkerkatalog gesendet — keine Messwerte, '
                  'Ergänzungen oder Symptome. Nichts wird gespeichert, bevor du es freigibst.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
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
              onPressed: _working || _url.text.trim().isEmpty
                  ? null
                  : () => _fetch(controller),
              icon: const Icon(Icons.download_outlined),
              label: Text(_priceText(context, 'Fetch page', 'Seite laden')),
            ),
          ),
          if (_fetched != null) ...[
            const SizedBox(height: 8),
            // The fetched text is shown before it is sent, because "what did
            // it actually read" is the question every wrong price raises.
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
                      style: Theme.of(context).textTheme.labelLarge,
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
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _instructions,
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
                'Use Labor Bayer, Munich. Only the vitamin panel.',
                'Nutze Labor Bayer, München. Nur das Vitaminpanel.',
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _working || controller.busy
                ? null
                : () => _propose(controller),
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              _priceText(context, 'Suggest prices', 'Preise vorschlagen'),
            ),
          ),
          if (_working) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
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
                if (set.unknownBiomarkerIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      _priceText(
                        context,
                        '${set.unknownBiomarkerIds.length} price(s) named a biomarker '
                            'that is not in your catalog and were dropped.',
                        '${set.unknownBiomarkerIds.length} Preis(e) nannten einen Biomarker, '
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
            onChanged: (value) => onChanged(proposal, value ?? false),
            title: Text(proposal.biomarkerName),
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
