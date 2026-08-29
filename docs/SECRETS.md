# Secrets & Konfiguration

## Relay-Server (`relay_server/.env`)

Vorlage: `relay_server/.env.example`. Diese Datei wird nie eingecheckt (`.env` steht in `relay_server/.gitignore`). Vor dem ersten produktiven Start `cp relay_server/.env.example relay_server/.env` und alle Werte anpassen. Der Server verweigert den Start (Fail-Fast), wenn sicherheitskritische Werte leer oder auf einem offensichtlichen Default belassen wurden (`JWT_SECRET`, `ADMIN_PASSWORD`).

| Key | Erklärung |
|---|---|
| `PORT` | TCP-Port, auf dem der Relay-Server intern lauscht (Standard `8080`). Wird über `docker-compose.yml` nach außen gemappt. |
| `PUBLIC_URL` | Die von außen erreichbare Basis-URL des Servers (z.B. `https://mein-relay.example.com` oder `http://<lan-ip>:8080`). Wird in QR-Code-Deep-Links (`photoframe://pair?u=<PUBLIC_URL>&c=<code>`) sowie in absoluten Links/Antworten verwendet. Muss von den paarenden Geräten aus erreichbar sein. |
| `DATA_DIR` | Verzeichnis für die SQLite-Datenbank, den Content-Addressed Blob-Store (`blobs/`) und Backups. In Docker auf das gemountete Volume `/data` gesetzt. |
| `JWT_SECRET` | Signaturschlüssel für Access-/Refresh-JWTs. Muss ein langer, zufälliger String sein (mind. 32 Zeichen), z.B. erzeugt mit `openssl rand -base64 48`. **Niemals** den Beispielwert übernehmen – bei Kompromittierung lassen sich beliebige Tokens fälschen. |
| `PAIRING_CODE_PEPPER` | Optionaler separater Pepper für das HMAC-Hashing von Pairing-Codes (`pairing_codes.code_hash`). Bleibt das Feld leer, wird der Pepper aus `JWT_SECRET` abgeleitet. Für zusätzliche Schlüsseltrennung empfiehlt sich ein eigener, unabhängiger Zufallswert. |
| `ADMIN_USERNAME` | Login-Name für das Admin-Panel (`/admin`), getrennt von der normalen Nutzer-Authentifizierung. |
| `ADMIN_PASSWORD` | Passwort für das Admin-Panel. Muss stark und einzigartig sein – das Admin-Panel erlaubt u.a. das Löschen von Nutzern/Frames und das Umschalten der Registrierung. |
| `REGISTRATION_ENABLED` | `true`/`false`. Schaltet die offene Selbstregistrierung frei. Ein WAN-erreichbarer Server mit dauerhaft offener Registrierung ohne Invite-Code ist praktisch ein öffentliches Filedrop – für den produktiven Dauerbetrieb sollte entweder `false` gesetzt oder `REGISTRATION_INVITE_CODE` genutzt werden. |
| `REGISTRATION_INVITE_CODE` | Optionaler Invite-Code, der bei der Registrierung zusätzlich angegeben werden muss, wenn `REGISTRATION_ENABLED=true`. Leer = Registrierung für jeden offen, der die `PUBLIC_URL` kennt. |
| `MAX_UPLOAD_BYTES` | Maximale Dateigröße pro Bild-Upload in Bytes (Standard-Beispielwert 15 MB). Wird sowohl in `multer`-Limits als auch bei einer Content-Length-Vorprüfung durchgesetzt. |
| `BACKUP_RETENTION_DAYS` | Anzahl Tage, für die automatische SQLite-Backups (`db.backup()`, nächtlicher Cron im Container) aufbewahrt werden, bevor sie rotiert/gelöscht werden. |

Zusätzliche, in `.env.example` bereits vorbereitete Werte (nicht explizit in der Aufgabenstellung genannt, aber Teil des aktuellen Scaffolds – siehe `relay_server/.env.example` für den aktuellen Stand): `JWT_ACCESS_TTL`, `JWT_REFRESH_TTL`, `MAX_IMAGES_PER_PAIRING`, `MAX_STORAGE_BYTES_PER_USER`, `NODE_ENV`. Sollte sich der tatsächliche Inhalt von `relay_server/.env.example` ändern, ist diese Tabelle entsprechend nachzuziehen.

---

## Store-Deployment-Secrets

**WICHTIG: Diese Secrets sind hier bewusst NICHT gesetzt und wurden NICHT erfunden.** Es handelt sich ausschließlich um Platzhalter/Beschreibungen, welche Werte später vom Nutzer selbst beschafft und ausschließlich als **GitHub Actions Repository Secrets** (Repo-Settings → Secrets and variables → Actions) hinterlegt werden müssen – niemals im Repository selbst, niemals in Klartext-Dateien. Referenziert von `.github/workflows/release.yml`.

| Secret | Beschreibung | Quelle |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Base64-kodierter Inhalt der `.jks`-Keystore-Datei für die Android-App-Signierung. | Selbst mit `keytool` erzeugter Release-Keystore; base64-kodieren mit z.B. `base64 -w0 release.keystore.jks`. |
| `ANDROID_KEYSTORE_PASSWORD` | Passwort des Android-Keystores. | Beim Erzeugen des Keystores selbst vergeben. |
| `ANDROID_KEY_ALIAS` | Alias des Signierschlüssels innerhalb des Keystores. | Beim Erzeugen des Keystores selbst vergeben. |
| `ANDROID_KEY_PASSWORD` | Passwort des einzelnen Schlüssels (kann vom Keystore-Passwort abweichen). | Beim Erzeugen des Keystores selbst vergeben. |
| `GOOGLE_PLAY_JSON_KEY` | Service-Account-JSON-Schlüssel mit Berechtigung für den Play-Console-Upload (für `upload_to_play_store`/Fastlane `supply`). | Google Play Console → Setup → API access → Service Account erstellen. |
| `APP_STORE_CONNECT_API_KEY_ID` | Key-ID des App Store Connect API Keys. | App Store Connect → Users and Access → Keys. |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer-ID zum App Store Connect API Key. | App Store Connect → Users and Access → Keys. |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Base64-kodierter Inhalt der `.p8`-Schlüsseldatei des App Store Connect API Keys. | App Store Connect, beim Erzeugen des Keys einmalig herunterladbar; base64-kodieren wie oben. |
| `MATCH_GIT_URL` | Git-URL eines privaten Repositories, in dem Fastlane `match` die iOS-Signierzertifikate/Provisioning-Profiles ablegt/verwaltet. | Vom Nutzer separat anzulegendes privates Repo (nicht `PhotoFrame` selbst). |
| `MATCH_PASSWORD` | Verschlüsselungspasswort für das `match`-Zertifikats-Repo. | Selbst beim Einrichten von `match` vergeben. |

Solange diese Secrets nicht gesetzt sind, bleiben die entsprechenden Jobs in `.github/workflows/release.yml` reine Platzhalter (siehe Kommentare dort) und der `ios-release`-Job kann ohnehin nur mit einem echten Apple-Developer-Account und einem `macos-latest`-Runner tatsächlich etwas bauen.
