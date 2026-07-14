import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'snapshot_service.dart';

enum OneDriveStorageMode { appFolder, sharedFolder }

class OneDriveFolder {
  const OneDriveFolder({
    required this.driveId,
    required this.itemId,
    required this.name,
    required this.isShared,
    this.webUrl,
  });

  final String driveId;
  final String itemId;
  final String name;
  final bool isShared;
  final String? webUrl;

  String get key => '$driveId:$itemId';

  static OneDriveFolder? tryFromGraphItem(
    Map<String, dynamic> item, {
    bool sharedEndpoint = false,
  }) {
    final remoteNode = item['remoteItem'];
    final remote = remoteNode is Map
        ? Map<String, dynamic>.from(remoteNode)
        : null;
    final node = remote ?? item;
    if (node['folder'] is! Map) return null;
    final parentNode = node['parentReference'];
    final parent = parentNode is Map
        ? Map<String, dynamic>.from(parentNode)
        : const <String, dynamic>{};
    final driveId = parent['driveId']?.toString();
    final itemId = node['id']?.toString();
    final name = node['name']?.toString();
    if (driveId == null ||
        driveId.isEmpty ||
        itemId == null ||
        itemId.isEmpty ||
        name == null ||
        name.isEmpty) {
      return null;
    }
    return OneDriveFolder(
      driveId: driveId,
      itemId: itemId,
      name: name,
      isShared: sharedEndpoint || remote != null,
      webUrl: node['webUrl']?.toString() ?? item['webUrl']?.toString(),
    );
  }
}

class DeviceCodeInfo {
  const DeviceCodeInfo({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresAt,
    required this.pollInterval,
    required this.storageMode,
    this.message,
  });

  final String deviceCode;
  final String userCode;
  final Uri verificationUri;
  final DateTime expiresAt;
  final Duration pollInterval;
  final OneDriveStorageMode storageMode;
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

  // Dedicated SuperHealth public-client registration.
  static const clientId = '5d14b872-c492-422b-ac7f-e7f877f8a6ed';
  static const sharedSubfolderName = 'SuperHealth';
  static const _authority = 'https://login.microsoftonline.com/consumers';
  static const _graphBase = 'https://graph.microsoft.com/v1.0';
  static const _snapshotName = 'superhealth_snapshot.json';
  static const _appFolderScope =
      'offline_access Files.ReadWrite.AppFolder';
  static const _sharedFolderScope = 'offline_access Files.ReadWrite';
  static const _simpleUploadLimit = 4 * 1024 * 1024;
  static const _chunkSize = 320 * 1024;

  static const _accessTokenKey = 'onedrive_access_token';
  static const _refreshTokenKey = 'onedrive_refresh_token';
  static const _expiresAtKey = 'onedrive_expires_at';
  static const _clientIdKey = 'onedrive_client_id';
  static const _storageModeKey = 'onedrive_storage_mode';
  static const _folderDriveIdKey = 'onedrive_folder_drive_id';
  static const _folderItemIdKey = 'onedrive_folder_item_id';
  static const _folderNameKey = 'onedrive_folder_name';
  static const _folderWebUrlKey = 'onedrive_folder_web_url';
  static const _folderSharedKey = 'onedrive_folder_is_shared';

  final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  final SnapshotService _snapshotService;

  static String scopeFor(OneDriveStorageMode mode) =>
      mode == OneDriveStorageMode.appFolder
      ? _appFolderScope
      : _sharedFolderScope;

  Future<DeviceCodeInfo> startDeviceCodeSignIn(
    OneDriveStorageMode storageMode,
  ) async {
    await signOut();
    final response = await _dio.post<Map<String, dynamic>>(
      '$_authority/oauth2/v2.0/devicecode',
      data: {'client_id': clientId, 'scope': scopeFor(storageMode)},
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
      storageMode: storageMode,
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
        await _storeTokens(response.data!, code.storageMode);
        return true;
      } on DioException catch (error) {
        final data = error.response?.data;
        final errorCode = data is Map ? data['error']?.toString() : null;
        if (errorCode == 'authorization_pending') continue;
        if (errorCode == 'slow_down') {
          interval += const Duration(seconds: 5);
          continue;
        }
        if (errorCode == 'authorization_declined' ||
            errorCode == 'expired_token') {
          return false;
        }
        rethrow;
      }
    }
    return false;
  }

  Future<OneDriveStorageMode?> currentStorageMode() async =>
      _modeFromStorage(await _secureStorage.read(key: _storageModeKey));

  Future<OneDriveFolder?> selectedFolder() async {
    final values = await Future.wait([
      _secureStorage.read(key: _folderDriveIdKey),
      _secureStorage.read(key: _folderItemIdKey),
      _secureStorage.read(key: _folderNameKey),
      _secureStorage.read(key: _folderWebUrlKey),
      _secureStorage.read(key: _folderSharedKey),
    ]);
    final driveId = values[0];
    final itemId = values[1];
    final name = values[2];
    if (driveId == null ||
        driveId.isEmpty ||
        itemId == null ||
        itemId.isEmpty ||
        name == null ||
        name.isEmpty) {
      return null;
    }
    return OneDriveFolder(
      driveId: driveId,
      itemId: itemId,
      name: name,
      isShared: values[4] == 'true',
      webUrl: values[3]?.isEmpty == true ? null : values[3],
    );
  }

  Future<bool> isSignedIn() async {
    final storedClientId = await _secureStorage.read(key: _clientIdKey);
    final mode = await currentStorageMode();
    if (storedClientId != clientId || mode == null) {
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

  Future<bool> isStorageConfigured() async {
    if (!await isSignedIn()) return false;
    final mode = await currentStorageMode();
    return mode == OneDriveStorageMode.appFolder ||
        (await selectedFolder()) != null;
  }

  Future<void> signOut() async {
    await Future.wait([
      _secureStorage.delete(key: _accessTokenKey),
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _expiresAtKey),
      _secureStorage.delete(key: _clientIdKey),
      _secureStorage.delete(key: _storageModeKey),
      _secureStorage.delete(key: _folderDriveIdKey),
      _secureStorage.delete(key: _folderItemIdKey),
      _secureStorage.delete(key: _folderNameKey),
      _secureStorage.delete(key: _folderWebUrlKey),
      _secureStorage.delete(key: _folderSharedKey),
    ]);
  }

  Future<List<OneDriveFolder>> listAvailableFolders() async {
    final mode = await currentStorageMode();
    if (mode != OneDriveStorageMode.sharedFolder) {
      throw StateError('Connect using shared-folder mode first.');
    }
    final folders = <String, OneDriveFolder>{};

    Future<void> addFrom(String path, {required bool sharedEndpoint}) async {
      final response = await _graph<Map<String, dynamic>>('GET', path);
      final items = response.data?['value'];
      if (items is! List) return;
      for (final raw in items) {
        if (raw is! Map) continue;
        final folder = OneDriveFolder.tryFromGraphItem(
          Map<String, dynamic>.from(raw),
          sharedEndpoint: sharedEndpoint,
        );
        if (folder != null) folders[folder.key] = folder;
      }
    }

    Object? sharedError;
    try {
      await addFrom(
        '/me/drive/sharedWithMe?\$select=id,name,webUrl,folder,remoteItem,parentReference',
        sharedEndpoint: true,
      );
    } on Object catch (error) {
      sharedError = error;
    }
    try {
      await addFrom(
        '/me/drive/root/children?\$select=id,name,webUrl,folder,remoteItem,parentReference',
        sharedEndpoint: false,
      );
    } on Object catch (error) {
      if (folders.isEmpty) throw sharedError ?? error;
    }

    final result = folders.values.toList()
      ..sort((a, b) {
        if (a.isShared != b.isShared) return a.isShared ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return result;
  }

  Future<void> selectSharedFolder(OneDriveFolder folder) async {
    if (await currentStorageMode() != OneDriveStorageMode.sharedFolder) {
      throw StateError('OneDrive is not connected in shared-folder mode.');
    }
    await Future.wait([
      _secureStorage.write(key: _folderDriveIdKey, value: folder.driveId),
      _secureStorage.write(key: _folderItemIdKey, value: folder.itemId),
      _secureStorage.write(key: _folderNameKey, value: folder.name),
      _secureStorage.write(key: _folderWebUrlKey, value: folder.webUrl ?? ''),
      _secureStorage.write(
        key: _folderSharedKey,
        value: folder.isShared.toString(),
      ),
    ]);
    try {
      await _ensureStorageRoot();
    } on Object {
      await _clearSelectedFolder();
      rethrow;
    }
  }

  Future<OneDriveSyncResult> synchronize() async {
    await _ensureStorageRoot();
    final snapshotAddress = await _itemAddress(_snapshotName);
    Map<String, dynamic>? metadata;
    Uint8List? remoteBytes;
    try {
      final response = await _graph<Map<String, dynamic>>(
        'GET',
        snapshotAddress,
      );
      metadata = response.data;
      final content = await _graph<List<int>>(
        'GET',
        '$snapshotAddress:/content',
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
      '$snapshotAddress:/content',
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
      await _graph<void>('DELETE', await _itemAddress(fullPath));
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
    final address = await _itemAddress(relativePath);
    if (bytes.length <= _simpleUploadLimit) {
      final response = await _graph<Map<String, dynamic>>(
        'PUT',
        '$address:/content',
        data: Stream.fromIterable([bytes]),
        options: Options(contentType: contentType),
      );
      return response.data ?? <String, dynamic>{};
    }

    final session = await _graph<Map<String, dynamic>>(
      'POST',
      '$address:/createUploadSession',
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

  Future<void> _ensureStorageRoot() async {
    final mode = await currentStorageMode();
    if (mode == null) throw StateError('OneDrive is not signed in.');
    if (mode == OneDriveStorageMode.appFolder) {
      await _graph<Object?>('GET', '/me/drive/special/approot');
      return;
    }

    final folder = await _requireSelectedFolder();
    final address = _sharedPathAddress(folder, sharedSubfolderName);
    try {
      await _graph<Object?>('GET', address);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      await _createFolder(
        childrenAddress: _sharedBaseChildrenAddress(folder),
        name: sharedSubfolderName,
        existingAddress: address,
      );
    }
  }

  Future<void> _ensureFolder(String relativePath) async {
    await _ensureStorageRoot();
    final segments = relativePath
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    var current = '';
    for (final segment in segments) {
      final parent = current;
      current = current.isEmpty ? segment : '$current/$segment';
      final address = await _itemAddress(current);
      try {
        await _graph<Object?>('GET', address);
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
        await _createFolder(
          childrenAddress: await _childrenAddress(parent),
          name: segment,
          existingAddress: address,
        );
      }
    }
  }

  Future<void> _createFolder({
    required String childrenAddress,
    required String name,
    required String existingAddress,
  }) async {
    try {
      await _graph<Object?>(
        'POST',
        childrenAddress,
        data: {
          'name': name,
          'folder': <String, dynamic>{},
          '@microsoft.graph.conflictBehavior': 'fail',
        },
      );
    } on DioException catch (error) {
      if (error.response?.statusCode != 409) rethrow;
      await _graph<Object?>('GET', existingAddress);
    }
  }

  Future<String> _itemAddress(String relativePath) async {
    final mode = await currentStorageMode();
    if (mode == OneDriveStorageMode.appFolder) {
      if (relativePath.isEmpty) return '/me/drive/special/approot';
      return '/me/drive/special/approot:/${_encodeGraphPath(relativePath)}';
    }
    if (mode == OneDriveStorageMode.sharedFolder) {
      final folder = await _requireSelectedFolder();
      final path = relativePath.isEmpty
          ? sharedSubfolderName
          : '$sharedSubfolderName/$relativePath';
      return _sharedPathAddress(folder, path);
    }
    throw StateError('OneDrive is not signed in.');
  }

  Future<String> _childrenAddress(String relativeParent) async {
    final mode = await currentStorageMode();
    if (mode == OneDriveStorageMode.appFolder) {
      if (relativeParent.isEmpty) {
        return '/me/drive/special/approot/children';
      }
      return '/me/drive/special/approot:/'
          '${_encodeGraphPath(relativeParent)}:/children';
    }
    if (mode == OneDriveStorageMode.sharedFolder) {
      final folder = await _requireSelectedFolder();
      final path = relativeParent.isEmpty
          ? sharedSubfolderName
          : '$sharedSubfolderName/$relativeParent';
      return '${_sharedPathAddress(folder, path)}:/children';
    }
    throw StateError('OneDrive is not signed in.');
  }

  String _sharedPathAddress(OneDriveFolder folder, String path) =>
      '/drives/${Uri.encodeComponent(folder.driveId)}/items/'
      '${Uri.encodeComponent(folder.itemId)}:/${_encodeGraphPath(path)}';

  String _sharedBaseChildrenAddress(OneDriveFolder folder) =>
      '/drives/${Uri.encodeComponent(folder.driveId)}/items/'
      '${Uri.encodeComponent(folder.itemId)}/children';

  Future<OneDriveFolder> _requireSelectedFolder() async {
    final folder = await selectedFolder();
    if (folder == null) {
      throw StateError('Choose a shared OneDrive folder before syncing.');
    }
    return folder;
  }

  Future<void> _clearSelectedFolder() async {
    await Future.wait([
      _secureStorage.delete(key: _folderDriveIdKey),
      _secureStorage.delete(key: _folderItemIdKey),
      _secureStorage.delete(key: _folderNameKey),
      _secureStorage.delete(key: _folderWebUrlKey),
      _secureStorage.delete(key: _folderSharedKey),
    ]);
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
    final mode = await currentStorageMode();
    if (storedClientId != clientId || mode == null) {
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
        'scope': scopeFor(mode),
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    await _storeTokens(response.data!, mode);
    return '${response.data!['access_token']}';
  }

  Future<void> _storeTokens(
    Map<String, dynamic> data,
    OneDriveStorageMode mode,
  ) async {
    final access = data['access_token']?.toString();
    if (access == null || access.isEmpty) {
      throw const FormatException(
        'Microsoft token response has no access token',
      );
    }
    final refresh = data['refresh_token']?.toString();
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    await _secureStorage.write(key: _clientIdKey, value: clientId);
    await _secureStorage.write(
      key: _storageModeKey,
      value: _modeStorageValue(mode),
    );
    await _secureStorage.write(key: _accessTokenKey, value: access);
    if (refresh != null && refresh.isNotEmpty) {
      await _secureStorage.write(key: _refreshTokenKey, value: refresh);
    }
    await _secureStorage.write(
      key: _expiresAtKey,
      value: DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String(),
    );
  }

  OneDriveStorageMode? _modeFromStorage(String? value) => switch (value) {
    'app_folder' => OneDriveStorageMode.appFolder,
    'shared_folder' => OneDriveStorageMode.sharedFolder,
    _ => null,
  };

  String _modeStorageValue(OneDriveStorageMode mode) =>
      mode == OneDriveStorageMode.appFolder
      ? 'app_folder'
      : 'shared_folder';

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
