import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/observability/error_reporter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  group('scrubSensitiveText', () {
    test('replaces http and https URLs including their hosts', () {
      expect(
        scrubSensitiveText('Lade https://nas.example.org/dav/Fotos/a.txt'),
        'Lade [redacted]',
      );
      expect(
        scrubSensitiveText('Quelle http://192.168.1.20:5005/api?key=1 down'),
        'Quelle [redacted] down',
      );
    });

    test('replaces other URL schemes such as content and file', () {
      expect(
        scrubSensitiveText(
            'content://com.android.externalstorage.documents/document/x%3AIMG'),
        '[redacted]',
      );
      expect(scrubSensitiveText('file:///storage/emulated/0/a'), '[redacted]');
    });

    test('replaces Windows drive paths and UNC paths', () {
      expect(
        scrubSensitiveText(r'Pfad C:\Users\markus\Bilder\Urlaub ok'),
        r'Pfad [redacted] ok',
      );
      expect(
        scrubSensitiveText(r'Share \\nas\fotos\alt'),
        r'Share [redacted]',
      );
    });

    test('replaces POSIX absolute paths', () {
      expect(
        scrubSensitiveText('Datei /storage/emulated/0/DCIM/Camera kaputt'),
        'Datei [redacted] kaputt',
      );
    });

    test('replaces e-mail addresses', () {
      expect(
        scrubSensitiveText('Konto markus.straub.it@gmail.com meldet'),
        'Konto [redacted] meldet',
      );
    });

    test('replaces photo and video file names, case-insensitively', () {
      expect(scrubSensitiveText('IMG_1234.heic defekt'), '[redacted] defekt');
      expect(scrubSensitiveText('"holiday.JPG" fehlt'), '"[redacted]" fehlt');
      expect(scrubSensitiveText('clip_07.mp4'), '[redacted]');
    });

    test('replaces IPv4 addresses and hostnames, keeps the port', () {
      expect(scrubSensitiveText('IP 10.0.0.7 antwortet'),
          'IP [redacted] antwortet');
      expect(scrubSensitiveText("Host 'nas.local':445 weg"),
          "Host '[redacted]':445 weg");
      expect(
          scrubSensitiveText('localhost:8080 offline'), '[redacted] offline');
    });

    test('keeps ordinary text, versions and code file names readable', () {
      const text = 'Version 0.1.0+13 in main.dart, Fehler bei 1/2 und and/or';
      expect(scrubSensitiveText(text), text);
    });

    test('leaves text without sensitive data unchanged', () {
      const text = 'Quelle übersprungen: Timeout nach 30 s';
      expect(scrubSensitiveText(text), text);
      expect(scrubSensitiveText(''), '');
    });
  });

  group('redactSentryEvent', () {
    tearDown(() => setErrorReportingEnabled(true));

    SentryEvent buildEvent() {
      return SentryEvent(
        message: SentryMessage('Fehler bei https://nas.local/Fotos'),
        exceptions: [
          SentryException(
            type: 'FileSystemException',
            value: 'cannot open /storage/emulated/0/IMG_9.jpg',
          ),
        ],
        breadcrumbs: [Breadcrumb(message: 'tippe auf Quelle')],
        user: SentryUser(email: 'markus.straub.it@gmail.com'),
        request: SentryRequest(url: 'https://nas.local/dav'),
      );
    }

    test('removes breadcrumbs, user and request data', () async {
      final event = await redactSentryEvent(buildEvent(), Hint());

      expect(event, isNotNull);
      expect(event!.breadcrumbs, isNull);
      expect(event.user, isNull);
      expect(event.request, isNull);
    });

    test('scrubs the message and the exception value', () async {
      final event = (await redactSentryEvent(buildEvent(), Hint()))!;

      expect(event.message?.formatted, 'Fehler bei [redacted]');
      expect(event.exceptions?.single.value, 'cannot open [redacted]');
      expect(event.exceptions?.single.type, 'FileSystemException');
      expect(event.exceptions?.single.throwable, isNull);
    });

    test('scrubs extra data and tags', () async {
      final event = buildEvent()
        // ignore: deprecated_member_use
        ..extra = {'file': '/storage/a/IMG_1.jpg', 'count': 3}
        ..tags = {'source': 'https://nas.local'};

      final redacted = (await redactSentryEvent(event, Hint()))!;

      // ignore: deprecated_member_use
      expect(redacted.extra, {'file': '[redacted]', 'count': 3});
      expect(redacted.tags, {'source': '[redacted]'});
    });

    test('drops every event while error reporting is switched off', () async {
      setErrorReportingEnabled(false);

      expect(await redactSentryEvent(buildEvent(), Hint()), isNull);
    });

    test('keeps events while error reporting is switched on', () async {
      setErrorReportingEnabled(true);

      expect(await redactSentryEvent(buildEvent(), Hint()), isNotNull);
    });
  });

  group('configureErrorReporting', () {
    test('sets the privacy and sampling policy', () {
      final options = SentryFlutterOptions();
      configureErrorReporting(options);

      expect(options.dsn, kGlitchTipDsn);
      expect(options.sendDefaultPii, isFalse);
      expect(options.tracesSampleRate, 0);
      expect(options.enableAutoPerformanceTracing, isFalse);
      expect(options.beforeSend, redactSentryEvent);
      expect(options.environment, 'debug');
    });
  });
}
