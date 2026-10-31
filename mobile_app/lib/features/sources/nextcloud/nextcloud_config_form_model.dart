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
          if (uri == null ||
              !uri.hasScheme ||
              (uri.scheme != 'https' && uri.scheme != 'http')) {
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
        // Either a full share link pasted into [shareToken] (legacy / paste
        // convenience) or the separate [serverUrl] + bare [shareToken].
        final parsed = parseShareLink(shareToken.trim());
        final server = parsed?.serverUrl ?? cleanServerUrl(serverUrl);
        final token = parsed?.token ?? shareToken.trim();
        final uri = Uri.tryParse(server);
        if (server.isEmpty) {
          errors['serverUrl'] = 'Server URL is required';
        } else if (uri == null ||
            (uri.scheme != 'https' && uri.scheme != 'http') ||
            uri.host.isEmpty) {
          errors['serverUrl'] = 'Enter a valid http(s) URL';
        } else if (uri.scheme == 'http' && !_isPrivateHost(uri.host)) {
          errors['serverUrl'] =
              'Plain HTTP is only allowed for private/LAN addresses; use HTTPS for public servers';
        }
        if (token.isEmpty) {
          errors['shareToken'] = 'Share link is required';
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
      final parsed = parseShareLink(shareToken.trim());
      return copyWith(
        serverUrl: parsed?.serverUrl ?? cleanServerUrl(serverUrl),
        shareToken: parsed?.token ?? _cleanToken(shareToken),
        folderPath: folderPath.trim().replaceAll(RegExp(r'^/+|/+$'), ''),
      );
    }
    return copyWith(
      serverUrl: cleanServerUrl(serverUrl),
      username: username.trim(),
      shareToken: parseShareLink(shareToken)?.token ?? _cleanToken(shareToken),
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
  /// Splits a pasted share link (`https://host[/sub][/index.php]/s/TOKEN[/...]`)
  /// into server URL and bare token, dropping everything that doesn't belong
  /// (query, fragment, `/download`, trailing slashes, `/index.php`).
  /// Returns `null` if [input] is not a share link.
  static ({String serverUrl, String token})? parseShareLink(String input) {
    final text = input.trim();
    final i = text.indexOf('/s/');
    if (i < 0) return null;
    var server = text.substring(0, i).replaceAll(RegExp(r'/index\.php$'), '');
    server = cleanServerUrl(server);
    final uri = Uri.tryParse(server);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return null;
    }
    final token = _cleanToken(text.substring(i + 3));
    if (token.isEmpty) return null;
    return (serverUrl: server, token: token);
  }

  /// Reduces any pasted Nextcloud URL to the server base: removes whitespace,
  /// query/fragment, trailing slashes and app paths (`/index.php`,
  /// `/remote.php`, `/apps/...`, `/s/...`).
  static String cleanServerUrl(String input) {
    var s = input.trim().split(RegExp(r'[?#]')).first;
    for (final marker in [
      '/index.php',
      '/remote.php',
      '/public.php',
      '/apps/',
      '/s/'
    ]) {
      final i = s.indexOf(marker);
      if (i > 0) s = s.substring(0, i);
    }
    return s.replaceAll(RegExp(r'/+$'), '');
  }

  static String _cleanToken(String input) =>
      input.trim().split(RegExp(r'[/?#\s]')).first;
}
