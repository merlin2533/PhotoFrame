/// Pure data/validation model for the Immich source configuration form.
///
/// Like `NextcloudConfigFormModel`, this has **no Flutter widget dependency**
/// so it stays testable with plain `flutter test`. The API key is entered
/// here but never persisted in the source descriptor - see
/// `ImmichSourceConfig` in `immich_photo_source.dart`.
class ImmichConfigFormModel {
  const ImmichConfigFormModel({
    this.serverUrl = '',
    this.apiKey = '',
  });

  /// Base URL of the Immich server, e.g. `https://immich.example.com`. A
  /// pasted `/api` suffix is tolerated and stripped by [normalized].
  final String serverUrl;

  /// Immich API key (created in Immich under Account Settings > API Keys).
  final String apiKey;

  ImmichConfigFormModel copyWith({
    String? serverUrl,
    String? apiKey,
  }) {
    return ImmichConfigFormModel(
      serverUrl: serverUrl ?? this.serverUrl,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  /// Validates the form, returning a field-name -> error-message map. An
  /// empty map means the form is valid and [normalized] can be submitted.
  Map<String, String> validate() {
    final errors = <String, String>{};

    final server = cleanServerUrl(serverUrl);
    if (server.isEmpty) {
      errors['serverUrl'] = 'Server-URL fehlt';
    } else {
      final uri = Uri.tryParse(server);
      if (uri == null ||
          (uri.scheme != 'https' && uri.scheme != 'http') ||
          uri.host.isEmpty) {
        errors['serverUrl'] = 'Bitte eine gültige http(s)-URL eingeben';
      } else if (uri.scheme == 'http' && !isPrivateHost(uri.host)) {
        // Same rule as Nextcloud: plain HTTP only for LAN addresses, so the
        // API key is never sent in the clear to a public host.
        errors['serverUrl'] =
            'Ohne HTTPS nur für Adressen im lokalen Netz erlaubt – öffentliche Server bitte mit https://';
      }
    }

    if (apiKey.trim().isEmpty) {
      errors['apiKey'] = 'API-Schlüssel fehlt';
    }

    return errors;
  }

  bool get isValid => validate().isEmpty;

  /// Trims and cleans the free-text fields, ready for building a source
  /// config from a validated form.
  ImmichConfigFormModel normalized() {
    return copyWith(
      serverUrl: cleanServerUrl(serverUrl),
      apiKey: apiKey.trim(),
    );
  }

  /// Reduces a pasted Immich URL to the server base: removes whitespace,
  /// query/fragment, trailing slashes and a trailing `/api`.
  static String cleanServerUrl(String input) {
    var s = input.trim().split(RegExp(r'[?#]')).first;
    s = s.replaceAll(RegExp(r'/+$'), '');
    if (s.endsWith('/api')) {
      s = s.substring(0, s.length - '/api'.length);
    }
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  /// Same LAN check as `NextcloudConfigFormModel`: localhost, RFC1918
  /// ranges and loopback are allowed over plain HTTP.
  static bool isPrivateHost(String host) {
    if (host == 'localhost') return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final p in parts) {
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return false;
      octets.add(v);
    }
    if (octets[0] == 10) return true;
    if (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) return true;
    if (octets[0] == 192 && octets[1] == 168) return true;
    if (octets[0] == 127) return true;
    return false;
  }
}
