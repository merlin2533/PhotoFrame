import 'package:mobile_app/features/sources/smb/smb_config_form_model.dart';
import 'package:test/test.dart';

void main() {
  group('SmbConfigFormModel.validate', () {
    test('empty form is invalid with both required fields flagged', () {
      const model = SmbConfigFormModel();
      final errors = model.validate();
      expect(errors, containsPair('host', isNotEmpty));
      expect(errors, containsPair('share', isNotEmpty));
      expect(model.isValid, isFalse);
    });

    test('valid host + share passes validation', () {
      const model = SmbConfigFormModel(host: '192.168.1.20', share: 'Photos');
      expect(model.validate(), isEmpty);
      expect(model.isValid, isTrue);
    });

    test('valid hostname (not just IP) passes validation', () {
      const model = SmbConfigFormModel(host: 'nas.local', share: 'Photos');
      expect(model.validate(), isEmpty);
    });

    test('host with embedded path is rejected', () {
      const model = SmbConfigFormModel(host: '192.168.1.20/share', share: 'Photos');
      expect(model.validate(), containsPair('host', isNotEmpty));
    });

    test('host with whitespace is rejected', () {
      const model = SmbConfigFormModel(host: '192.168 1.20', share: 'Photos');
      expect(model.validate(), containsPair('host', isNotEmpty));
    });

    test('host with invalid characters is rejected', () {
      const model = SmbConfigFormModel(host: 'nas!local', share: 'Photos');
      expect(model.validate(), containsPair('host', isNotEmpty));
    });

    test('share name with a slash is rejected', () {
      const model = SmbConfigFormModel(host: 'nas.local', share: 'Photos/2024');
      expect(model.validate(), containsPair('share', isNotEmpty));
    });

    test('missing share only flags share', () {
      const model = SmbConfigFormModel(host: 'nas.local');
      final errors = model.validate();
      expect(errors, containsPair('share', isNotEmpty));
      expect(errors.containsKey('host'), isFalse);
    });

    test('whitespace-only host/share counts as empty', () {
      const model = SmbConfigFormModel(host: '   ', share: '   ');
      final errors = model.validate();
      expect(errors, containsPair('host', isNotEmpty));
      expect(errors, containsPair('share', isNotEmpty));
    });
  });

  group('SmbConfigFormModel.normalized', () {
    test('trims host, share, domain, username and root path', () {
      const model = SmbConfigFormModel(
        host: '  nas.local  ',
        share: '  Photos  ',
        domain: '  WORKGROUP  ',
        username: '  alice  ',
        rootPath: '/Frame/2024/',
      );
      final normalized = model.normalized();
      expect(normalized.host, 'nas.local');
      expect(normalized.share, 'Photos');
      expect(normalized.domain, 'WORKGROUP');
      expect(normalized.username, 'alice');
      expect(normalized.rootPath, 'Frame/2024');
    });

    test('does not trim the password', () {
      const model = SmbConfigFormModel(
        host: 'nas.local',
        share: 'Photos',
        password: '  secret  ',
      );
      expect(model.normalized().password, '  secret  ');
    });
  });
}
