// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'ai_models.dart';
import 'ai_settings.dart';
import 'api_key_store.dart';
import 'provider_clients.dart';

/// One ingredient read off a product label, already reduced to a single unit.
class ParsedLabelIngredient {
  const ParsedLabelIngredient({
    required this.name,
    required this.amount,
    required this.unit,
  });

  final String name;

  /// Amount per one stock unit — one capsule, tablet, or scoop.
  ///
  /// `null` when the label states an ingredient without a quantity, which is
  /// common for proprietary blends and for "contains traces of".
  final double? amount;
  final String unit;

  Map<String, Object?> toIngredientMap() => {
    'name': name,
    'amount': ?amount,
    if (unit.isNotEmpty) 'unit': unit,
  };
}

/// The reviewable result of reading a pasted label.
class ParsedSupplementLabel {
  const ParsedSupplementLabel({
    required this.ingredients,
    required this.servingSize,
    required this.warnings,
    this.detectedServingSize,
  });

  final List<ParsedLabelIngredient> ingredients;

  /// The serving size the amounts were divided by.
  final int servingSize;

  /// The serving size the model believes the label itself states.
  ///
  /// Surfaced so a label that says "per 4 capsules" while the person entered
  /// 1 is caught before the dose is stored four times too high.
  final int? detectedServingSize;

  final List<String> warnings;

  bool get servingSizeDisagrees =>
      detectedServingSize != null && detectedServingSize != servingSize;
}

class SupplementLabelFormatException implements Exception {
  const SupplementLabelFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads a pasted supplement label into structured ingredient rows.
///
/// Product labels state amounts per serving, and a serving is often several
/// capsules. Everything else in the app — component exposure, the advisor's
/// interaction check, the weekly plan — assumes an amount per single stock
/// unit, so the serving size has to be part of the input rather than something
/// a person is expected to divide out by hand.
class SupplementLabelService {
  SupplementLabelService({
    required ApiKeyStore keyStore,
    required AiProviderClientFactory clientFactory,
    ProviderCapabilityRegistry? capabilities,
  }) : _keyStore = keyStore,
       _clientFactory = clientFactory,
       _capabilities = capabilities ?? ProviderCapabilityRegistry();

  final ApiKeyStore _keyStore;
  final AiProviderClientFactory _clientFactory;
  final ProviderCapabilityRegistry _capabilities;

  static const systemPrompt =
      'You transcribe supplement product labels into structured data. You copy '
      'what the label states and never estimate, complete, or correct a value '
      'that is not printed on it. You answer with JSON only.';

  /// Sends [labelText] to the configured parsing model and returns rows to
  /// review.
  ///
  /// No health record is sent: a product label is public packaging text, so the
  /// request deliberately carries an empty context rather than the profile
  /// snapshot the advisor and lab planner use.
  Future<ParsedSupplementLabel> parse({
    required String labelText,
    required int servingSize,
    required AiTaskSettings settings,
    String stockUnit = 'unit',
  }) async {
    final text = labelText.trim();
    if (text.isEmpty) {
      throw const SupplementLabelFormatException(
        'Paste the ingredient list from the label first.',
      );
    }
    if (servingSize < 1) {
      throw const SupplementLabelFormatException(
        'The serving size must be at least one unit.',
      );
    }
    final key = await _keyStore.read(settings.provider);
    if (key == null || key.isEmpty) {
      throw StateError('Add a ${settings.provider.name} API key first.');
    }
    final capabilities = _capabilities.forModel(
      settings.provider,
      settings.model,
    );
    final response = await _clientFactory
        .create(settings.provider)
        .respond(
          key,
          ProviderRequest(
            model: settings.model,
            systemPrompt: systemPrompt,
            userPrompt: _prompt(
              text: text,
              servingSize: servingSize,
              stockUnit: stockUnit,
            ),
            contextJson: '',
            reasoningLevel:
                capabilities.reasoningLevels.contains(settings.reasoningLevel)
                ? settings.reasoningLevel
                : null,
            maxOutputTokens: 4000,
            requireJson: true,
          ),
        );
    return decodeLabel(response.text, servingSize: servingSize);
  }

  String _prompt({
    required String text,
    required int servingSize,
    required String stockUnit,
  }) =>
      '''
Read this supplement label and list every ingredient it states, with the
amount exactly as printed — per serving, not per $stockUnit. Do not divide,
convert, or round anything; the amounts are divided by the serving size
afterwards.

The person entered a serving size of $servingSize $stockUnit(s). Report the
serving size the label itself states in "detected_serving_size" so a mismatch
can be caught. If the label does not state one, use null.

Label text:
$text

Answer with a JSON object only:
{
  "detected_serving_size": <integer number of $stockUnit(s) per serving, or null>,
  "ingredients": [
    {"name": "<ingredient name, without brand names or trademark symbols>",
     "amount": <number as printed per serving, or null if none is printed>,
     "unit": "<unit as printed, for example mg, µg, g, IU>"}
  ],
  "warnings": ["<anything ambiguous or unreadable, one short sentence each>"]
}

Rules:
- Copy only what the label states. Never estimate a missing amount.
- When an ingredient shows two units, for example "26 µg (1040 IU)", use the
  first and note the second in warnings.
- Omit non-nutritive fillers, capsule shell, and anti-caking agents.
- Return an empty ingredients array rather than inventing rows.
''';

  /// Decodes a model response into reviewable rows.
  ///
  /// The division by serving size happens here rather than in the prompt: a
  /// model that slips an arithmetic step would otherwise silently store a dose
  /// several times too high, and there is no way to see that in the result.
  ParsedSupplementLabel decodeLabel(
    String responseText, {
    required int servingSize,
  }) {
    if (servingSize < 1) {
      throw const SupplementLabelFormatException(
        'The serving size must be at least one unit.',
      );
    }
    final decoded = _decodeObject(responseText);
    final rawIngredients = decoded['ingredients'];
    if (rawIngredients is! List) {
      throw const SupplementLabelFormatException(
        'The response did not contain an ingredients list.',
      );
    }

    final warnings = <String>[
      for (final warning in _asList(decoded['warnings']))
        if (warning.trim().isNotEmpty) warning.trim(),
    ];
    final ingredients = <ParsedLabelIngredient>[];
    for (final raw in rawIngredients) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final unit = raw['unit']?.toString().trim() ?? '';
      final perServing = _asDouble(raw['amount']);
      if (raw['amount'] != null && perServing == null) {
        warnings.add('Could not read the amount for $name.');
        ingredients.add(
          ParsedLabelIngredient(name: name, amount: null, unit: unit),
        );
        continue;
      }
      final perUnit = perServing == null ? null : perServing / servingSize;
      if (perUnit != null && !perUnit.isFinite) {
        warnings.add('Skipped an unusable amount for $name.');
        continue;
      }
      ingredients.add(
        ParsedLabelIngredient(name: name, amount: perUnit, unit: unit),
      );
    }

    return ParsedSupplementLabel(
      ingredients: ingredients,
      servingSize: servingSize,
      detectedServingSize: _asPositiveInt(decoded['detected_serving_size']),
      warnings: warnings,
    );
  }

  Map<String, Object?> _decodeObject(String text) {
    var candidate = text.trim();
    if (candidate.startsWith('```')) {
      candidate = candidate
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    try {
      final value = jsonDecode(candidate);
      if (value is Map) return Map<String, Object?>.from(value);
      // A bare array is a common shape for this request; accept it rather than
      // making a person re-run a paid call over a wrapper key.
      if (value is List) return {'ingredients': value};
    } on FormatException {
      final start = candidate.indexOf('{');
      final end = candidate.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          final value = jsonDecode(candidate.substring(start, end + 1));
          if (value is Map) return Map<String, Object?>.from(value);
        } on FormatException {
          // Fall through to the consistent error below.
        }
      }
    }
    throw const SupplementLabelFormatException(
      'The response was not valid JSON.',
    );
  }

  List<String> _asList(Object? value) =>
      value is List ? value.map((item) => '$item').toList() : const [];

  double? _asDouble(Object? value) {
    if (value is num) return value.isFinite ? value.toDouble() : null;
    final text = value?.toString().trim().replaceAll(',', '.');
    if (text == null || text.isEmpty) return null;
    final parsed = double.tryParse(text);
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  int? _asPositiveInt(Object? value) {
    final parsed = _asDouble(value);
    if (parsed == null) return null;
    final rounded = parsed.round();
    return rounded >= 1 ? rounded : null;
  }
}
