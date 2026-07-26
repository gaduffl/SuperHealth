// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../data/health_repository.dart';
import '../domain/entities.dart';
import '../sync/one_drive_service.dart';
import 'ai_models.dart';
import 'ai_settings.dart';
import 'api_key_store.dart';
import 'provider_clients.dart';

class ParsedMeasurementCandidate {
  const ParsedMeasurementCandidate({
    required this.reportedName,
    required this.value,
    required this.unit,
    required this.confidence,
    this.hasExtractionConfidence = true,
    this.biomarkerId,
    this.refLow,
    this.refHigh,
    this.page,
    this.rowText,
    this.notes = '',
  });

  final String? biomarkerId;
  final String reportedName;
  final double value;
  final String unit;
  final double? refLow;
  final double? refHigh;
  final int? page;
  final String? rowText;
  final double confidence;
  final bool hasExtractionConfidence;
  final String notes;

  ParsedMeasurementCandidate copyWith({
    String? biomarkerId,
    bool clearMapping = false,
    String? reportedName,
    double? value,
    String? unit,
    double? refLow,
    bool clearRefLow = false,
    double? refHigh,
    bool clearRefHigh = false,
    int? page,
    bool clearPage = false,
    String? rowText,
    double? confidence,
    bool? hasExtractionConfidence,
    String? notes,
  }) => ParsedMeasurementCandidate(
    biomarkerId: clearMapping ? null : biomarkerId ?? this.biomarkerId,
    reportedName: reportedName ?? this.reportedName,
    value: value ?? this.value,
    unit: unit ?? this.unit,
    refLow: clearRefLow ? null : refLow ?? this.refLow,
    refHigh: clearRefHigh ? null : refHigh ?? this.refHigh,
    page: clearPage ? null : page ?? this.page,
    rowText: rowText ?? this.rowText,
    confidence: confidence ?? this.confidence,
    hasExtractionConfidence:
        hasExtractionConfidence ?? this.hasExtractionConfidence,
    notes: notes ?? this.notes,
  );
}

class ParsedLabReport {
  const ParsedLabReport({
    required this.profileId,
    required this.fileName,
    required this.pdfBytes,
    required this.sha256,
    required this.provider,
    required this.model,
    required this.measurements,
    required this.warnings,
    required this.errors,
    this.labName,
    this.reportDate,
  });

  final String profileId;
  final String fileName;
  final Uint8List pdfBytes;
  final String sha256;
  final AiProvider provider;
  final String model;
  final String? labName;
  final DateTime? reportDate;
  final List<ParsedMeasurementCandidate> measurements;
  final List<String> warnings;
  final List<String> errors;

  ParsedLabReport copyWith({
    DateTime? reportDate,
    String? labName,
    List<ParsedMeasurementCandidate>? measurements,
  }) => ParsedLabReport(
    profileId: profileId,
    fileName: fileName,
    pdfBytes: pdfBytes,
    sha256: sha256,
    provider: provider,
    model: model,
    labName: labName ?? this.labName,
    reportDate: reportDate ?? this.reportDate,
    measurements: measurements ?? this.measurements,
    warnings: warnings,
    errors: errors,
  );
}

class DocumentSaveResult {
  const DocumentSaveResult({required this.document, this.cloudWarning});

  final HealthDocument document;
  final String? cloudWarning;
}

class DocumentParsingService {
  DocumentParsingService({
    required HealthRepository repository,
    required ApiKeyStore keyStore,
    required OneDriveService oneDriveService,
    Dio? dio,
    ProviderCapabilityRegistry? capabilities,
  }) : _repository = repository,
       _keyStore = keyStore,
       _oneDriveService = oneDriveService,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(minutes: 3),
               receiveTimeout: const Duration(minutes: 10),
             ),
           ),
       _capabilities = capabilities ?? ProviderCapabilityRegistry();

  final HealthRepository _repository;
  final ApiKeyStore _keyStore;
  final OneDriveService _oneDriveService;
  final Dio _dio;
  final ProviderCapabilityRegistry _capabilities;

  static const _maxPdfBytes = 32 * 1024 * 1024;

  Future<ParsedLabReport> parse({
    required String profileId,
    required String fileName,
    required Uint8List pdfBytes,
    required AiTaskSettings settings,
  }) async {
    if (pdfBytes.isEmpty) throw ArgumentError('The selected PDF is empty.');
    if (pdfBytes.length > _maxPdfBytes) {
      throw StateError(
        'PDFs larger than 32 MB are not accepted for direct parsing.',
      );
    }
    if (!_looksLikePdf(pdfBytes)) {
      throw const FormatException('The selected file is not a PDF.');
    }
    final hash = sha256.convert(pdfBytes).toString();
    final duplicate = await _repository.documentByHash(profileId, hash);
    if (duplicate != null) {
      throw StateError(
        'This exact PDF is already saved as ${duplicate.fileName}.',
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
    if (settings.reasoningLevel != null &&
        !capabilities.reasoningLevels.contains(settings.reasoningLevel)) {
      throw StateError(
        'The selected reasoning level is not supported by this model.',
      );
    }
    final catalog = await _repository.biomarkers();
    final catalogJson = jsonEncode([
      for (final biomarker in catalog)
        {
          'id': biomarker.id,
          'canonical_name': biomarker.canonicalName,
          'display_name': biomarker.displayName,
          'synonyms': biomarker.synonyms,
          'unit_hint': biomarker.defaultUnit,
        },
    ]);
    final prompt = _parserPrompt
        .replaceAll('{{BIOMARKER_CATALOG_JSON}}', catalogJson)
        .replaceAll('{{FILE_NAME}}', fileName)
        .replaceAll('{{SHA256}}', hash);

    final responseText = await switch (settings.provider) {
      AiProvider.openai => _parseOpenAi(
        key,
        settings,
        fileName,
        pdfBytes,
        prompt,
      ),
      AiProvider.anthropic => _parseAnthropic(key, settings, pdfBytes, prompt),
      AiProvider.gemini => _parseGemini(key, settings, pdfBytes, prompt),
    };
    return _decodeReport(
      responseText,
      profileId: profileId,
      fileName: fileName,
      pdfBytes: pdfBytes,
      hash: hash,
      settings: settings,
      catalog: catalog,
    );
  }

  Future<DocumentSaveResult> saveAfterExplicitReview({
    required ParsedLabReport report,
    required List<ParsedMeasurementCandidate> reviewedMeasurements,
    required DateTime reportDate,
    required String reportComment,
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      throw StateError('Explicit document approval is required.');
    }
    if (reviewedMeasurements.isEmpty) {
      throw StateError('At least one reviewed measurement is required.');
    }
    if (report.errors.isNotEmpty) {
      throw StateError('Resolve the parser errors before saving this report.');
    }
    final duplicate = await _repository.documentByHash(
      report.profileId,
      report.sha256,
    );
    if (duplicate != null) {
      throw StateError('This PDF was saved while the review was open.');
    }

    final existingCatalog = await _repository.biomarkers();
    final byId = {for (final item in existingCatalog) item.id: item};
    final byCanonical = {
      for (final item in existingCatalog) item.canonicalName: item,
    };
    final newBiomarkers = <Biomarker>[];
    final now = DateTime.now();
    final earliestReportDate = DateTime(1900);
    final latestReportDate = DateTime(now.year, now.month, now.day);
    final normalizedReportDate = DateTime(
      reportDate.year,
      reportDate.month,
      reportDate.day,
    );
    if (normalizedReportDate.isBefore(earliestReportDate) ||
        normalizedReportDate.isAfter(latestReportDate)) {
      throw ArgumentError(
        'The report date must be between 1900-01-01 and today.',
      );
    }
    final documentId = _repository.newId();
    final measurements = <Measurement>[];
    for (final candidate in reviewedMeasurements) {
      _validateReviewedCandidate(candidate, byId);
      Biomarker? biomarker = byId[candidate.biomarkerId];
      if (biomarker == null) {
        var canonical = HealthRepository.normalizeName(candidate.reportedName);
        if (canonical.isEmpty) canonical = 'temporary_${_repository.newId()}';
        biomarker = byCanonical[canonical];
        if (biomarker == null) {
          biomarker = Biomarker(
            id: _repository.newId(),
            canonicalName: canonical,
            displayName: candidate.reportedName,
            defaultUnit: candidate.unit,
            description:
                'Temporary biomarker created during reviewed PDF import.',
            isTemporary: true,
            createdAt: now,
            updatedAt: now,
          );
          newBiomarkers.add(biomarker);
          byCanonical[canonical] = biomarker;
          byId[biomarker.id] = biomarker;
        }
      }
      measurements.add(
        Measurement(
          id: _repository.newId(),
          profileId: report.profileId,
          biomarkerId: biomarker.id,
          documentId: documentId,
          takenAt: normalizedReportDate,
          value: candidate.value,
          unit: candidate.unit,
          labRefLow: candidate.refLow,
          labRefHigh: candidate.refHigh,
          page: candidate.page,
          rowText: candidate.rowText,
          extractionConfidence: candidate.hasExtractionConfidence
              ? candidate.confidence
              : null,
          notes: candidate.notes,
          flags:
              candidate.hasExtractionConfidence && candidate.confidence < 0.85
              ? const ['low_confidence']
              : const [],
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final base = await getApplicationDocumentsDirectory();
    final directory = Directory(
      path.join(base.path, 'documents', report.profileId),
    );
    await directory.create(recursive: true);
    final localFile = File(path.join(directory.path, '${report.sha256}.pdf'));
    await localFile.writeAsBytes(report.pdfBytes, flush: true);

    String? oneDriveItemId;
    String? cloudWarning;
    if (await _oneDriveService.isSignedIn()) {
      try {
        final uploaded = await _oneDriveService.uploadDocument(
          profileId: report.profileId,
          file: localFile,
          fileName: '${report.sha256}.pdf',
        );
        oneDriveItemId = uploaded['id']?.toString();
      } on Object catch (error) {
        cloudWarning = 'Saved locally, but OneDrive upload failed: $error';
      }
    }

    final document = HealthDocument(
      id: documentId,
      profileId: report.profileId,
      fileName: path.basename(report.fileName),
      sha256: report.sha256,
      localPath: localFile.path,
      oneDriveItemId: oneDriveItemId,
      documentDate: normalizedReportDate,
      parsedAt: now,
      parserProvider: report.provider.name,
      parserModel: report.model,
      labName: report.labName,
      reportComment: reportComment.trim(),
      warnings: [...report.warnings, ?cloudWarning],
      errors: report.errors,
      createdAt: now,
      updatedAt: now,
    );
    try {
      await _repository.saveDocumentBundle(
        document: document,
        newBiomarkers: newBiomarkers,
        measurements: measurements,
      );
    } on Object {
      if (await localFile.exists()) await localFile.delete();
      rethrow;
    }
    return DocumentSaveResult(document: document, cloudWarning: cloudWarning);
  }

  void _validateReviewedCandidate(
    ParsedMeasurementCandidate candidate,
    Map<String, Biomarker> biomarkersById,
  ) {
    if (candidate.reportedName.trim().isEmpty) {
      throw ArgumentError('Every measurement needs a reported name.');
    }
    if (candidate.unit.trim().isEmpty) {
      throw ArgumentError(
        '${candidate.reportedName}: the reported unit is required.',
      );
    }
    if (!candidate.value.isFinite) {
      throw ArgumentError(
        '${candidate.reportedName}: the value must be a finite number.',
      );
    }
    if (candidate.refLow?.isFinite == false ||
        candidate.refHigh?.isFinite == false) {
      throw ArgumentError(
        '${candidate.reportedName}: reference bounds must be finite numbers.',
      );
    }
    if (candidate.refLow != null &&
        candidate.refHigh != null &&
        candidate.refLow! > candidate.refHigh!) {
      throw ArgumentError(
        '${candidate.reportedName}: the lower reference bound exceeds the upper bound.',
      );
    }
    if (candidate.page != null && candidate.page! < 1) {
      throw ArgumentError(
        '${candidate.reportedName}: the PDF page must be at least 1.',
      );
    }
    if (candidate.hasExtractionConfidence &&
        (!candidate.confidence.isFinite ||
            candidate.confidence < 0 ||
            candidate.confidence > 1)) {
      throw ArgumentError(
        '${candidate.reportedName}: extraction confidence must be between 0 and 1.',
      );
    }
    final biomarkerId = candidate.biomarkerId;
    if (biomarkerId != null && !biomarkersById.containsKey(biomarkerId)) {
      throw ArgumentError(
        '${candidate.reportedName}: the selected biomarker no longer exists.',
      );
    }
  }

  Future<String> _parseOpenAi(
    String key,
    AiTaskSettings settings,
    String fileName,
    Uint8List bytes,
    String prompt,
  ) async {
    String? fileId;
    try {
      final upload = await _retry(
        () => _dio.post<Map<String, dynamic>>(
          'https://api.openai.com/v1/files',
          data: FormData.fromMap({
            'purpose': 'user_data',
            'file': MultipartFile.fromBytes(
              bytes,
              filename: path.basename(fileName),
            ),
          }),
          options: Options(headers: {'Authorization': 'Bearer $key'}),
        ),
      );
      fileId = upload.data?['id']?.toString();
      if (fileId == null) {
        throw const AiProviderException('OpenAI file upload returned no ID.');
      }
      final response = await _retry(
        () => _dio.post<Map<String, dynamic>>(
          'https://api.openai.com/v1/responses',
          data: {
            'model': settings.model,
            'store': false,
            if (settings.reasoningLevel != null)
              'reasoning': {'effort': settings.reasoningLevel},
            'input': [
              {
                'role': 'user',
                'content': [
                  {'type': 'input_text', 'text': prompt},
                  {'type': 'input_file', 'file_id': fileId},
                ],
              },
            ],
            'max_output_tokens': 16384,
            'text': {
              'format': {'type': 'json_object'},
            },
          },
          options: Options(
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
            },
          ),
        ),
      );
      return _openAiText(response.data);
    } finally {
      if (fileId != null) {
        try {
          await _dio.delete<void>(
            'https://api.openai.com/v1/files/$fileId',
            options: Options(headers: {'Authorization': 'Bearer $key'}),
          );
        } on Object {
          // The parse result remains usable; provider-side expiration is the fallback.
        }
      }
    }
  }

  Future<String> _parseAnthropic(
    String key,
    AiTaskSettings settings,
    Uint8List bytes,
    String prompt,
  ) async {
    final response = await _retry(
      () => _dio.post<Map<String, dynamic>>(
        'https://api.anthropic.com/v1/messages',
        data: {
          'model': settings.model,
          'max_tokens': 16384,
          'system':
              'You are a precise lab-report extraction engine. Return only valid JSON.',
          if (settings.reasoningLevel != null) ...{
            'thinking': {'type': 'adaptive'},
            'output_config': {'effort': settings.reasoningLevel},
          },
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'document',
                  'source': {
                    'type': 'base64',
                    'media_type': 'application/pdf',
                    'data': base64Encode(bytes),
                  },
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
        },
        options: Options(
          headers: {
            'x-api-key': key,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
        ),
      ),
    );
    final content = response.data?['content'];
    if (content is List) {
      final text = content
          .whereType<Map>()
          .where((item) => item['type'] == 'text')
          .map((item) => item['text']?.toString() ?? '')
          .join('\n')
          .trim();
      if (text.isNotEmpty) return text;
    }
    throw const AiProviderException('Anthropic returned no parser output.');
  }

  Future<String> _parseGemini(
    String key,
    AiTaskSettings settings,
    Uint8List bytes,
    String prompt,
  ) async {
    final response = await _retry(
      () => _dio.post<Map<String, dynamic>>(
        'https://generativelanguage.googleapis.com/v1beta/interactions',
        data: {
          'model': settings.model,
          'store': false,
          'system_instruction':
              'You are a precise lab-report extraction engine. Return only valid JSON.',
          'input': [
            {
              'type': 'document',
              'data': base64Encode(bytes),
              'mime_type': 'application/pdf',
            },
            {'type': 'text', 'text': prompt},
          ],
          'generation_config': {
            'max_output_tokens': 16384,
            if (settings.reasoningLevel != null)
              'thinking_level': settings.reasoningLevel,
          },
        },
        options: Options(
          headers: {'x-goog-api-key': key, 'Content-Type': 'application/json'},
        ),
      ),
    );
    final steps = response.data?['steps'];
    final parts = <String>[];
    if (steps is List) {
      for (final step in steps.whereType<Map>()) {
        if (step['type'] != 'model_output') continue;
        final content = step['content'];
        if (content is String) {
          parts.add(content);
        } else if (content is List) {
          for (final item in content.whereType<Map>()) {
            if (item['text'] != null) parts.add(item['text'].toString());
          }
        }
      }
    }
    final text = parts.join('\n').trim();
    if (text.isEmpty) {
      throw const AiProviderException('Gemini returned no parser output.');
    }
    return text;
  }

  Future<Response<Map<String, dynamic>>> _retry(
    Future<Response<Map<String, dynamic>>> Function() action,
  ) async {
    DioException? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await action();
      } on DioException catch (error) {
        lastError = error;
        final status = error.response?.statusCode;
        final retryable =
            status == 408 ||
            status == 409 ||
            status == 429 ||
            (status != null && status >= 500);
        if (!retryable || attempt == 2) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    throw lastError ?? const AiProviderException('Provider request failed.');
  }

  String _openAiText(Map<String, dynamic>? data) {
    final output = data?['output'];
    final parts = <String>[];
    if (output is List) {
      for (final item in output.whereType<Map>()) {
        final content = item['content'];
        if (content is! List) continue;
        for (final block in content.whereType<Map>()) {
          if (block['text'] != null) parts.add(block['text'].toString());
        }
      }
    }
    final text = parts.join('\n').trim();
    if (text.isEmpty) {
      throw const AiProviderException('OpenAI returned no parser output.');
    }
    return text;
  }

  ParsedLabReport _decodeReport(
    String raw, {
    required String profileId,
    required String fileName,
    required Uint8List pdfBytes,
    required String hash,
    required AiTaskSettings settings,
    required List<Biomarker> catalog,
  }) {
    final decoded = _jsonObject(raw);
    final document = decoded['document'] is Map
        ? Map<String, Object?>.from(decoded['document'] as Map)
        : const <String, Object?>{};
    final warnings = _stringList(decoded['warnings']);
    final errors = _stringList(decoded['errors']);
    final byId = {for (final item in catalog) item.id: item};
    final byCanonical = {for (final item in catalog) item.canonicalName: item};
    final candidates = <ParsedMeasurementCandidate>[];
    final rows = decoded['measurements'];
    if (rows is! List) {
      errors.add('The parser response did not contain a measurements array.');
    }
    for (final value in rows is List ? rows.whereType<Map>() : const <Map>[]) {
      final row = Map<String, Object?>.from(value);
      final reportedName = row['reported_name']?.toString().trim() ?? '';
      final parsedValue = _number(row['value']);
      final unit = row['unit']?.toString().trim() ?? '';
      if (reportedName.isEmpty || parsedValue == null || unit.isEmpty) {
        warnings.add(
          'Skipped an incomplete measurement row: ${jsonEncode(row)}',
        );
        continue;
      }
      final requestedId = row['biomarker_id']?.toString();
      final mapped =
          byId[requestedId] ??
          byCanonical[HealthRepository.normalizeName(requestedId ?? '')] ??
          byCanonical[HealthRepository.normalizeName(reportedName)];
      final parsedConfidence = _number(row['confidence']);
      final hasExtractionConfidence =
          parsedConfidence != null &&
          parsedConfidence >= 0 &&
          parsedConfidence <= 1;
      if (row.containsKey('confidence') && !hasExtractionConfidence) {
        warnings.add(
          'Ignored an invalid extraction confidence for $reportedName.',
        );
      }
      final confidence = hasExtractionConfidence ? parsedConfidence : 0.0;
      var refLow = _optionalNumber(row, 'ref_low', reportedName, warnings);
      var refHigh = _optionalNumber(row, 'ref_high', reportedName, warnings);
      if (refLow != null && refHigh != null && refLow > refHigh) {
        refLow = null;
        refHigh = null;
        warnings.add(
          'Ignored unordered lab reference bounds for $reportedName.',
        );
      }
      var page = _optionalNumber(row, 'page', reportedName, warnings)?.toInt();
      if (page != null && page < 1) {
        page = null;
        warnings.add('Ignored a measurement page below 1 for $reportedName.');
      }
      candidates.add(
        ParsedMeasurementCandidate(
          biomarkerId: mapped?.id,
          reportedName: reportedName,
          value: parsedValue,
          unit: unit,
          refLow: refLow,
          refHigh: refHigh,
          page: page,
          rowText: row['row_text']?.toString(),
          confidence: confidence,
          hasExtractionConfidence: hasExtractionConfidence,
          notes: row['notes']?.toString() ?? '',
        ),
      );
    }
    if (candidates.isEmpty) {
      errors.add('No complete measurement rows were extracted.');
    }
    return ParsedLabReport(
      profileId: profileId,
      fileName: fileName,
      pdfBytes: pdfBytes,
      sha256: hash,
      provider: settings.provider,
      model: settings.model,
      labName: document['lab_name']?.toString(),
      reportDate: DateTime.tryParse(document['report_date']?.toString() ?? ''),
      measurements: candidates,
      warnings: warnings.toSet().toList(),
      errors: errors.toSet().toList(),
    );
  }

  Map<String, Object?> _jsonObject(String raw) {
    var value = raw.trim();
    value = value
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on FormatException {
      final start = value.indexOf('{');
      final end = value.lastIndexOf('}');
      if (start >= 0 && end > start) {
        final decoded = jsonDecode(value.substring(start, end + 1));
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      }
    }
    throw const FormatException('The parser did not return a JSON object.');
  }

  List<String> _stringList(Object? value) => value is List
      ? value.map((item) => item.toString()).toList()
      : <String>[];

  double? _number(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : value == null
        ? null
        : double.tryParse(value.toString().trim().replaceAll(',', '.'));
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  double? _optionalNumber(
    Map<String, Object?> row,
    String key,
    String reportedName,
    List<String> warnings,
  ) {
    if (!row.containsKey(key)) return null;
    final value = _number(row[key]);
    if (value == null && row[key] != null) {
      warnings.add('Ignored an invalid $key for $reportedName.');
    }
    return value;
  }

  bool _looksLikePdf(Uint8List bytes) =>
      bytes.length >= 5 &&
      ascii.decode(bytes.sublist(0, 5), allowInvalid: true) == '%PDF-';

  static const _parserPrompt = '''
You are a precise lab-report extraction engine. Read the attached PDF and return a single JSON object that matches EXACTLY the provided schema. Do not include extra keys or prose.

MAPPING RULES
- Only map to IDs that exist in the provided catalog. If unsure, leave biomarker_id empty and set a low confidence.
- Preserve the printed German or English reported name.

NUMBERS AND UNITS
- Parse German or English decimal separators. Convert commas to decimal points and strip thousands separators.
- Keep the unit string exactly as printed. Do not infer units, convert values, or calculate derived markers.
- Extract lab reference ranges exactly as printed.

DATES
- report_date: prefer sample collection date; otherwise use report date. Format YYYY-MM-DD.

OUTPUT
Return keys: document, measurements, warnings, errors.
- document: {lab_name, report_date, file_name:"{{FILE_NAME}}", sha256:"{{SHA256}}", patient:{sex,dob,age_years}, report_comment:""}
- measurements: [{biomarker_id, reported_name, value, unit, ref_low, ref_high, page, row_text, confidence, notes:""}]
- warnings: ambiguous mappings, missing units, unreadable text, or derived calculations detected.
- errors: only hard failures preventing reliable extraction.
- confidence is 0.00 to 1.00. Include page numbers and raw row text when possible. Include every panel row.

BIOMARKER CATALOG
{{BIOMARKER_CATALOG_JSON}}
''';
}
