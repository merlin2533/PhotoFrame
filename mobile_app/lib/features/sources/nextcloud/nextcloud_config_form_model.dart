/// The two ways a Nextcloud source can be configured, per docs/PLAN.md
/// ("Nextcloud: Lese- UND Schreibzugriff, Account ODER öffentlicher
/// Share-Link").
enum NextcloudAuthKind {
  /// WebDAV login with username + app password against
  /// `remote.php/dav/files/<user>/...`. Full read/write access to the
  /// configured folder.
  account,

  /// A public share link, accessed via `public.php/webdav`. Read/write
  /// access depends entirely on how the link was shared server-side and is
  /// only known for sure after `testConnection()`'s permission probe.
  shareLink,
}

/// Pure data/validation model for the Nextcloud source configuration form.
/// Deliberately has **no Flutter widget dependency** so it stays testable
/// with plain `flutter test` - the actual screen (built by a parallel
/// agent) is expected to bind its text fields to an instance of this class.
class NextcloudConfigFormModel {
  const NextcloudConfigFormModel({
    this.authKind = NextcloudAuthKind.account,
    this.serverUrl = '',
    this.username = '',
    this.appPassword = '',
    this.shareToken = '',
    this.sharePassword = '',
    this.folderPath = '',
  });

  final NextcloudAuthKind authKind;

  /// Base server URL, e.g. `https://cloud.example.com` (no trailing slash,
  /// no `/remote.php/...` suffix - that's appended based on [authKind]).
  final String serverUrl;

  /// Account username. Only used when [authKind] is
  /// [NextcloudAuthKind.account].
  final String username;

  /// Nextcloud "app password" (never the user's real account password - the
  /// app should instruct users to generate one under Settings > Security).
  /// Only used when [authKind] is [NextcloudAuthKind.account].
  final String appPassword;

  /// The share token from a public share link
  /// (`https://cloud.example.com/s/<token>`). Only used when [authKind] is
  /// [NextcloudAuthKind.shareLink].
  final String shareToken;

  /// Optional password protecting the share link, if the sharer set one.
  /// Only used when [authKind] is [NextcloudAuthKind.shareLink].
  final String sharePassword;

  /// Subfolder within the account/share to use as the source root. Empty
  /// means the account/share root itself.
  final String folderPath;

  NextcloudConfigFormModel copyWith({
    NextcloudAuthKind? authKind,
    String? serverUrl,
    String? username,
    String? appPassword,
    String? shareToken,
    String? sharePassword,
    String? folderPath,
  }) {
    return NextcloudConfigFormModel(
      authKind: authKind ?? this.authKind,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      appPassword: appPassword ?? this.appPassword,
      shareToken: shareToken ?? this.shareToken,
      sharePassword: sharePassword ?? this.sharePassword,
      folderPath: folderPath ?? this.folderPath,
    );
  }

  /// Validates the form, returning a field-name -> error-message map. An
  /// empty map means the form is valid and [normalized] can be submitted.
  Map<String, String> validate() {
    final errors = <String, String>{};

    final trimmedUrl = serverUrl.trim();
    if (trimmedUrl.isEmpty) {
      errors['serverUrl'] = 'Server URL is required';
    } else {
      final uri = Uri.tryParse(trimmedUrl);
      if (uri == null || !uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
        errors['serverUrl'] = 'Enter a valid http(s) URL';
      } else if (uri.scheme == 'http' && !_isPrivateHost(uri.host)) {
        // Per docs/PLAN.md P0 decisions: HTTPS is enforced except for
        // explicit LAN opt-out (private IP ranges) - a public hostname over
        // plain HTTP is rejected here rather than silently sending
        // credentials in the clear.
        errors['serverUrl'] =
            'Plain HTTP is only allowed for private/LAN addresses; use HTTPS for public servers';
      }
    }

    switch (authKind) {
      case NextcloudAuthKind.account:
        if (username.trim().isEmpty) {
          errors['username'] = 'Username is required';
        }
        if (appPassword.isEmpty) {
          errors['appPassword'] = 'App password is required';
        }
      case NextcloudAuthKind.shareLink:
        if (shareToken.trim().isEmpty) {
          errors['shareToken'] = 'Share link/token is required';
        }
    }

    return errors;
  }

  bool get isValid => validate().isEmpty;

  static bool _isPrivateHost(String host) {
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

  /// Trims free-text fields, useful right before building the actual source
  /// config from a validated form.
  NextcloudConfigFormModel normalized() {
    return copyWith(
      serverUrl: serverUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      username: username.trim(),
      shareToken: _extractShareToken(shareToken.trim()),
      folderPath: folderPath.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
    );
  }

  /// The share-token field's hint text explicitly invites either a bare
  /// token ("AbCdEf") or a full share URL
  /// ("https://cloud.example.com/s/AbCdEf") - but the token is used
  /// downstream as a Basic-Auth username against `public.php/webdav`, which
  /// must be the bare token, never the full URL. Without this extraction, a
  /// user who (reasonably, given the hint) pastes the full URL gets a
  /// guaranteed, unexplained 401. Nextcloud share URLs always end in
  /// `/s/<token>` (optionally followed by a trailing slash or query
  /// string), so pull that segment out; anything that doesn't look like a
  /// URL is assumed to already be a bare token and passed through as-is.
  static String _extractShareToken(String input) {
    if (!input.contains('/s/')) return input;
    final afterMarker = input.substring(input.lastIndexOf('/s/') + 3);
    final token = afterMarker.split(RegExp(r'[/?#]')).first;
    return token.isEmpty ? input : token;
  }
}
