import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('OneDrive storage modes', () {
    test(
      'use the dedicated SuperHealth app identity and mode-specific scopes',
      () {
        expect(
          OneDriveService.clientId,
          '5d14b872-c492-422b-ac7f-e7f877f8a6ed',
        );
        expect(
          OneDriveService.scopeFor(OneDriveStorageMode.appFolder),
          'offline_access Files.ReadWrite.AppFolder',
        );
        expect(
          OneDriveService.scopeFor(OneDriveStorageMode.sharedFolder),
          'offline_access Files.ReadWrite',
        );
      },
    );

    test('reads an owned folder from a Graph drive item', () {
      final folder = OneDriveFolder.tryFromGraphItem({
        'id': 'owned-item',
        'name': 'Family Health',
        'webUrl': 'https://example.test/owned',
        'folder': <String, dynamic>{},
        'parentReference': {'driveId': 'owner-drive'},
      });

      expect(folder, isNotNull);
      expect(folder!.driveId, 'owner-drive');
      expect(folder.itemId, 'owned-item');
      expect(folder.name, 'Family Health');
      expect(folder.isShared, isFalse);
    });

    test('resolves a shared remote folder to its owner drive and item', () {
      final folder = OneDriveFolder.tryFromGraphItem({
        'remoteItem': {
          'id': 'shared-item',
          'name': 'Shared Health',
          'webUrl': 'https://example.test/shared',
          'folder': <String, dynamic>{},
          'parentReference': {'driveId': 'shared-owner-drive'},
        },
      }, sharedEndpoint: true);

      expect(folder, isNotNull);
      expect(folder!.driveId, 'shared-owner-drive');
      expect(folder.itemId, 'shared-item');
      expect(folder.name, 'Shared Health');
      expect(folder.isShared, isTrue);
    });

    test('ignores files when building the folder picker', () {
      final folder = OneDriveFolder.tryFromGraphItem({
        'id': 'file-item',
        'name': 'not-a-folder.json',
        'parentReference': {'driveId': 'drive'},
        'file': {'mimeType': 'application/json'},
      });

      expect(folder, isNull);
    });

    test(
      'paginates both endpoints, deduplicates folders, and sorts shared first',
      () async {
        final dio = Dio();
        final requestedUris = <Uri>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestedUris.add(options.uri);
              final endpoint = options.uri.path;
              final page = options.uri.queryParameters['page'];
              Map<String, dynamic> data;
              if (endpoint.endsWith('/sharedWithMe') && page == null) {
                data = {
                  'value': [_sharedFolder('shared-a', 'Alpha')],
                  '@odata.nextLink':
                      'https://graph.microsoft.com/v1.0/me/drive/sharedWithMe?page=shared-2',
                };
              } else if (endpoint.endsWith('/sharedWithMe') &&
                  page == 'shared-2') {
                data = {
                  'value': [
                    _sharedFolder('shared-a', 'Alpha'),
                    _sharedFolder('shared-b', 'Bravo'),
                  ],
                };
              } else if (endpoint.endsWith('/root/children') && page == null) {
                data = {
                  'value': [_ownedFolder('owned-a', 'Zulu')],
                  '@odata.nextLink': '/me/drive/root/children?page=owned-2',
                };
              } else if (endpoint.endsWith('/root/children') &&
                  page == 'owned-2') {
                data = {
                  'value': [_ownedFolder('owned-b', 'Charlie')],
                };
              } else {
                throw StateError('Unexpected Graph request: ${options.uri}');
              }
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: data,
                ),
              );
            },
          ),
        );

        final folders = await _FolderDiscoveryService(
          dio,
        ).listAvailableFolders();

        expect(requestedUris, hasLength(4));
        expect(requestedUris.first.queryParameters['allowexternal'], 'true');
        expect(folders.map((folder) => folder.name), [
          'Alpha',
          'Bravo',
          'Charlie',
          'Zulu',
        ]);
        expect(folders.where((folder) => folder.isShared), hasLength(2));
        expect(folders.map((folder) => folder.key).toSet(), hasLength(4));
      },
    );

    test(
      'falls back to owned folders when the first shared page fails',
      () async {
        final dio = Dio();
        final requestedUris = <Uri>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestedUris.add(options.uri);
              if (options.uri.path.endsWith('/sharedWithMe')) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                  ),
                );
                return;
              }
              if (options.uri.path.endsWith('/root/children')) {
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'value': [_ownedFolder('owned-a', 'Family Health')],
                    },
                  ),
                );
                return;
              }
              throw StateError('Unexpected Graph request: ${options.uri}');
            },
          ),
        );

        final folders = await _FolderDiscoveryService(
          dio,
        ).listAvailableFolders();

        expect(requestedUris, hasLength(2));
        expect(folders.map((folder) => folder.name), ['Family Health']);
      },
    );

    test(
      'fails rather than returning partial shared folders after a later page error',
      () async {
        final dio = Dio();
        final requestedUris = <Uri>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestedUris.add(options.uri);
              final page = options.uri.queryParameters['page'];
              if (options.uri.path.endsWith('/sharedWithMe') && page == null) {
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'value': [_sharedFolder('shared-a', 'Alpha')],
                      '@odata.nextLink': '/me/drive/sharedWithMe?page=shared-2',
                    },
                  ),
                );
                return;
              }
              if (options.uri.path.endsWith('/sharedWithMe') &&
                  page == 'shared-2') {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.connectionError,
                  ),
                );
                return;
              }
              throw StateError('Unexpected Graph request: ${options.uri}');
            },
          ),
        );

        await expectLater(
          _FolderDiscoveryService(dio).listAvailableFolders(),
          throwsA(
            isA<OneDriveFolderDiscoveryException>().having(
              (error) => error.message,
              'message',
              contains('partial response'),
            ),
          ),
        );
        expect(requestedUris, hasLength(2));
        expect(
          requestedUris.where((uri) => uri.path.endsWith('/root/children')),
          isEmpty,
        );
      },
    );

    test(
      'rejects a looping continuation instead of returning a partial list',
      () async {
        final dio = Dio();
        var requests = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests += 1;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'value': [_sharedFolder('shared-a', 'Alpha')],
                    '@odata.nextLink':
                        '/me/drive/sharedWithMe?allowexternal=true',
                  },
                ),
              );
            },
          ),
        );

        await expectLater(
          _FolderDiscoveryService(dio).listAvailableFolders(),
          throwsA(isA<OneDriveFolderDiscoveryException>()),
        );
        expect(requests, 1);
      },
    );

    test(
      'rejects an off-origin continuation without sending its bearer token',
      () async {
        final dio = Dio();
        final requestedUris = <Uri>[];
        final authorizationHeaders = <String?>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestedUris.add(options.uri);
              authorizationHeaders.add(
                options.headers['Authorization']?.toString(),
              );
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'value': [_sharedFolder('shared-a', 'Alpha')],
                    '@odata.nextLink': 'https://attacker.invalid/collect-token',
                  },
                ),
              );
            },
          ),
        );

        await expectLater(
          _FolderDiscoveryService(dio).listAvailableFolders(),
          throwsA(isA<OneDriveFolderDiscoveryException>()),
        );
        expect(requestedUris, hasLength(1));
        expect(requestedUris.single.host, 'graph.microsoft.com');
        expect(authorizationHeaders, ['Bearer test-token']);
      },
    );

    test('authoritative restore publish uses the remote ETag', () async {
      final dio = Dio();
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (options.method == 'GET' &&
                options.uri.path.endsWith('/special/approot')) {
              handler.resolve(
                Response<Object?>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{},
                ),
              );
              return;
            }
            if (options.method == 'GET' &&
                options.uri.path.endsWith('superhealth_snapshot.json')) {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'eTag': '"snapshot-v1"'},
                ),
              );
              return;
            }
            if (options.method == 'PUT') {
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'eTag': '"snapshot-v2"'},
                ),
              );
              return;
            }
            throw StateError('Unexpected Graph request: ${options.uri}');
          },
        ),
      );

      await _AppFolderService(dio).publishRestoredDataAuthoritatively();

      final upload = requests.singleWhere((item) => item.method == 'PUT');
      expect(upload.headers['If-Match'], '"snapshot-v1"');
      expect(upload.headers.containsKey('If-None-Match'), isFalse);
    });

    test(
      'authoritative restore publish creates only when no snapshot exists',
      () async {
        final dio = Dio();
        final requests = <RequestOptions>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              if (options.method == 'GET' &&
                  options.uri.path.endsWith('/special/approot')) {
                handler.resolve(
                  Response<Object?>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, dynamic>{},
                  ),
                );
                return;
              }
              if (options.method == 'GET' &&
                  options.uri.path.endsWith('superhealth_snapshot.json')) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response<Object?>(
                      requestOptions: options,
                      statusCode: 404,
                    ),
                    type: DioExceptionType.badResponse,
                  ),
                );
                return;
              }
              if (options.method == 'PUT') {
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'eTag': '"snapshot-v1"'},
                  ),
                );
                return;
              }
              throw StateError('Unexpected Graph request: ${options.uri}');
            },
          ),
        );

        await _AppFolderService(dio).publishRestoredDataAuthoritatively();

        final upload = requests.singleWhere((item) => item.method == 'PUT');
        expect(upload.headers['If-None-Match'], '*');
        expect(upload.headers.containsKey('If-Match'), isFalse);
      },
    );

    test(
      'ordinary sync prevents a first-snapshot creation race with If-None-Match',
      () async {
        final dio = Dio();
        final requests = <RequestOptions>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              if (options.method == 'GET' &&
                  options.uri.path.endsWith('/special/approot')) {
                handler.resolve(
                  Response<Object?>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, dynamic>{},
                  ),
                );
                return;
              }
              if (options.method == 'GET' &&
                  options.uri.path.endsWith('superhealth_snapshot.json')) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response<Object?>(
                      requestOptions: options,
                      statusCode: 404,
                    ),
                    type: DioExceptionType.badResponse,
                  ),
                );
                return;
              }
              if (options.method == 'PUT') {
                handler.resolve(
                  Response<Object?>(requestOptions: options, statusCode: 200),
                );
                return;
              }
              throw StateError('Unexpected Graph request: ${options.uri}');
            },
          ),
        );

        await _AppFolderService(dio).synchronize();

        final upload = requests.singleWhere((item) => item.method == 'PUT');
        expect(upload.headers['If-None-Match'], '*');
        expect(upload.headers.containsKey('If-Match'), isFalse);
      },
    );

    test(
      'ordinary sync fails closed when snapshot metadata lacks an ETag',
      () async {
        final dio = Dio();
        final requests = <RequestOptions>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              if (options.method == 'GET' &&
                  options.uri.path.endsWith('/special/approot')) {
                handler.resolve(
                  Response<Object?>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, dynamic>{},
                  ),
                );
                return;
              }
              if (options.method == 'GET' &&
                  options.uri.path.endsWith('superhealth_snapshot.json')) {
                handler.resolve(
                  Response<Map<String, dynamic>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: <String, dynamic>{},
                  ),
                );
                return;
              }
              throw StateError('Unexpected Graph request: ${options.uri}');
            },
          ),
        );

        await expectLater(
          _AppFolderService(dio).synchronize(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('without an ETag'),
            ),
          ),
        );

        expect(requests.where((item) => item.method == 'PUT'), isEmpty);
        expect(requests, hasLength(2));
      },
    );
  });
}

class _FolderDiscoveryService extends OneDriveService {
  _FolderDiscoveryService(Dio dio)
    : super(
        _snapshotService(),
        dio: dio,
        accessTokenProvider: () async => 'test-token',
      );

  @override
  Future<OneDriveStorageMode?> currentStorageMode() async =>
      OneDriveStorageMode.sharedFolder;
}

class _AppFolderService extends OneDriveService {
  _AppFolderService(Dio dio)
    : super(
        _snapshotService(),
        dio: dio,
        accessTokenProvider: () async => 'test-token',
      );

  @override
  Future<OneDriveStorageMode?> currentStorageMode() async =>
      OneDriveStorageMode.appFolder;
}

SnapshotService _snapshotService() {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  return SnapshotService(database, HealthRepository(database));
}

Map<String, dynamic> _sharedFolder(String id, String name) => {
  'remoteItem': {
    'id': id,
    'name': name,
    'folder': <String, dynamic>{},
    'parentReference': {'driveId': 'shared-drive'},
  },
};

Map<String, dynamic> _ownedFolder(String id, String name) => {
  'id': id,
  'name': name,
  'folder': <String, dynamic>{},
  'parentReference': {'driveId': 'owned-drive'},
};
