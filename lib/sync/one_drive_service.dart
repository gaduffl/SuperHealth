import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'snapshot_service.dart';

class DeviceCodeInfo {
  const DeviceCodeInfo({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.pollInterval,
    this.message,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final Duration pollInterval;
  final String? message;
}

class OneDriveSyncResult {
  const OneDriveSyncResult({
    required this.remoteFound,
    required this.appliedRows,
    required this.keptLocalRows,
    required this.conflicts,
    required this.uploadedBytes,
  });

  final bool remoteFound;
  final int appliedRows;
  final int keptLocalRows;
  final int conflicts;
  final int uploadedBytes;
}

class OneDriveLegacyFile {
  const OneDriveLegacyFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class OneDriveService {
  OneDriveService(
    this._snapshotService, {
    Dio? dio,
    FlutterSecureStorage? secureStorage,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 30),
               receiveTimeout: const Duration(minutes: 2),
             ),
           ),
       _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(aOptions: AndroidOptions());

  // Dedicated SuperHealth public-client registration and AppFolder scope.
  static const clientId = '5d14b872-c492-422b-ac7f-e7f877f8a6ed';
  static const _authority = 'https://login.microsoftonline.com/consumers';
  static const _graphBase = 'https://graph.microsoft.com/v1.0';
  static const _snapshotName = 'superhealth_snapshot.json';
  static const _scope = 'offline_access Files.ReadWrite.AppFolder';
  static const _simpleUploadLimit = 4 * 1024 * 1024;
  static const _chunkSize = 320 * 1024;

  static const _accessTokenKey = 'onedrive_access_token';
  static const _refreshTokenKey = 'onedrive_refresh_token';
  static const _expiresAtKey = 'onedrive_expires_at';
  static const _clientIdKey = 'onedrive_client_id';

  final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  final SnapshotService _snapshotService;

  Future<DeviceCodeInfo> startDeviceCodeSignIn() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_authority/oauth2/v2.0/devicecode',
      data: {'client_id': clientId, 'scope': _scope},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data!;
    return DeviceCodeInfo(
      deviceCode: '${data['device_code']}',
      userCode: '${data['user_code']}',
      verificationUri: Uri.parse(
        '${data['verification_uri'] ?? 'https://microsoft.com/devicelogin'}',
      ),
      expiresAt: DateTime.now().add(
        Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 900),
      ),
      pollInterval: Duration(seconds: (data['interval'] as num?)?.toInt() ?? 5),
      message: data['message']?.toString(),
    );
  }

  Future<bool> pollForSignIn(DeviceCodeInfo code) async {
    var interval = code.pollInterval;
    while (DateTime.now().isBefore(code.expiresAt)) {
      await Future<void>.delayed(interval);
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '$_authority/oauth2/v2.0/token',
          data: {
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            'client_id': clientId,
            'device_code': code.deviceCode,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        await _storeTokens(response.data!);
        return true;
      } on DioException catch (error) {
        final data = error.response?.data;
        final code = data is Map ? data['error']?.toString() : null;
        if (code == 'authorization_pending') continue;
        if (code == 'slow_down') {
          interval += const Duration(seconds: 5);
          continue;
        }
        if (code == 'authorization_declined' || code == 'expired_token') {
          return false;
        }
        rethrow;
      }
    }
    return false;
  }

  Future<bool> isSignedIn() async {
    final storedClientId = await _secureStorage.read(key: _clientIdKey);
    if (storedClientId != clientId) {
      await signOut();
      return false;
    }
    final refresh = await _secureStorage.read(key: _refreshTokenKey);
    if (refresh == null || refresh.isEmpty) return false;
    try {
      await _validAccessToken();
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> signOut() async {
    await Future.wait([
      _secureStorage.delete(key: _accessTokenKey),
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _expiresAtKey),
      _secureStorage.delete(key: _clientIdKey),
    ]);
  }

  Future<OneDriveSyncResult> synchronize() async {
    Map<String, dynamic>? metadata;
    Uint8List? remoteBytes;
    try {
      final response = await _graph<Map<String, dynamic>>(
        'GET',
        '/me/drive/special/approot:/$_snapshotName',
      );
      metadata = response.data;
      final content = await _graph<List<int>>(
        'GET',
        '/me/drive/special/approot:/$_snapshotName:/content',
        options: Options(responseType: ResponseType.bytes),
      );
      remoteBytes = Uint8List.fromList(content.data ?? const []);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
    }

    var merge = const SnapshotMergeResult(
      appliedRows: 0,
      keptLocalRows: 0,
      conflicts: 0,
    );
    if (remoteBytes != null && remoteBytes.isNotEmpty) {
      merge = await _snapshotService.mergeJson(utf8.decode(remoteBytes));
    }

    final localJson = await _snapshotService.buildSnapshotJson();
    final bytes = Uint8List.fromList(utf8.encode(localJson));
    final etag = metadata?['eTag']?.toString();
    await _graph<Object?>(
      'PUT',
      '/me/drive/special/approot:/$_snapshotName:/content',
      data: Stream.fromIterable([bytes]),
      options: Options(
        contentType: 'application/json',
        headers: etag == null ? null : {'If-Match': etag},
      ),
    );
    await _snapshotService.markCurrentAsSynchronized();

    return OneDriveSyncResult(
      remoteFound: remoteBytes != null,
      appliedRows: merge.appliedRows,
      keptLocalRows: merge.keptLocalRows,
      conflicts: merge.conflicts,
      uploadedBytes: bytes.length,
    );
  }

  /// Reads known exports from the pre-merge apps without modifying them.
  Future<List<OneDriveLegacyFile>> downloadLegacyFiles() async {
    const candidates = [
      'supplement_sync.json',
      'data/supplement_sync.json',
      'data/profiles.json',
      'data/biomarkers.json',
      'data/ranges.json',
      'data/biomarker_lists.json',
      'data/biomarker_list_entries.json',
      'data/user_overrides.json',
      'data/documents.json',
      'data/measurements.json',
    ];
    final result = <OneDriveLegacyFile>[];
    for (final candidate in candidates) {
      try {
        final response = await _graph<List<int>>(
          'GET',
          '/me/drive/special/approot:/${_encodeGraphPath(candidate)}:/content',
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = response.data;
        if (bytes != null && bytes.isNotEmpty) {
          result.add(
            OneDriveLegacyFile(
              name: candidate.split('/').last,
              bytes: Uint8List.fromList(bytes),
            ),
          );
        }
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> uploadApprovedFile({
    required String profileId,
    required String relativePath,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
  }) async {
    final safePath = _safeRelativePath(relativePath);
    final directory = 'Advisor Workspace/$profileId';
    await _ensureFolder(directory);
    final fullPath = '$directory/$safePath';
    await _ensureFolder(
      fullPath.contains('/')
          ? fullPath.substring(0, fullPath.lastIndexOf('/'))
          : directory,
    );
    return _uploadBytes(fullPath, bytes, contentType: contentType);
  }

  Future<void> deleteApprovedFile({
    required String profileId,
    required String relativePath,
  }) async {
    final safePath = _safeRelativePath(relativePath);
    final fullPath = 'Advisor Workspace/$profileId/$safePath';
    try {
      await _graph<void>(
        'DELETE',
        '/me/drive/special/approot:/${_encodeGraphPath(fullPath)}',
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadDocument({
    required String profileId,
    required File file,
    String? fileName,
    String contentType = 'application/pdf',
  }) async {
    final name = _safeRelativePath(fileName ?? file.uri.pathSegments.last);
    final directory = 'Documents/$profileId';
    await _ensureFolder(directory);
    return _uploadBytes(
      '$directory/$name',
      await file.readAsBytes(),
      contentType: contentType,
    );
  }

  Future<Map<String, dynamic>> _uploadBytes(
    String relativePath,
    Uint8List bytes, {
    required String contentType,
  }) async {
    final encodedPath = _encodeGraphPath(relativePath);
    if (bytes.length <= _simpleUploadLimit) {
      final response = await _graph<Map<String, dynamic>>(
        'PUT',
        '/me/drive/special/approot:/$encodedPath:/content',
        data: Stream.fromIterable([bytes]),
        options: Options(contentType: contentType),
      );
      return response.data ?? <String, dynamic>{};
    }

    final session = await _graph<Map<String, dynamic>>(
      'POST',
      '/me/drive/special/approot:/$encodedPath:/createUploadSession',
      data: {
        'item': {
          '@microsoft.graph.conflictBehavior': 'replace',
          'name': relativePath.split('/').last,
        },
      },
    );
    final uploadUrl = session.data?['uploadUrl']?.toString();
    if (uploadUrl == null) {
      throw StateError('OneDrive upload session missing URL');
    }

    Map<String, dynamic> result = {};
    for (var start = 0; start < bytes.length; start += _chunkSize) {
      final end = (start + _chunkSize).clamp(0, bytes.length);
      final response = await _dio.put<Map<String, dynamic>>(
        uploadUrl,
        data: Stream.fromIterable([bytes.sublist(start, end)]),
        options: Options(
          headers: {
            'Content-Length': end - start,
            'Content-Range': 'bytes $start-${end - 1}/${bytes.length}',
          },
        ),
      );
      if (response.data != null) result = response.data!;
    }
    return result;
  }

  Future<void> _ensureFolder(String relativePath) async {
    final segments = relativePath
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    var current = '';
    for (final segment in segments) {
      final parent = current;
      current = current.isEmpty ? segment : '$current/$segment';
      try {
        await _graph<Object?>(
          'GET',
          '/me/drive/special/approot:/${_encodeGraphPath(current)}',
        );
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
        final childrenPath = parent.isEmpty
            ? '/me/drive/special/approot/children'
            : '/me/drive/special/approot:/${_encodeGraphPath(parent)}:/children';
        await _graph<Object?>(
          'POST',
          childrenPath,
          data: {
            'name': segment,
            'folder': <String, dynamic>{},
            '@microsoft.graph.conflictBehavior': 'fail',
          },
        );
      }
    }
  }

  Future<Response<T>> _graph<T>(
    String method,
    String path, {
    Object? data,
    Options? options,
  }) async {
    final token = await _validAccessToken();
    final merged = (options ?? Options()).copyWith(
      method: method,
      headers: {...?options?.headers, 'Authorization': 'Bearer $token'},
    );
    return _dio.request<T>('$_graphBase$path', data: data, options: merged);
  }

  Future<String> _validAccessToken() async {
    final storedClientId = await _secureStorage.read(key: _clientIdKey);
    if (storedClientId != clientId) {
      await signOut();
      throw StateError('OneDrive must be reconnected for SuperHealth.');
    }
    final token = await _secureStorage.read(key: _accessTokenKey);
    final expiryRaw = await _secureStorage.read(key: _expiresAtKey);
    final expiry = DateTime.tryParse(expiryRaw ?? '');
    if (token != null &&
        expiry != null &&
        DateTime.now().isBefore(expiry.subtract(const Duration(minutes: 2)))) {
      return token;
    }
    final refresh = await _secureStorage.read(key: _refreshTokenKey);
    if (refresh == null || refresh.isEmpty) {
      throw StateError('OneDrive is not signed in');
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '$_authority/oauth2/v2.0/token',
      data: {
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
        'scope': _scope,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    await _storeTokens(response.data!);
    return '${response.data!['access_token']}';
  }

  Future<void> _storeTokens(Map<String, dynamic> data) async {
    final access = data['access_token']?.toString();
    if (access == null || access.isEmpty) {
      throw const FormatException(
        'Microsoft token response has no access token',
      );
    }
    final refresh = data['refresh_token']?.toString();
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    await _secureStorage.write(key: _clientIdKey, value: clientId);
    await _secureStorage.write(key: _accessTokenKey, value: access);
    if (refresh != null && refresh.isNotEmpty) {
      await _secureStorage.write(key: _refreshTokenKey, value: refresh);
    }
    await _secureStorage.write(
      key: _expiresAtKey,
      value: DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String(),
    );
  }

  String _safeRelativePath(String input) {
    final normalized = input.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList();
    if (segments.isEmpty || segments.any((segment) => segment == '..')) {
      throw const FormatException('Unsafe workspace path');
    }
    return segments.join('/');
  }

  String _encodeGraphPath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');
}
