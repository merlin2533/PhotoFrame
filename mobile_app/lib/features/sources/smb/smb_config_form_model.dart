/// Pure data/validation model for the SMB source configuration form.
///
/// Deliberately has **no Flutter widget dependency** (mirrors
/// `NextcloudConfigFormModel`'s design) so it stays testable with plain
/// `flutter test`; `smb_config_form.dart` binds its text fields to an
/// instance of this class.
class SmbConfigFormModel {
  const SmbConfigFormModel({
    this.host = '',
    this.share = '',
    this.domain = '',
    this.username = '',
    this.password = '',
    this.rootPath = '',
  });

  /// Hostname or IP address of the SMB server, e.g. `192.168.1.20` or
  /// `nas.local`.
  final String host;

  /// Share name, e.g. `Photos`.
  final String share;

  /// Optional Windows domain/workgroup. Most home NAS/Samba setups leave
  /// this empty.
  final String domain;

  final String username;
  final String password;

  /// Path within [share] to use as the source root, e.g. `Frame/2024`.
  /// Empty means the share root itself.
  final String rootPath;

  SmbConfigFormModel copyWith({
    String? host,
    String? share,
    String? domain,
    String? username,
    String? password,
    String? rootPath,
  }) {
    return SmbConfigFormModel(
      host: host ?? this.host,
      share: share ?? this.share,
      domain: domain ?? this.domain,
      username: username ?? this.username,
      password: password ?? this.password,
      rootPath: rootPath ?? this.rootPath,
    );
  }

  /// A reasonably strict, but not RFC-pedantic, hostname/IPv4 shape check:
  /// rejects obviously-invalid input (whitespace, empty labels, a scheme/
  /// path accidentally pasted in) without trying to be a full validator -
  /// the real, authoritative check is [SmbPhotoSource.testConnection]
  /// actually reaching the host.
  static final RegExp _hostPattern = RegExp(
    r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$',
  );

  /// Validates the form, returning a field-name -> error-message map. An
  /// empty map means the form is valid and [normalized] can be submitted.
  Map<String, String> validate() {
    final errors = <String, String>{};

    final trimmedHost = host.trim();
    if (trimmedHost.isEmpty) {
      errors['host'] = 'Host/IP is required';
    } else if (trimmedHost.contains(' ') || trimmedHost.contains('/') || trimmedHost.contains('\\')) {
      errors['host'] = 'Enter just the host/IP, without a path (e.g. 192.168.1.20)';
    } else if (!_hostPattern.hasMatch(trimmedHost)) {
      errors['host'] = 'Enter a valid hostname or IP address';
    }

    final trimmedShare = share.trim();
    if (trimmedShare.isEmpty) {
      errors['share'] = 'Share name is required';
    } else if (trimmedShare.contains('/') || trimmedShare.contains('\\')) {
      errors['share'] = 'Enter just the share name, without a path';
    }

    return errors;
  }

  bool get isValid => validate().isEmpty;

  /// Trims free-text fields, useful right before building the actual
  /// `SmbSourceConfig` from a validated form.
  SmbConfigFormModel normalized() {
    return copyWith(
      host: host.trim(),
      share: share.trim(),
      domain: domain.trim(),
      username: username.trim(),
      rootPath: rootPath.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
    );
  }
}
