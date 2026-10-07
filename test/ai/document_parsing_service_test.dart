import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'review saves IGeL only on chosen candidates and retains confidence flags',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Alex');
      final snapshot = SnapshotService(database, repository);
      final service = DocumentParsingService(
        repository: repository,
        keyStore: _KeyStore(),
        oneDriveService: _SignedOutOneDrive(snapshot),
      );
      final directory = await Directory.systemTemp.createTemp('igel-import-');
      addTearDown(() => directory.delete(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final report = ParsedLabReport(
        profileId: profile.id,
        fileName: 'fixture.pdf',
        pdfBytes: Uint8List.fromList(utf8.encode('%PDF-1.4\n%%EOF')),
        sha256: 'fixture-hash',
        provider: AiProvider.openai,
        model: 'fixture-model',
        warnings: const [],
        errors: const [],
        measurements: const [
          ParsedMeasurementCandidate(
            reportedName: 'Marker A',
            value: 1,
            unit: 'mg/dL',
            confidence: 0.7,
          ),
          ParsedMeasurementCandidate(
            reportedName: 'Marker B',
            value: 2,
            unit: 'mg/dL',
            confidence: 0.9,
          ),
        ],
      );
      final reviewed = [
        report.measurements.first.copyWith(isSelfPaid: true),
        report.measurements.last,
      ];
      await expectLater(
        service.saveAfterExplicitReview(
          report: report,
          reviewedMeasurements: reviewed,
          reportDate: DateTime(2026, 1, 1),
          reportComment: '',
          userConfirmed: false,
        ),
        throwsStateError,
      );
      expect(await repository.reportedMeasurements(profile.id), isEmpty);
      await service.saveAfterExplicitReview(
        report: report,
        reviewedMeasurements: reviewed,
        reportDate: DateTime(2026, 1, 1),
        reportComment: '',
        userConfirmed: true,
      );
      final rows = await repository.reportedMeasurements(profile.id);
      expect(rows.singleWhere((row) => row.value == 1).isSelfPaid, isTrue);
      expect(
        rows.singleWhere((row) => row.value == 1).flags,
        contains('low_confidence'),
      );
      expect(rows.singleWhere((row) => row.value == 2).isSelfPaid, isFalse);
    },
  );

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
        isSelfPaid: true,
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
      expect(edited.isSelfPaid, isTrue);
      expect(edited.copyWith(isSelfPaid: false).isSelfPaid, isFalse);
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
                                  'is_self_paid': true,
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
      expect(candidate.isSelfPaid, isFalse);
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

class _SignedOutOneDrive extends OneDriveService {
  _SignedOutOneDrive(super.snapshotService);

  @override
  Future<bool> isSignedIn() async => false;
}
