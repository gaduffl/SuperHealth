import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/document_parsing_service.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';

void main() {
  test(
    'reviewed parser candidates can replace or clear every editable field',
    () {
      const candidate = ParsedMeasurementCandidate(
        biomarkerId: 'bio-1',
        reportedName: 'Original',
        value: 1,
        unit: 'mg/dL',
        refLow: 0.5,
        refHigh: 2,
        page: 3,
        rowText: 'Original source row',
        confidence: 0.7,
        notes: 'Parser note',
      );

      final edited = candidate.copyWith(
        clearMapping: true,
        reportedName: 'Reviewed',
        value: -1.25,
        unit: 'mmol/L',
        clearRefLow: true,
        refHigh: 4,
        clearPage: true,
        notes: 'User checked this row',
      );

      expect(edited.biomarkerId, isNull);
      expect(edited.reportedName, 'Reviewed');
      expect(edited.value, -1.25);
      expect(edited.unit, 'mmol/L');
      expect(edited.refLow, isNull);
      expect(edited.refHigh, 4);
      expect(edited.page, isNull);
      expect(edited.rowText, 'Original source row');
      expect(edited.confidence, 0.7);
      expect(edited.notes, 'User checked this row');
    },
  );

  test(
    'parser excludes non-finite values and omits optional non-finite fields',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Me');
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final response = options.path.endsWith('/v1/files')
                ? {'id': 'file-1'}
                : options.path.endsWith('/v1/responses')
                ? {
                    'output': [
                      {
                        'content': [
                          {
                            'text': jsonEncode({
                              'document': const {},
                              'warnings': const [],
                              'errors': const [],
                              'measurements': [
                                {
                                  'reported_name': 'ApoB',
                                  'value': '-4.5',
                                  'unit': 'mg/dL',
                                  'ref_low': 'NaN',
                                  'ref_high': 'Infinity',
                                  'page': '-Infinity',
                                  'confidence': 'NaN',
                                },
                                {
                                  'reported_name': 'Discard NaN',
                                  'value': 'NaN',
                                  'unit': 'mg/dL',
                                },
                                {
                                  'reported_name': 'Discard infinity',
                                  'value': 'Infinity',
                                  'unit': 'mg/dL',
                                },
                                {
                                  'reported_name': 'Unordered',
                                  'value': -3,
                                  'unit': 'mg/dL',
                                  'ref_low': 10,
                                  'ref_high': 5,
                                  'page': 0,
                                  'confidence': 2,
                                },
                              ],
                            }),
                          },
                        ],
                      },
                    ],
                  }
                : <String, Object?>{};
            handler.resolve(Response(requestOptions: options, data: response));
          },
        ),
      );
      final service = DocumentParsingService(
        repository: repository,
        keyStore: _KeyStore(),
        oneDriveService: OneDriveService(SnapshotService(database, repository)),
        dio: dio,
      );

      final report = await service.parse(
        profileId: profile.id,
        fileName: 'report.pdf',
        pdfBytes: Uint8List.fromList(utf8.encode('%PDF-1.4\n%%EOF')),
        settings: const AiTaskSettings(
          provider: AiProvider.openai,
          model: 'gpt-5.6',
        ),
      );

      expect(report.measurements, hasLength(2));
      final candidate = report.measurements.firstWhere(
        (item) => item.reportedName == 'ApoB',
      );
      expect(candidate.value, -4.5);
      expect(candidate.value.isFinite, isTrue);
      expect(candidate.refLow, isNull);
      expect(candidate.refHigh, isNull);
      expect(candidate.page, isNull);
      expect(candidate.hasExtractionConfidence, isFalse);
      final unordered = report.measurements.firstWhere(
        (item) => item.reportedName == 'Unordered',
      );
      expect(unordered.value, -3);
      expect(unordered.refLow, isNull);
      expect(unordered.refHigh, isNull);
      expect(unordered.page, isNull);
      expect(unordered.hasExtractionConfidence, isFalse);
      expect(
        report.warnings.join('\n'),
        contains('Skipped an incomplete measurement row'),
      );
      expect(report.warnings.join('\n'), contains('invalid ref_low'));
      expect(
        report.warnings.join('\n'),
        contains('invalid extraction confidence'),
      );
      expect(
        report.warnings.join('\n'),
        contains('unordered lab reference bounds'),
      );
      await database.close();
    },
  );
}

class _KeyStore extends ApiKeyStore {
  @override
  Future<String?> read(AiProvider provider) async => 'test-key';
}
