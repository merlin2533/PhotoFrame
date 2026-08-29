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

- **Relay-Server** (`relay_server/`): Umsetzung läuft parallel in diesem Repo. Für den aktuellen Implementierungs- und Teststand (welche Routen/Features bereits fertig und verifiziert sind) siehe `relay_server/README.md` (falls vorhanden) bzw. die Commit-Historie des Relay-Server-Teils.
- **Flutter-App** (`mobile_app/`): bisher nur Domain-Fundament/Skeleton (Projektgerüst, keine vollständige Feature-Implementierung). Umfang und Reihenfolge der noch ausstehenden Meilensteine: [`docs/PLAN.md`](docs/PLAN.md).
- **CI** (`.github/workflows/`): Gerüst für `mobile_app`- und `relay_server`-Pipelines sowie eine Docker-Multi-Arch-Build-Probe liegt bereit; der `mobile_app`-Workflow wurde in dieser Session mangels verfügbarer Flutter-SDK nicht real gegen einen Runner ausgeführt.
- **Store-Release** (Android AAB / iOS IPA): `.github/workflows/release.yml` enthält ein Platzhalter-Gerüst für Fastlane-Lanes, ausgelöst durch Git-Tags (`v*`). Ein echter signierter Release folgt erst, sobald ein Android-Keystore bzw. ein Apple-Developer-Account/Zertifikate (Mac erforderlich) vorhanden sind – siehe [`docs/SECRETS.md`](docs/SECRETS.md) für die dafür benötigten (aktuell nicht gesetzten) Secrets.
