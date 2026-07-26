// ignore_for_file: prefer_initializing_formals

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../sync/one_drive_service.dart';

enum WorkspaceOperation { create, replace, delete }

class WorkspaceProposal {
  const WorkspaceProposal({
    required this.id,
    required this.profileId,
    required this.relativePath,
    required this.operation,
    required this.summary,
    required this.createdAt,
    this.bytes,
    this.previousSha256,
    this.contentType = 'application/octet-stream',
  });

  final String id;
  final String profileId;
  final String relativePath;
  final WorkspaceOperation operation;
  final String summary;
  final Uint8List? bytes;
  final String? previousSha256;
  final String contentType;
  final DateTime createdAt;
}

class SafeWorkspaceService {
  SafeWorkspaceService({OneDriveService? oneDriveService, Uuid? uuid})
    : _oneDriveService = oneDriveService,
      _uuid = uuid ?? const Uuid();

  final OneDriveService? _oneDriveService;
  final Uuid _uuid;
  final Map<String, WorkspaceProposal> _pending = {};

  List<WorkspaceProposal> get pending => List.unmodifiable(_pending.values);

  Future<List<String>> listFiles(String profileId) async {
    final root = await _root(profileId);
    if (!await root.exists()) return const [];
    final result = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        result.add(path.relative(entity.path, from: root.path));
      }
    }
    result.sort();
    return result;
  }

  Future<Uint8List> read(String profileId, String relativePath) async {
    final file = await _file(profileId, relativePath);
    return file.readAsBytes();
  }

  Future<Map<String, Object?>> contextSnapshot(String profileId) async {
    final files = <Map<String, Object?>>[];
    for (final relativePath in await listFiles(profileId)) {
      final bytes = await read(profileId, relativePath);
      String? textContent;
      try {
        textContent = const Utf8Decoder(allowMalformed: false).convert(bytes);
      } on FormatException {
        // Binary files remain visible by metadata without corrupting the prompt.
      }
      files.add({
        'path': relativePath,
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'text_content': textContent,
        'binary': textContent == null,
      });
    }
    return {
      'schema': 'superhealth.advisor_workspace',
      'schema_version': 1,
      'complete': true,
      'profile_id': profileId,
      'files': files,
    };
  }

  Future<WorkspaceProposal> proposeWrite({
    required String profileId,
    required String relativePath,
    required Uint8List bytes,
    required String summary,
    String contentType = 'application/octet-stream',
  }) async {
    final file = await _file(profileId, relativePath);
    final exists = await file.exists();
    final proposal = WorkspaceProposal(
      id: _uuid.v4(),
      profileId: profileId,
      relativePath: _safeRelativePath(relativePath),
      operation: exists
          ? WorkspaceOperation.replace
          : WorkspaceOperation.create,
      summary: summary,
      bytes: bytes,
      previousSha256: exists
          ? sha256.convert(await file.readAsBytes()).toString()
          : null,
      contentType: contentType,
      createdAt: DateTime.now(),
    );
    _pending[proposal.id] = proposal;
    return proposal;
  }

  Future<WorkspaceProposal> proposeDelete({
    required String profileId,
    required String relativePath,
    required String summary,
  }) async {
    final file = await _file(profileId, relativePath);
    if (!await file.exists()) {
      throw StateError('Workspace file does not exist.');
    }
    final proposal = WorkspaceProposal(
      id: _uuid.v4(),
      profileId: profileId,
      relativePath: _safeRelativePath(relativePath),
      operation: WorkspaceOperation.delete,
      summary: summary,
      previousSha256: sha256.convert(await file.readAsBytes()).toString(),
      createdAt: DateTime.now(),
    );
    _pending[proposal.id] = proposal;
    return proposal;
  }

  /// Must only be invoked after the UI has shown the exact path, operation,
  /// summary, and content preview in a confirmation dialog.
  Future<void> applyAfterExplicitApproval(
    String proposalId, {
    required bool userConfirmed,
    bool uploadToOneDrive = true,
  }) async {
    if (!userConfirmed) throw StateError('Explicit file approval is required.');
    final proposal = _pending[proposalId];
    if (proposal == null) throw StateError('Proposal is no longer pending.');
    final file = await _file(proposal.profileId, proposal.relativePath);
    final previousBytes = await file.exists() ? await file.readAsBytes() : null;
    final currentHash = previousBytes == null
        ? null
        : sha256.convert(previousBytes).toString();
    if (currentHash != proposal.previousSha256) {
      throw StateError(
        'The workspace file changed after the preview. Review it again.',
      );
    }
    switch (proposal.operation) {
      case WorkspaceOperation.create:
      case WorkspaceOperation.replace:
        await file.parent.create(recursive: true);
        await file.writeAsBytes(proposal.bytes!, flush: true);
        try {
          if (uploadToOneDrive &&
              _oneDriveService != null &&
              await _oneDriveService.isSignedIn()) {
            await _oneDriveService.uploadApprovedFile(
              profileId: proposal.profileId,
              relativePath: proposal.relativePath,
              bytes: proposal.bytes!,
              contentType: proposal.contentType,
            );
          }
        } on Object {
          await _restoreLocalFile(file, previousBytes);
          rethrow;
        }
        break;
      case WorkspaceOperation.delete:
        await file.delete();
        try {
          if (uploadToOneDrive &&
              _oneDriveService != null &&
              await _oneDriveService.isSignedIn()) {
            await _oneDriveService.deleteApprovedFile(
              profileId: proposal.profileId,
              relativePath: proposal.relativePath,
            );
          }
        } on Object {
          await _restoreLocalFile(file, previousBytes);
          rethrow;
        }
        break;
    }
    _pending.remove(proposalId);
  }

  void reject(String proposalId) => _pending.remove(proposalId);

  Future<void> _restoreLocalFile(File file, Uint8List? previousBytes) async {
    if (previousBytes == null) {
      if (await file.exists()) {
        await file.delete();
      }
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsBytes(previousBytes, flush: true);
  }

  Future<Directory> _root(String profileId) async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(path.join(base.path, 'advisor_workspace', profileId));
  }

  Future<File> _file(String profileId, String relativePath) async {
    final root = await _root(profileId);
    final safe = _safeRelativePath(relativePath);
    final file = File(path.join(root.path, safe));
    if (!path.isWithin(root.path, file.path)) {
      throw ArgumentError('Path escapes the advisor workspace.');
    }
    return file;
  }

  String _safeRelativePath(String value) {
    final normalized = path.normalize(value.trim()).replaceAll('\\', '/');
    if (normalized.isEmpty ||
        normalized == '.' ||
        normalized.startsWith('/') ||
        normalized == '..' ||
        normalized.startsWith('../')) {
      throw ArgumentError('Invalid advisor workspace path.');
    }
    return normalized;
  }
}
