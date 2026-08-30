import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/sources/domain/photo_source.dart';
import 'package:mobile_app/features/sources/domain/source_descriptor.dart';
import 'package:mobile_app/features/sources/local/local_folder_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';
import 'package:mobile_app/features/sources/nextcloud/nextcloud_photo_source.dart';
import 'package:mobile_app/features/sources/smb/smb_photo_source.dart';

void main() {
  group('SourceDescriptor JSON roundtrip', () {
    test('toJson/fromJson preserves all fields', () {
      const descriptor = SourceDescriptor(
        type: SourceType.smb,
        id: 'src-1',
        displayName: 'My NAS',
        config: {'host': 'nas.local', 'share': 'Photos', 'rootPath': ''},
      );

      final restored = SourceDescriptor.fromJson(descriptor.toJson());

      expect(restored.type, SourceType.smb);
      expect(restored.id, 'src-1');
      expect(restored.displayName, 'My NAS');
      expect(restored.config, {'host': 'nas.local', 'share': 'Photos', 'rootPath': ''});
    });

    test('fromJson falls back to SourceType.mock for an unknown type string', () {
      final restored = SourceDescriptor.fromJson({
        'type': 'some_future_type',
        'id': 'x',
        'displayName': 'x',
        'config': <String, dynamic>{},
      });

      expect(restored.type, SourceType.mock);
    });

    test('fromJson tolerates a missing config key', () {
      final restored = SourceDescriptor.fromJson({
        'type': 'local',
        'id': 'x',
        'displayName': 'x',
      });

      expect(restored.config, isEmpty);
    });
  });

  group('SmbSourceConfig JSON roundtrip', () {
    test('toJson never includes the password', () {
      const config = SmbSourceConfig(
        host: 'nas.local',
        share: 'Photos',
        domain: 'WORKGROUP',
        username: 'alice',
        password: 'super-secret',
        rootPath: 'Frame/2024',
      );

      final json = config.toJson();

      expect(json.containsKey('password'), isFalse);
      expect(json, {
        'host': 'nas.local',
        'share': 'Photos',
        'domain': 'WORKGROUP',
        'username': 'alice',
        'rootPath': 'Frame/2024',
      });
    });

    test('fromJson rebuilds every non-secret field and re-attaches the given password', () {
      const original = SmbSourceConfig(
        host: 'nas.local',
        share: 'Photos',
        domain: 'WORKGROUP',
        username: 'alice',
        password: 'super-secret',
        rootPath: 'Frame/2024',
      );

      final restored = SmbSourceConfig.fromJson(original.toJson(), password: 'super-secret');

      expect(restored.host, original.host);
      expect(restored.share, original.share);
      expect(restored.domain, original.domain);
      expect(restored.username, original.username);
      expect(restored.rootPath, original.rootPath);
      expect(restored.password, 'super-secret');
    });
  });

  group('NextcloudSourceConfig JSON roundtrip', () {
    test('toJson never includes authPassword', () {
      const config = NextcloudSourceConfig(
        davBaseUrl: 'https://cloud.example.com/remote.php/dav/files/alice',
        authUsername: 'alice',
        authPassword: 'app-password-secret',
        rootPath: 'Fotos',
        isShareLink: false,
      );

      final json = config.toJson();

      expect(json.containsKey('authPassword'), isFalse);
      expect(json, {
        'davBaseUrl': 'https://cloud.example.com/remote.php/dav/files/alice',
        'authUsername': 'alice',
        'rootPath': 'Fotos',
        'isShareLink': false,
      });
    });

    test('fromJson rebuilds the config and re-attaches the given password', () {
      const original = NextcloudSourceConfig(
        davBaseUrl: 'https://cloud.example.com/public.php/webdav',
        authUsername: 'AbCdEf',
        authPassword: 'link-password',
        rootPath: '',
        isShareLink: true,
      );

      final restored = NextcloudSourceConfig.fromJson(original.toJson(), password: 'link-password');

      expect(restored.davBaseUrl, original.davBaseUrl);
      expect(restored.authUsername, original.authUsername);
      expect(restored.rootPath, original.rootPath);
      expect(restored.isShareLink, isTrue);
      expect(restored.authPassword, 'link-password');
    });
  });

  group('fromDescriptor factory', () {
    test('builds an SmbPhotoSource for SourceType.smb', () {
      const descriptor = SourceDescriptor(
        type: SourceType.smb,
        id: 'src-smb',
        displayName: 'NAS',
        config: {'host': 'nas.local', 'share': 'Photos', 'domain': '', 'username': 'alice', 'rootPath': ''},
      );

      final source = fromDescriptor(descriptor, password: 'pw');

      expect(source, isA<SmbPhotoSource>());
      expect(source.id, 'src-smb');
      expect(source.displayName, 'NAS');
      expect((source as SmbPhotoSource).config.host, 'nas.local');
      expect(source.config.password, 'pw');
    });

    test('builds a NextcloudPhotoSource for SourceType.nextcloud', () {
      const descriptor = SourceDescriptor(
        type: SourceType.nextcloud,
        id: 'src-nc',
        displayName: 'Cloud',
        config: {
          'davBaseUrl': 'https://cloud.example.com/remote.php/dav/files/alice',
          'authUsername': 'alice',
          'rootPath': '',
          'isShareLink': false,
        },
      );

      final source = fromDescriptor(descriptor, password: 'app-pw');

      expect(source, isA<NextcloudPhotoSource>());
      expect(source.id, 'src-nc');
      expect((source as NextcloudPhotoSource).config.authUsername, 'alice');
      expect(source.config.authPassword, 'app-pw');
    });

    test('builds a LocalFolderSource for SourceType.local, carrying the rootPath', () {
      const descriptor = SourceDescriptor(
        type: SourceType.local,
        id: 'src-local',
        displayName: 'USB Stick',
        config: {'rootPath': '/storage/usb/DCIM'},
      );

      final source = fromDescriptor(descriptor, password: null);

      expect(source, isA<LocalFolderSource>());
      expect(source.id, 'src-local');
      expect((source as LocalFolderSource).rootPath, '/storage/usb/DCIM');
    });

    test('builds a MockPhotoSource for SourceType.mock', () {
      const descriptor = SourceDescriptor(type: SourceType.mock, id: 'src-mock', displayName: 'Mock');

      final source = fromDescriptor(descriptor, password: null);

      expect(source, isA<MockPhotoSource>());
      expect(source.id, 'src-mock');
    });

    test('falls back to MockPhotoSource for SourceType.sharedAlbum (not yet configurable)', () {
      const descriptor = SourceDescriptor(type: SourceType.sharedAlbum, id: 'src-shared', displayName: 'Family');

      final source = fromDescriptor(descriptor, password: null);

      expect(source, isA<MockPhotoSource>());
      expect(source.id, 'src-shared');
    });
  });

  group('PhotoSourceDescriptorX.toDescriptor', () {
    test('SmbPhotoSource round-trips through toDescriptor -> fromDescriptor', () {
      const config = SmbSourceConfig(
        host: 'nas.local',
        share: 'Photos',
        domain: 'WORKGROUP',
        username: 'alice',
        password: 'secret',
        rootPath: 'Frame',
      );
      final source = SmbPhotoSource(id: 'src-1', config: config, displayName: 'My NAS');

      final descriptor = source.toDescriptor();

      expect(descriptor.type, SourceType.smb);
      expect(descriptor.id, 'src-1');
      expect(descriptor.displayName, 'My NAS');
      expect(descriptor.config.containsKey('password'), isFalse);

      final rebuilt = fromDescriptor(descriptor, password: 'secret') as SmbPhotoSource;
      expect(rebuilt.config.host, 'nas.local');
      expect(rebuilt.config.password, 'secret');
    });

    test('LocalFolderSource toDescriptor carries the current rootPath', () {
      final source = LocalFolderSource(id: 'src-local', rootPath: '/mnt/photos');

      final descriptor = source.toDescriptor();

      expect(descriptor.type, SourceType.local);
      expect(descriptor.config['rootPath'], '/mnt/photos');
    });

    test('LocalFolderSource with no rootPath yet persists an empty string, not null', () {
      final source = LocalFolderSource(id: 'src-local');

      final descriptor = source.toDescriptor();

      expect(descriptor.config['rootPath'], '');
    });

    test('MockPhotoSource toDescriptor produces a mock descriptor', () {
      final source = MockPhotoSource(id: 'src-mock', displayName: 'Test');

      final descriptor = source.toDescriptor();

      expect(descriptor.type, SourceType.mock);
      expect(descriptor.id, 'src-mock');
      expect(descriptor.displayName, 'Test');
    });
  });
}
