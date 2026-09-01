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
      const model = NextcloudConfigFormModel(authKind: NextcloudAuthKind.shareLink);
      expect(model.validate(), containsPair('shareToken', isNotEmpty));
    });

    test('a bare token with no server URL embedded is rejected', () {
      // Share-link mode has no separate server-URL field (see
      // `nextcloud_config_form.dart`) - the full link must be pasted so both
      // pieces can be derived from it; a bare token alone has nowhere to
      // get the server from.
      const model = NextcloudConfigFormModel(
        authKind: NextcloudAuthKind.shareLink,
        shareToken: 'AbCdEf',
      );
      expect(model.validate(), containsPair('shareToken', isNotEmpty));
    });

    test('a full share link is valid and requires no separate server URL', () {
      const model = NextcloudConfigFormModel(
        authKind: NextcloudAuthKind.shareLink,
        shareToken: 'https://cloud.example.com/s/AbCdEf',
      );
      expect(model.validate(), isEmpty);
    });

    test('share password is optional', () {
      const model = NextcloudConfigFormModel(
        authKind: NextcloudAuthKind.shareLink,
        shareToken: 'https://cloud.example.com/s/AbCdEf',
      );
      expect(model.validate(), isEmpty);
    });

    test('share mode does not require account fields', () {
      const model = NextcloudConfigFormModel(
        authKind: NextcloudAuthKind.shareLink,
        shareToken: 'https://cloud.example.com/s/AbCdEf',
      );
      final errors = model.validate();
      expect(errors.containsKey('username'), isFalse);
      expect(errors.containsKey('appPassword'), isFalse);
    });

    test('plain http share link to a public host is rejected', () {
      const model = NextcloudConfigFormModel(
        authKind: NextcloudAuthKind.shareLink,
        shareToken: 'http://cloud.example.com/s/AbCdEf',
      );
      expect(model.validate(), containsPair('shareToken', isNotEmpty));
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

    test('share link mode derives both server URL and token from the pasted link', () {
      const model = NextcloudConfigFormModel(
        authKind: NextcloudAuthKind.shareLink,
        shareToken: '  https://cloud.example.com/s/AbCdEf/  ',
      );
      final normalized = model.normalized();
      expect(normalized.serverUrl, 'https://cloud.example.com');
      expect(normalized.shareToken, 'AbCdEf');
    });
  });
}
