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

    switch (authKind) {
      case NextcloudAuthKind.account:
        // The server URL field is only shown (and only meaningful) in
        // account mode - in share-link mode it's derived from the pasted
        // link itself, see the case below.
        final trimmedUrl = serverUrl.trim();
        if (trimmedUrl.isEmpty) {
          errors['serverUrl'] = 'Server URL is required';
        } else {
          final uri = Uri.tryParse(trimmedUrl);
          if (uri == null || !uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
            errors['serverUrl'] = 'Enter a valid http(s) URL';
          } else if (uri.scheme == 'http' && !_isPrivateHost(uri.host)) {
            // Per docs/PLAN.md P0 decisions: HTTPS is enforced except for
            // explicit LAN opt-out (private IP ranges) - a public hostname
            // over plain HTTP is rejected here rather than silently sending
            // credentials in the clear.
            errors['serverUrl'] =
                'Plain HTTP is only allowed for private/LAN addresses; use HTTPS for public servers';
          }
        }
        if (username.trim().isEmpty) {
          errors['username'] = 'Username is required';
        }
        if (appPassword.isEmpty) {
          errors['appPassword'] = 'App password is required';
        }
      case NextcloudAuthKind.shareLink:
        // The server URL field isn't shown in this mode (see
        // `nextcloud_config_form.dart`) - the whole share link is pasted
        // into `shareToken` instead and both pieces are derived from it in
        // `normalized()`, so validate that combined input here rather than
        // the separate `serverUrl`/`shareToken` checks used for account
        // mode above. A bare token (no `/s/`) is no longer accepted here,
        // since there would be no field left to also supply a server URL
        // for it.
        final trimmedShareInput = shareToken.trim();
        if (trimmedShareInput.isEmpty) {
          errors['shareToken'] = 'Share link is required';
        } else {
          final derivedServerUrl = _extractShareServerUrl(trimmedShareInput);
          if (derivedServerUrl == null) {
            errors['shareToken'] = 'Enter the full share link, e.g. https://cloud.example.com/s/AbCdEf';
          } else if (derivedServerUrl.scheme == 'http' && !_isPrivateHost(derivedServerUrl.host)) {
            // Same HTTPS-except-LAN policy as the account mode above,
            // applied to the server URL derived from the pasted link.
            errors['shareToken'] =
                'Plain HTTP links are only allowed for private/LAN addresses; use an HTTPS share link';
          }
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
    if (authKind == NextcloudAuthKind.shareLink) {
      // `serverUrl` isn't a separate input in this mode (see
      // `nextcloud_config_form.dart`) - both it and `shareToken` are derived
      // from the one pasted share link.
      final trimmedShareInput = shareToken.trim();
      return copyWith(
        serverUrl: _extractShareServerUrl(trimmedShareInput)?.origin ?? '',
        shareToken: _extractShareToken(trimmedShareInput),
        folderPath: folderPath.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
      );
    }
    return copyWith(
      serverUrl: serverUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      username: username.trim(),
      shareToken: _extractShareToken(shareToken.trim()),
      folderPath: folderPath.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
    );
  }

  /// Pulls the server origin (`https://cloud.example.com`) out of a pasted
  /// public share link (`https://cloud.example.com/s/AbCdEf`) - the part of
  /// [_extractShareToken]'s input that would otherwise have to be entered a
  /// second time into a separate server-URL field. Returns `null` if
  /// [input] doesn't look like a full share link (no `/s/` marker, or the
  /// part before it isn't a valid http(s) URL) - callers treat that as "not
  /// a full link", since a bare token alone carries no server information.
  static Uri? _extractShareServerUrl(String input) {
    if (!input.contains('/s/')) return null;
    final beforeMarker = input.substring(0, input.indexOf('/s/'));
    final uri = Uri.tryParse(beforeMarker);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      return null;
    }
    return uri;
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
