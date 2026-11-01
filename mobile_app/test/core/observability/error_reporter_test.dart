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
      const text =
          'Version 0.1.0+13 in main.dart, Fehler bei 1/2 am 12/05/2026';
      expect(scrubSensitiveText(text), text);
      expect(
        scrubSensitiveText(
            'Fehler in lib/core/x.dart:42 und package:app/y.dart'),
        'Fehler in lib/core/x.dart:42 und package:app/y.dart',
      );
    });

    test('redacts relative paths with spaces in quotes', () {
      expect(
        scrubSensitiveText('Foto "Urlaub 2023/Italien/IMG_1.jpg"'),
        'Foto "[redacted]"',
      );
      expect(
        scrubSensitiveText(r'Ordner "Fotos\Urlaub 2023" fehlt'),
        r'Ordner "[redacted]" fehlt',
      );
    });

    test('redacts unquoted relative paths with spaces ending in a photo', () {
      expect(
        scrubSensitiveText('Datei Urlaub 2023/Italien/IMG_1.jpg fehlt'),
        '[redacted] fehlt',
      );
    });

    test('redacts Windows paths with spaces up to the file name', () {
      expect(
        scrubSensitiveText(r'C:\Users\John Smith\Pictures\Urlaub 2023\a b.jpg'),
        '[redacted]',
      );
    });

    test('redacts POSIX paths with spaces up to the file name', () {
      expect(
        scrubSensitiveText(
            "path = '/data/user/0/app/files/My Photos/a.jpg' ok"),
        "path = '[redacted]' ok",
      );
      expect(
        scrubSensitiveText('path = /data/user/0/My Photos/a b.jpg ok'),
        'path = [redacted] ok',
      );
    });

    test('redacts a bare host after zu, host, server and address keywords', () {
      expect(
        scrubSensitiveText('Verbindung zu "nas" dauert zu lange'),
        'Verbindung zu "[redacted]" dauert zu lange',
      );
      expect(
        scrubSensitiveText('SMB authentication failed for "nas"'),
        'SMB authentication failed for "[redacted]"',
      );
      expect(
        scrubSensitiveText('Could not connect to SMB host "nas"'),
        'Could not connect to SMB host "[redacted]"',
      );
      expect(
        scrubSensitiveText('SMB-Host "nas" ist nicht erreichbar'),
        'SMB-Host "[redacted]" ist nicht erreichbar',
      );
      expect(
        scrubSensitiveText("Server 'nas' antwortet nicht"),
        "Server '[redacted]' antwortet nicht",
      );
      expect(
        scrubSensitiveText('address = nas, port = 445'),
        'address = [redacted], port = 445',
      );
      expect(
        scrubSensitiveText('host: nas'),
        'host: [redacted]',
      );
      expect(
        scrubSensitiveText('Host Nas-Synology'),
        'Host [redacted]',
      );
    });

    test('redacts user@host pairs', () {
      expect(scrubSensitiveText('Login user@nas fehlgeschlagen'),
          'Login [redacted] fehlgeschlagen');
    });

    test('redacts IPv6 addresses', () {
      expect(scrubSensitiveText('Ziel fe80::1 offline'),
          'Ziel [redacted] offline');
      expect(scrubSensitiveText('Ziel 2001:db8::1 offline'),
          'Ziel [redacted] offline');
      expect(scrubSensitiveText('Ziel [fe80::1]:445 offline'),
          'Ziel [[redacted]]:445 offline');
    });

    test('redacts realistic app messages', () {
      expect(
        scrubSensitiveText(
            'Verbindung zu "nas" dauert zu lange – Netzwerk oder Host prüfen'),
        'Verbindung zu "[redacted]" dauert zu lange – Netzwerk oder Host prüfen',
      );
      expect(
        scrubSensitiveText(r'Connected to \\nas\fotos'),
        'Connected to [redacted]',
      );
      expect(
        scrubSensitiveText(
            'Quelle übersprungen: Datei "Urlaub 2023/Italien/IMG_1.jpg" nicht lesbar'),
        'Quelle übersprungen: Datei "[redacted]" nicht lesbar',
      );
      expect(
        scrubSensitiveText(
            'Immich-Server antwortet nicht: http://192.168.1.20:2283/api'),
        'Immich-Server antwortet nicht: [redacted]',
      );
      expect(
        scrubSensitiveText('Fehler beim Skalieren von IMG_1234.heic'),
        'Fehler beim Skalieren von [redacted]',
      );
      expect(
        scrubSensitiveText(
            'Nextcloud: Verbindungstest zu "cloud.example.org" hat zu lange gedauert'),
        'Nextcloud: Verbindungstest zu "[redacted]" hat zu lange gedauert',
      );
      expect(
        scrubSensitiveText(
            'Konnte /storage/emulated/0/My Photos/a b.jpg nicht lesen'),
        'Konnte [redacted] nicht lesen',
      );
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

    test('scrubs an exception value that contains a path with spaces',
        () async {
      final event = SentryEvent(
        exceptions: [
          SentryException(
            type: 'FileSystemException',
            value:
                r'cannot open C:\Users\John Smith\Pictures\Urlaub 2023\a b.jpg',
          ),
          SentryException(
            type: 'FileSystemException',
            value: 'cannot read /data/user/0/My Photos/a b.jpg',
          ),
        ],
      );

      final redacted = (await redactSentryEvent(event, Hint()))!;

      expect(redacted.exceptions?[0].value, 'cannot open [redacted]');
      expect(redacted.exceptions?[1].value, 'cannot read [redacted]');
      expect(redacted.exceptions?[0].type, 'FileSystemException');
    });

    test('scrubs string and map values in contexts and clears identifiers',
        () async {
      final event = buildEvent()
        ..contexts['recovered'] = <String, String>{
          'message': 'Foto "Urlaub 2023/Italien/IMG_1.jpg" fehlt',
        }
        ..contexts['source'] = {'server': 'https://nas.local/dav'}
        ..contexts.device = SentryDevice(
          name: 'Markus Pixel',
          model: 'Pixel 8',
          deviceUniqueIdentifier: 'abc-123',
        );

      final redacted = (await redactSentryEvent(event, Hint()))!;

      expect(
        redacted.contexts['recovered'],
        {'message': 'Foto "[redacted]" fehlt'},
      );
      expect(redacted.contexts['source'], {'server': '[redacted]'});
      expect(redacted.contexts.device?.name, isNull);
      expect(redacted.contexts.device?.deviceUniqueIdentifier, isNull);
      expect(redacted.contexts.device?.model, 'Pixel 8');
    });

    test('drops debug images and scrubs stack frame paths', () async {
      final event = SentryEvent(
        threads: [
          SentryThread(
            stacktrace: SentryStackTrace(
              frames: [
                SentryStackFrame(
                  absPath: '/data/user/0/My Photos/a.dart',
                  fileName: 'main.dart',
                  function: 'load',
                ),
              ],
            ),
          ),
        ],
        debugMeta: DebugMeta(
          images: [DebugImage(type: 'elf', name: '/data/app/lib.so')],
        ),
      );

      final redacted = (await redactSentryEvent(event, Hint()))!;
      final frame = redacted.threads!.single.stacktrace!.frames.single;

      expect(redacted.debugMeta, isNull);
      expect(frame.absPath, '[redacted]');
      expect(frame.fileName, 'main.dart');
      expect(frame.function, 'load');
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
