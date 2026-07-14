import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/sync/one_drive_service.dart';

void main() {
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
  });
}
