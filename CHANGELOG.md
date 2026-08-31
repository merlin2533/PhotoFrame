# Changelog

All notable changes to PhotoFrame are recorded here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). From this point
forward, every commit automatically gets an entry appended right below this
paragraph by the repo's `commit-msg` git hook (see `CONTRIBUTING.md` for
one-time setup) — each entry's version is `mobile_app`'s `pubspec.yaml`
build number *after* that commit's automatic bump, newest entry on top.

<!-- COMMIT-HOOK-INSERT-MARKER: new entries are inserted directly below this line. -->
- **2026-08-31** (mobile_app 0.1.0+2) — Fix real-device bugs (slideshow never rendered real photos, kiosk mode had no immediate exit), rename app to PhotoFrame, add CHANGELOG/version-bump git hooks

## Baseline (pre-automation)

Retroactive summary of everything up to `mobile_app` version `0.1.0+1` /
`relay_server` version `1.0.0`, before this automated changelog started:

- Full v1 architecture scaffold: relay server (auth, pairing, content-addressed
  blob storage, quotas, admin panel) and Flutter app foundation (PhotoSource
  abstraction, slideshow engine, Riverpod state).
- Weather overlay, configurable transitions/Ken Burns, favorites, "on this
  day" date filter, i18n scaffold (DE/EN), E2E crypto (X25519/HKDF/AES-GCM)
  for frame-to-frame config push with TOFU key-fingerprint verification.
- SMB/Nextcloud/local-folder source configuration forms, source persistence
  across app restarts, Android kiosk/autostart mode, admin frame
  soft-delete, config-push flow fully wired into the app's navigation,
  language switcher.
- Fixes for real-device bugs: the slideshow now actually decodes and
  displays real photo files (`Image.file`) instead of a placeholder box for
  every configured source, HEIC/HEIF is honestly treated as undecodable
  (Flutter's built-in codec can't read it) while GIF/BMP were added to the
  supported set, kiosk screen-pinning can now be exited immediately from
  Settings, and the app is now labelled "PhotoFrame" everywhere instead of
  the generic `mobile_app` project name.
