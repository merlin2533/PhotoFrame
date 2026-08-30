import 'package:mobile_app/features/sources/nextcloud/nextcloud_config_form_model.dart';
import 'package:test/test.dart';

void main() {
  group('NextcloudConfigFormModel.validate - server URL', () {
    test('empty server URL is invalid', () {
      const model = NextcloudConfigFormModel(username: 'alice', appPassword: 'x');
      expect(model.validate(), containsPair('serverUrl', isNotEmpty));
    });

    test('URL without a scheme is invalid', () {
      const model = NextcloudConfigFormModel(
        serverUrl: 'cloud.example.com',
        username: 'alice',
        appPassword: 'x',
      );
      expect(model.validate(), containsPair('serverUrl', isNotEmpty));
    });

    test('https URL to a public host is valid', () {
      const model = NextcloudConfigFormModel(
        serverUrl: 'https://cloud.example.com',
        username: 'alice',
        appPassword: 'x',
      );
      expect(model.validate().containsKey('serverUrl'), isFalse);
    });

    test('plain http to a public host is rejected', () {
      const model = NextcloudConfigFormModel(
        serverUrl: 'http://cloud.example.com',
        username: 'alice',
        appPassword: 'x',
      );
      expect(model.validate(), containsPair('serverUrl', isNotEmpty));
    });

    test('plain http to a private LAN IP is allowed', () {
      const model = NextcloudConfigFormModel(
        serverUrl: 'http://192.168.1.50',
        username: 'alice',
        appPassword: 'x',
      );
      expect(model.validate().containsKey('serverUrl'), isFalse);
    });

    test('plain http to localhost is allowed', () {
      const model = NextcloudConfigFormModel(
        serverUrl: 'http://localhost:8080',
        username: 'alice',
        appPassword: 'x',
      );
      expect(model.validate().containsKey('serverUrl'), isFalse);
    });
  });

  group('NextcloudConfigFormModel.validate - account mode', () {
    test('requires username and app password', () {
      const model = NextcloudConfigFormModel(serverUrl: 'https://cloud.example.com');
      final errors = model.validate();
      expect(errors, containsPair('username', isNotEmpty));
      expect(errors, containsPair('appPassword', isNotEmpty));
    });

    test('valid account form has no errors', () {
      const model = NextcloudConfigFormModel(
        serverUrl: 'https://cloud.example.com',
        username: 'alice',
        appPassword: 'app-pw',
      );
      expect(model.validate(), isEmpty);
      expect(model.isValid, isTrue);
    });
  });

  group('NextcloudConfigFormModel.validate - share link mode', () {
    test('requires a share token', () {
      const model = NextcloudConfigFormModel(
        authKind: NextcloudAuthKind.shareLink,
        serverUrl: 'https://cloud.example.com',
      );
      expect(model.validate(), containsPair('shareToken', isNotEmpty));
    });

    test('share password is optional', () {
      const model = NextcloudConfigFormModel(
        authKind: NextcloudAuthKind.shareLink,
        serverUrl: 'https://cloud.example.com',
        shareToken: 'AbCdEf',
      );
      expect(model.validate(), isEmpty);
    });

    test('share mode does not require account fields', () {
      const model = NextcloudConfigFormModel(
        authKind: NextcloudAuthKind.shareLink,
        serverUrl: 'https://cloud.example.com',
        shareToken: 'AbCdEf',
      );
      final errors = model.validate();
      expect(errors.containsKey('username'), isFalse);
      expect(errors.containsKey('appPassword'), isFalse);
    });
  });

  group('NextcloudConfigFormModel.normalized', () {
    test('strips trailing slashes from the server URL', () {
      const model = NextcloudConfigFormModel(serverUrl: 'https://cloud.example.com///');
      expect(model.normalized().serverUrl, 'https://cloud.example.com');
    });

    test('trims username, share token and folder path slashes', () {
      const model = NextcloudConfigFormModel(
        username: '  alice  ',
        shareToken: '  AbCdEf  ',
        folderPath: '/Fotos/Rahmen/',
      );
      final normalized = model.normalized();
      expect(normalized.username, 'alice');
      expect(normalized.shareToken, 'AbCdEf');
      expect(normalized.folderPath, 'Fotos/Rahmen');
    });
  });
}
