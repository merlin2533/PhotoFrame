# PhotoFrame

Digitale App für iOS und Android, die ein Smartphone/Tablet in einen digitalen Fotorahmen im Endlos-Modus verwandelt: Diashow aus verschiedenen Bildquellen (SMB, Nextcloud/WebDAV, lokaler Ordner), plus eine Sharing-/Pairing-Funktion, mit der gepaarte Frames sich gegenseitig Bilder über eine Hochladefunktion zuschicken können.

Der vollständige Architektur- und Umsetzungsplan steht in [`docs/PLAN.md`](docs/PLAN.md); Einzelentscheidungen samt Begründung in [`docs/DECISIONS.md`](docs/DECISIONS.md), ein Architekturüberblick in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Projektstruktur

```text
mobile_app/     Flutter-App (iOS + Android)
relay_server/   Node/TypeScript Relay-Server (Self-hosted Pairing-/Sharing-Backend)
docs/           Planung, Architektur, Secrets, Datenschutz-Vorlage
```

## Relay-Server lokal starten

Voraussetzung: Node.js 22+ (bzw. Docker, siehe unten).

```bash
cd relay_server
cp .env.example .env
# .env öffnen und mindestens JWT_SECRET / ADMIN_PASSWORD auf eigene, zufällige Werte setzen
npm install
npm run build
npm start
```

Alternativ per Docker Compose (empfohlen für den Dauerbetrieb, z.B. auf NAS/Raspberry Pi):

```bash
cd relay_server
cp .env.example .env
# .env anpassen wie oben
docker compose up -d
```

Details zu allen `.env`-Werten: [`docs/SECRETS.md`](docs/SECRETS.md). Datenschutz-Vorlage für Betreiber: [`docs/PRIVACY.md`](docs/PRIVACY.md).

## Flutter-App

Setup folgt noch vollständig – aktuell liegt unter `mobile_app/` das Domain-Fundament (Projektgerüst, `analysis_options.yaml`, `pubspec.yaml`). Für lokale Entwicklung wird eine installierte Flutter-SDK benötigt (`flutter pub get && flutter analyze && flutter test`). Details zum geplanten Funktionsumfang und den Meilensteinen: [`docs/PLAN.md`](docs/PLAN.md).

## Kiosk-/Autostart-Hinweis

Ein Fotorahmen soll nach dem Einschalten möglichst automatisch in die Diashow starten. Das stößt an echte Plattformgrenzen:

- **Android**: kein zuverlässiger Autostart über einen reinen Boot-Receiver (seit API 29 verboten). Die App registriert sich stattdessen als Home-App/Launcher + Screen-Pinning (Kiosk-Modus) – erfordert einmalige manuelle Auswahl als Standard-Startbildschirm.
- **iOS**: kein Autostart durch Drittanbieter-Apps möglich. Es bleibt nur der manuell vom Nutzer aktivierte "Geführte Zugriff"-Modus.

Details/Begründung: [`docs/DECISIONS.md`](docs/DECISIONS.md), ADR-004.

## Aktueller Umsetzungsstand

Ehrlich benannt nach der Code-Review-Backlog-Nacharbeit (siehe `docs/PLAN.md`, Abschnitt "Code-Review-Backlog") – dieser Abschnitt beschreibt, was tatsächlich implementiert und verifiziert ist, nicht nur geplant:

- **Relay-Server** (`relay_server/`): Kernrouten (Auth/Registrierung, Device-Tokens, Recovery, Pairing inkl. Create-Code/Redeem/Leave/Delete/Rename/Member-Entfernen, Content-Addressed Upload/Delete/Hide, Config-Push inkl. Reject-Endpunkt, Admin-API, Health) sind implementiert und per `npm run build && npm test && npm run lint` verifiziert. In dieser Runde zusätzlich geschlossen: Blob-Refcount- und `storage_used_bytes`-Lecks bei Pairing-/User-/Bild-Löschung (siehe `docs/DECISIONS.md` ADR-007), `commitBlob()` läuft jetzt in derselben Transaktion wie der `images`-Insert, Live-Updates (`album:updated`/`album:imageDeleted`) sind über Socket.IO verdrahtet (ADR-008), Pairing-Code-TTL korrekt auf 15 Minuten, `config_pushes.ciphertext` ist größenbegrenzt und ablehnbar, `backup.ts` überspringt Unterverzeichnisse. Test-Suite ist von 18 auf 40 Tests gewachsen, davon jetzt erstmals **HTTP-Level-Tests gegen die echte `createApp()`-Instanz** (`test/http/`), die die komplette Autorisierungsschicht (`authGuard`, Pairing-Mitgliedschaft, Uploader-vs.-Owner-Löschrechte) statt nur Hilfsfunktionen prüfen.
  - **Weiterhin bewusst offen** (siehe `docs/PLAN.md` Code-Review-Backlog für Details): Key-Fingerprint/TOFU-Verifikation und Member-Block-UI sind Gegenstand einer separaten, parallelen Bearbeitungsrunde – Stand dort bitte in der jeweiligen Historie/den zugehörigen ADRs prüfen, nicht hier. Socket-Mitgliedschaft wird nur beim Raumbeitritt geprüft, nicht bei jedem nachfolgenden Event (dokumentierte Grenze, kein Fix in dieser Runde). `client_upload_id` ist weiterhin global statt pro Frame/Pairing eindeutig. Der Redeem-Attempt-Zähler bremst Code-Guessing weiterhin nicht wirksam (jetzt explizit per Test sichtbar gemacht, `test/http/pairing.http.test.ts`).
  - **Nicht real gegen echte Hardware/Netzwerke getestet**: SMB-/Nextcloud-Verbindungen sind serverseitig gar nicht betroffen (laufen direkt vom Client), aber auch das Relay selbst läuft nur gegen eine temporäre SQLite-DB in der Sandbox – kein echtes Multi-Host-Deployment, kein echter Docker-Daemon-Lauf in dieser Runde verifiziert.
- **Flutter-App** (`mobile_app/`): Umfang/Fortschritt wird parallel von einer eigenen Bearbeitungsrunde getrieben (Domain-Fundament plus laufende Feature-Meilensteine, siehe `docs/PLAN.md`). Diese Runde hat den `mobile_app/`-Code nicht angefasst.
- **CI** (`.github/workflows/`): Gerüst für `mobile_app`- und `relay_server`-Pipelines sowie eine Docker-Multi-Arch-Build-Probe liegt bereit; der `mobile_app`-Workflow wurde in dieser Session mangels verfügbarer Flutter-SDK nicht real gegen einen Runner ausgeführt.
- **Store-Release** (Android AAB / iOS IPA): `.github/workflows/release.yml` referenziert bereits alle in `docs/PLAN.md` gelisteten Deployment-Secrets für beide Plattformen. **Noch fehlend**: `mobile_app/android/fastlane/{Fastfile,Appfile}` und `mobile_app/ios/fastlane/{Fastfile,Appfile}` selbst – die zugehörigen `android/`- bzw. `ios/`-Unterprojekte existieren zum Zeitpunkt dieser Runde noch nicht (sie entstehen erst durch `flutter create`/die parallele Flutter-Bearbeitungsrunde), weshalb das Fastlane-Gerüst bewusst noch nicht angelegt wurde, um keine mit dem generierten Projektskelett kollidierenden Verzeichnisse zu erzeugen. Ein echter signierter Release ist ohnehin erst möglich, sobald ein Android-Keystore bzw. ein Apple-Developer-Account/Zertifikate (Mac erforderlich) vorhanden sind – siehe [`docs/SECRETS.md`](docs/SECRETS.md) für die benötigten (aktuell nicht gesetzten) Secrets. Weder ein echter iOS-IPA- noch ein signierter Android-AAB-Build wurden in dieser Runde erzeugt.
