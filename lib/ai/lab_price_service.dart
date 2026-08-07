import 'dart:convert';

import 'package:dio/dio.dart';

import '../domain/entities.dart';
import 'ai_models.dart';
import 'ai_settings.dart';
import 'api_key_store.dart';
import 'provider_clients.dart';

/// Why a proposed price cannot be applied without the owner looking at it.
///
/// A wrong price is not a cosmetic error: the lab planner costs its tiers from
/// these numbers, so it changes what the app tells someone to spend.
enum LabPriceReviewReason {
  /// The model gave no verbatim line it read the price from, so nothing
  /// distinguishes a sourced figure from an invented one.
  unsourced,

  /// The source quoted a currency other than the one the field stores.
  foreignCurrency,

  /// A large move against the stored price. Usually a different panel, a
  /// different lab, or a decimal in the wrong place.
  largeChange,

  /// No stored price to compare against, so nothing contradicts it either.
  firstPrice,

  /// A lab name that disagrees with the one already recorded.
  conflictingLab,
}

extension LabPriceReviewReasonX on LabPriceReviewReason {
  String get englishLabel => switch (this) {
    LabPriceReviewReason.unsourced => 'No quoted source',
    LabPriceReviewReason.foreignCurrency => 'Quoted in another currency',
    LabPriceReviewReason.largeChange => 'Large change',
    LabPriceReviewReason.firstPrice => 'First price for this marker',
    LabPriceReviewReason.conflictingLab => 'Different lab than stored',
  };

  String get germanLabel => switch (this) {
    LabPriceReviewReason.unsourced => 'Keine Quelle zitiert',
    LabPriceReviewReason.foreignCurrency => 'In anderer Währung angegeben',
    LabPriceReviewReason.largeChange => 'Große Änderung',
    LabPriceReviewReason.firstPrice => 'Erster Preis für diesen Marker',
    LabPriceReviewReason.conflictingLab => 'Anderes Labor als gespeichert',
  };
}

/// One price the model proposes for one biomarker.
class LabPriceProposal {
  const LabPriceProposal({
    required this.biomarkerId,
    required this.biomarkerName,
    required this.oldPriceEur,
    required this.newPriceEur,
    required this.labName,
    required this.currency,
    required this.quote,
    required this.reviewReasons,
  });

  final String biomarkerId;
  final String biomarkerName;
  final double? oldPriceEur;
  final double newPriceEur;
  final String labName;

  /// As quoted by the source. Anything but EUR is surfaced rather than
  /// converted: an exchange rate the app invented would be a second guess
  /// stacked on the first.
  final String currency;

  /// The verbatim line the price was read from. Empty when the model asserted
  /// a figure instead of reading one — which is exactly what review is for.
  final String quote;

  final Set<LabPriceReviewReason> reviewReasons;

  /// Whether this can be pre-ticked. Confident means sourced, in euros, and
  /// not a surprise against what is already stored.
  bool get isConfident => reviewReasons.isEmpty;
}

/// What one pricing run produced.
class LabPriceProposalSet {
  const LabPriceProposalSet({
    required this.proposals,
    required this.unknownBiomarkerIds,
    required this.sourceUrl,
    required this.usage,
  });

  final List<LabPriceProposal> proposals;

  /// Ids the model returned that are not in the catalog. Dropped rather than
  /// created: inventing a biomarker to hang a price on is worse than no price.
  final List<String> unknownBiomarkerIds;

  final String? sourceUrl;
  final TokenUsage? usage;

  List<LabPriceProposal> get confident =>
      proposals.where((item) => item.isConfident).toList();
  List<LabPriceProposal> get needsReview =>
      proposals.where((item) => !item.isConfident).toList();

  bool get isEmpty => proposals.isEmpty;
}

class LabPriceException implements Exception {
  const LabPriceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads lab prices from a page or from text the owner pastes, and proposes
/// catalog updates. Never writes: the caller applies an approved subset.
class LabPriceService {
  LabPriceService(this._keyStore, this._clientFactory, {Dio? dio})
    : _dio = dio ?? Dio();

  final ApiKeyStore _keyStore;
  final AiProviderClientFactory _clientFactory;
  final Dio _dio;

  /// A price list is text, not a document. Anything past this is navigation
  /// chrome and footers, and paying to send it helps nobody.
  static const maxSourceCharacters = 120000;

  /// A move this large against a stored price is nearly always a different
  /// panel or a misplaced decimal rather than a real change.
  static const largeChangeFactor = 1.5;

  static const systemPrompt = '''
You update a personal biomarker price catalog. You are given the catalog and,
optionally, a lab price list.

Rules:
- Only return biomarker_id values present in the supplied catalog. Never invent
  one, and never rename a marker.
- Quote the exact line you read each price from in "quote". If you did not read
  it from the supplied source, leave "quote" empty rather than paraphrasing.
- Report the currency the source states. Do not convert between currencies.
- A price is for a single named test. Do not divide a panel price across its
  parts, and do not return a panel price for one of its members.
- Omit any biomarker you have no price for. An omission is a correct answer.
''';

  /// Fetches a price page and reduces it to text.
  ///
  /// Done in the app rather than by the model: no provider exposes a
  /// fetch-this-URL tool, and fetching here means the owner can see exactly
  /// what was sent before it is sent.
  Future<String> fetchSource(Uri url) async {
    if (!url.isScheme('http') && !url.isScheme('https')) {
      throw const LabPriceException('Only http and https addresses are read.');
    }
    final Response<String> response;
    try {
      response = await _dio.getUri<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          // A price page that answers with an error still answers; surface the
          // status rather than letting dio throw a generic failure.
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (error) {
      throw LabPriceException('Could not load $url: ${error.message}');
    }
    if ((response.statusCode ?? 0) >= 400) {
      throw LabPriceException('$url answered ${response.statusCode}.');
    }
    final text = htmlToText(response.data ?? '');
    if (text.trim().isEmpty) {
      throw LabPriceException('$url returned no readable text.');
    }
    return text;
  }

  /// Reduces markup to the text a reader would see.
  ///
  /// Script and style bodies go first — they are the bulk of a modern page and
  /// none of it is price data. Block-level tags become newlines so table rows
  /// do not run together into one unreadable line, which is what makes a price
  /// list parseable at all.
  static String htmlToText(String html) {
    var text = html
        .replaceAll(
          RegExp(
            r'<(script|style)[^>]*>.*?</\1>',
            dotAll: true,
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ')
        .replaceAll(
          RegExp(
            r'</(p|div|tr|li|h[1-6]|table|section)>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</t[dh]>', caseSensitive: false), '\t')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    for (final entry in const {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&euro;': '€',
    }.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    final lines = text
        .split('\n')
        .map(
          (line) => line
              // Collapse a run of whitespace that contains a tab down to one
              // tab, so a table row keeps its column boundaries. Flattening it
              // to a space would run "Ferritin" into its price and lose the
              // structure that makes a price list readable at all.
              .replaceAll(RegExp(r'[ \t]*\t[ \t]*'), '\t')
              .replaceAll(RegExp(r' +'), ' ')
              .trim(),
        )
        .where((line) => line.isNotEmpty);
    final joined = lines.join('\n');
    return joined.length <= maxSourceCharacters
        ? joined
        : joined.substring(0, maxSourceCharacters);
  }

  /// The catalog rows the model is allowed to price.
  ///
  /// Deliberately not the health context: pricing needs no measurements, no
  /// supplements and no symptoms, so none are sent.
  static String catalogJson(List<Biomarker> catalog) => jsonEncode({
    'biomarkers': [
      for (final item in catalog)
        {
          'biomarker_id': item.id,
          'name': item.displayName,
          if (item.category.isNotEmpty) 'category': item.category,
          if (item.synonyms.isNotEmpty) 'synonyms': item.synonyms,
          'current_price_eur': item.priceEur,
          if (item.labName != null) 'current_lab': item.labName,
        },
    ],
  });

  Future<LabPriceProposalSet> propose({
    required List<Biomarker> catalog,
    required AiTaskSettings settings,
    String? sourceText,
    String? sourceUrl,
    String? instructions,
  }) async {
    if (catalog.isEmpty) {
      throw const LabPriceException('The biomarker catalog is empty.');
    }
    final key = await _keyStore.read(settings.provider);
    if (key == null) {
      throw LabPriceException('Add a ${settings.provider.name} API key first.');
    }
    final client = _clientFactory.create(settings.provider);
    final prompt = StringBuffer(
      'Return a price for every biomarker in the catalog you can price.',
    );
    if (instructions != null && instructions.trim().isNotEmpty) {
      prompt.writeln('\n\nOwner instructions:\n${instructions.trim()}');
    }
    if (sourceUrl != null && sourceUrl.trim().isNotEmpty) {
      prompt.writeln('\n\nSource page: ${sourceUrl.trim()}');
    }
    if (sourceText != null && sourceText.trim().isNotEmpty) {
      prompt.writeln('\n\nSource text:\n${sourceText.trim()}');
    } else if (!settings.webSearch) {
      prompt.writeln(
        '\n\nNo source text was supplied. Only return prices you are certain '
        'of, and leave "quote" empty for each of them.',
      );
    }

    final response = await client.respond(
      key,
      ProviderRequest(
        model: settings.model,
        systemPrompt: systemPrompt,
        userPrompt: prompt.toString(),
        contextJson: catalogJson(catalog),
        reasoningLevel: settings.reasoningLevel,
        webSearch: settings.webSearch,
        requireJson: true,
        jsonSchema: _schema,
        maxOutputTokens: 16000,
      ),
    );
    return parseResponse(
      response.text,
      catalog: catalog,
      sourceUrl: sourceUrl,
      usage: response.usage,
    );
  }

  /// Turns a model response into proposals, classifying each one.
  ///
  /// Separated from the network call so the classification rules — the part
  /// that decides what gets pre-ticked — can be tested directly.
  static LabPriceProposalSet parseResponse(
    String text, {
    required List<Biomarker> catalog,
    String? sourceUrl,
    TokenUsage? usage,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw LabPriceException(
        'The model did not return JSON: ${error.message}',
      );
    }
    if (decoded is! Map) {
      throw const LabPriceException('The model did not return a JSON object.');
    }
    final rows = decoded['prices'];
    if (rows is! List) {
      throw const LabPriceException('The response has no "prices" array.');
    }
    final byId = {for (final item in catalog) item.id: item};
    final proposals = <LabPriceProposal>[];
    final unknown = <String>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final id = '${row['biomarker_id'] ?? ''}'.trim();
      final biomarker = byId[id];
      if (biomarker == null) {
        if (id.isNotEmpty) unknown.add(id);
        continue;
      }
      final price = _toDouble(row['price_eur']);
      if (price == null || price <= 0 || !price.isFinite) continue;
      final currency = '${row['currency'] ?? 'EUR'}'.trim().toUpperCase();
      final quote = '${row['quote'] ?? ''}'.trim();
      final lab = '${row['lab_name'] ?? ''}'.trim();
      final old = biomarker.priceEur;

      final reasons = <LabPriceReviewReason>{
        if (quote.isEmpty) LabPriceReviewReason.unsourced,
        if (currency.isNotEmpty && currency != 'EUR')
          LabPriceReviewReason.foreignCurrency,
        if (old == null) LabPriceReviewReason.firstPrice,
        if (old != null && old > 0 && _isLargeChange(old, price))
          LabPriceReviewReason.largeChange,
        if (lab.isNotEmpty &&
            (biomarker.labName ?? '').isNotEmpty &&
            lab.toLowerCase() != biomarker.labName!.toLowerCase())
          LabPriceReviewReason.conflictingLab,
      };

      proposals.add(
        LabPriceProposal(
          biomarkerId: biomarker.id,
          biomarkerName: biomarker.displayName,
          oldPriceEur: old,
          newPriceEur: price,
          labName: lab.isEmpty ? (biomarker.labName ?? '') : lab,
          currency: currency.isEmpty ? 'EUR' : currency,
          quote: quote,
          reviewReasons: reasons,
        ),
      );
    }
    proposals.sort((a, b) => a.biomarkerName.compareTo(b.biomarkerName));
    return LabPriceProposalSet(
      proposals: List.unmodifiable(proposals),
      unknownBiomarkerIds: List.unmodifiable(unknown),
      sourceUrl: sourceUrl,
      usage: usage,
    );
  }

  static bool _isLargeChange(double before, double after) =>
      after > before * largeChangeFactor || after < before / largeChangeFactor;

  static double? _toDouble(Object? value) => switch (value) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text.trim().replaceAll(',', '.')),
    _ => null,
  };

  static const _schema = <String, Object?>{
    'type': 'object',
    'additionalProperties': false,
    'required': ['prices'],
    'properties': {
      'prices': {
        'type': 'array',
        'items': {
          'type': 'object',
          'additionalProperties': false,
          'required': [
            'biomarker_id',
            'price_eur',
            'currency',
            'quote',
            'lab_name',
          ],
          'properties': {
            'biomarker_id': {'type': 'string'},
            'price_eur': {'type': 'number'},
            'currency': {'type': 'string'},
            'lab_name': {'type': 'string'},
            'quote': {'type': 'string'},
          },
        },
      },
    },
  };
}
