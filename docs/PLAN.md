# PhotoFrame – iOS/Android App (v1 Voll-Scaffold)

## Context

Das Repo ist aktuell leer (nur `README.md` + `LICENSE`) – Greenfield-Projekt. Ziel: eine Cross-Platform-App, die ein Smartphone/Tablet in einen digitalen Fotorahmen im Endlos-Modus verwandelt:

1. **Diashow-Engine**: Zugriff auf SMB-Ordner (inkl. Unterordner), Laden von n Bildern, lokales Caching, zufällige Wiedergabe in einstellbarem Intervall. Ordnername immer unten rechts einblendbar (Setting an/aus). Verschiedene Anzeige-Modi, Cache-Verwaltung, Verbindungstests.
2. **Weitere Bildquellen**: Nextcloud (WebDAV); Google Drive vorerst zurückgestellt (siehe Entscheidung unten).
3. **Sharing/Pairing**: Ein "Frame" (App-Instanz im Diashow-Modus) kann mit einer anderen App-Instanz gepaart werden. Von dort hochgeladene Bilder erscheinen bei beiden Frames, sind jederzeit ansehbar und löschbar (Löschung propagiert überall).

Der Plan wurde in zwei Runden erarbeitet und durch ein **kritisches Gegenlesen mit Opus** (Architektur-Review) ergänzt, bevor Code geschrieben wird. Das hat mehrere Architekturfehler aufgedeckt, die jetzt (statt später als Breaking Change) korrigiert sind – siehe "P0-Entscheidungen" und die überarbeiteten Interfaces/Datenmodelle unten.

### P0-Entscheidungen (mit Nutzer abgestimmt)

- **Google Drive wird aus v1 gestrichen.** Grund: automatischer Ordner-Abgleich braucht den restricted OAuth-Scope `drive.readonly`, der eine kostenpflichtige jährliche CASA-Sicherheitsprüfung durch Google voraussetzt; ohne Verification bleibt die App auf 100 Testnutzer begrenzt. Google Drive wird als spätere Ausbaustufe dokumentiert (zwei Optionen, siehe "Google Drive – zurückgestellt" am Ende), aber die `PhotoSource`-Abstraktion wird so gebaut, dass es sich nahtlos nachrüsten lässt.
- **Vertriebsweg: perspektivisch Play Store / App Store.** Damit sind ab Tag 1 verpflichtend: Datenschutzerklärung (`docs/PRIVACY.md`), i18n (mind. DE/EN, keine hartcodierten Strings), sauberer Umgang mit Berechtigungen/Data-Safety-Angaben, HTTPS-Erzwingung für die Relay-Basis-URL mit explizitem LAN-Opt-out (Android `usesCleartextTraffic`, iOS ATS-Ausnahme nur für private IP-Ranges).
- **SMB-Machbarkeit wird als Spike vorgezogen** (vor dem Rest der Quellen-Implementierung): `samba-browser-flutter`/`libdsm`-Wrapper sind wenig gepflegt, iOS-SMB-Unterstützung historisch dünn. Ein Tag Zeitbudget für einen Verbindungstest gegen ein echtes Share auf Android **und** iOS, bevor M3 (SMB-Quelle) voll umgesetzt wird. Fallback: Nextcloud/WebDAV wird primäre Fernquelle, zusätzlich wird eine **`LocalFolderSource`** ergänzt (Dateien direkt vom Gerät/USB-Stick über SAF/`file_picker`) – zuverlässigste, günstigste Quelle, die im ursprünglichen Plan komplett fehlte.
- **Autostart/Kiosk-Modus ehrlich modellieren.** Android verbietet seit API 29 das Starten von Activities aus dem Hintergrund – ein reiner `BOOT_COMPLETED`-Receiver startet die App **nicht** zuverlässig. Realistischer Ansatz: App registriert sich als **Home-App/Launcher** (`CATEGORY_HOME`-Intent-Filter) → startet automatisch nach Boot, kombiniert mit Screen-Pinning (`startLockTask`). iOS: kein Autostart möglich, nur manueller "Geführter Zugriff" – wird in README/Architektur klar als Plattformgrenze dokumentiert, um keine falsche Erwartung zu wecken.

### Weitere bereits abgestimmte Entscheidungen

- **Framework: Flutter** – eine Codebasis für iOS+Android.
- **Sharing-Backend: kein Firebase/BaaS**, sondern ein **eigener self-hosted Relay-Server** als **Docker-All-in-one-Image mit genau einem Port**, eingebetteter SQLite-DB, kleinem Admin-Panel + Benutzerverwaltung, Registrierung ohne große Hürden, konfigurierbare Basis-URL, saubere `docker-compose.yml` + `.env.example` für alle Secrets.
- **State-Management App: Riverpod.**
- **Umfang dieser Runde**: voller Funktions-Scaffold, weitere Härtung (P2-Liste unten) folgt bewusst später.

**Kurze Konkurrenzrecherche** (fließt in UX ein): Frameo (kostenlos, Cloud-Relay, Pairing-Code, Duplikat-Vermeidung, Video-Clips), Nixplay (mehrere Frames/Account, Cloud-Integrationen), Skylight (E-Mail-zu-Frame, Abo-gated), Pix-Star (App/Web/E-Mail-Upload). Übernommen: Pairing-Code + QR, Blur-Fill-Hintergrund für Hochkantbilder, Uhr-Overlay, Nachtmodus – jetzt gegen den eigenen Relay-Server statt Firebase umgesetzt.

## Architekturüberblick

```
 [Handy A: PhotoFrame-App]                [Handy/Tablet B: PhotoFrame-App im Frame-Modus]
        |  REST + WebSocket (JWT)                  |  REST + WebSocket (JWT)
        └───────────────┬───────────────────────────┘
                         v
              [Relay-Server: 1 Docker-Container]
              - Express/Node API (versioniert /api/v1)
              - Socket.IO (authentifizierte Rooms, Realtime-Push)
              - SQLite/WAL (Users, Device-Tokens, Frames, Pairings, Bild-Metadaten)
              - Content-addressed Storage unter /data/blobs (Originale + Thumbnails)
              - Admin-Web-UI unter /admin (statisch, per adminGuard geschützt)
              - Backup-Skript (nächtlicher Cron im Container)
```

SMB, lokale Ordner und Nextcloud laufen **ohne** den Relay-Server – die App verbindet sich direkt vom Gerät aus. Der Relay-Server wird ausschließlich für Pairing/Sharing gebraucht.

## Repo-/Ordnerstruktur (Monorepo)

```
/README.md                                # Projektüberblick, Architektur, Setup, Kiosk-Anleitung
/.gitignore                               # Flutter + Node + Docker + IDE
/.github/workflows/
  mobile_app.yml                          # flutter analyze/test
  relay_server.yml                        # npm ci/build/test/lint
  docker.yml                              # buildx multi-arch Build-Probe (amd64+arm64)
  release.yml                             # bei Tag-Push: fastlane-Lanes für Android/iOS (Secrets aus GitHub Actions Secrets)
/docs/
  PLAN.md                                 # dieser komplette Plan, 1:1 ins Repo übernommen (Referenz für spätere Runden/Opus)
  ARCHITECTURE.md                         # PhotoSource-Abstraktion, Medien-Index, Pairing-Flow
  DECISIONS.md                            # ADRs: Framework, Relay statt Firebase, Drive zurückgestellt, Kiosk-Grenzen
  SECRETS.md                              # ALLE Keys/Secrets (Relay-.env UND Store-Deployment-Credentials), wo sie eingetragen werden
  PRIVACY.md                              # Datenschutz-Vorlage für Server-Betreiber (Store-Pflicht)

/mobile_app/                              # Flutter-Projekt (`flutter create mobile_app`)
  lib/
    main.dart
    app.dart                              # MaterialApp.router + go_router + ProviderScope + l10n
    l10n/                                 # ARB-Dateien (de, en)
    core/
      theme/app_theme.dart
      routing/app_router.dart             # /slideshow, /settings, /sources, /pairing
      errors/failure.dart                 # Fehler-Taxonomie: AuthError|NetworkError|NotFound|PermissionDenied|Unsupported|QuotaExceeded|Timeout
      utils/{result.dart, cancellation_token.dart}
    features/
      slideshow/
        domain/{slideshow_engine.dart, shuffle_bag.dart, slideshow_config.dart, display_mode.dart, night_schedule.dart}
        presentation/{slideshow_screen.dart, widgets/{source_label_overlay.dart, clock_overlay.dart, slide_renderer.dart, touch_control_overlay.dart, empty_state_view.dart}}
        state/slideshow_providers.dart
      sources/
        domain/{photo_source.dart, photo_item.dart, photo_folder.dart, media_type.dart}
        local/local_folder_source.dart    # SAF/file_picker – zuverlässiger Fallback
        smb/{smb_photo_source.dart, smb_config_form.dart, smb_network_discovery.dart}
        nextcloud/{nextcloud_photo_source.dart, nextcloud_config_form.dart}
        shared_album/shared_album_photo_source.dart
        mock/mock_photo_source.dart
        source_registry.dart              # Pool aktiver Quellen + periodisches Auto-Refresh
        presentation/{source_list_screen.dart, add_source_screen.dart}
        state/sources_providers.dart
      index/
        media_index.dart                  # persistenter Index (drift/SQLite): Crawl, Query, Random-Sampling
        media_index_entry.dart            # path, size, mtime, hash, width, height, taken_at, orientation, last_seen_at
      playlists/
        playlist.dart                     # {id, name, sources[], folders[], filter, schedule?} – Modell jetzt, UI simpel
      pairing/
        domain/pairing_models.dart        # Frame, Pairing, SharedImage
        domain/pairing_repository.dart
        data/relay_pairing_repository.dart
        presentation/{relay_server_setup_screen.dart, pairing_screen.dart, pairing_qr_display_screen.dart, pairing_scan_screen.dart, shared_album_view_screen.dart, upload_screen.dart, recovery_code_screen.dart}
        state/pairing_providers.dart
      settings/
        domain/app_settings.dart
        presentation/settings_screen.dart
        state/settings_providers.dart
    services/
      cache/image_cache_manager.dart      # zweistufig: Thumbnail + Vollbild, LRU, "letzte N nie evicten"
      storage/{local_kv_store.dart, secure_credential_store.dart}  # secure_credential_store: SMB/Nextcloud-Passwörter
      connectivity/connectivity_service.dart  # online/degraded/offline-Zustandsmaschine
      relay/{relay_api_client.dart, relay_socket_client.dart, token_refresh_interceptor.dart}
      permissions/permission_service.dart
      logging/log_ring_buffer.dart        # On-Device-Log für "Logs teilen" (Diagnose bei wandmontiertem Gerät)
    state/providers.dart
  test/
    features/slideshow/{shuffle_bag_test.dart, slideshow_engine_test.dart}
    features/sources/mock_photo_source_test.dart
    features/pairing/fake_pairing_repository_test.dart
  pubspec.yaml
  analysis_options.yaml
  android/fastlane/{Fastfile, Appfile, metadata/android/de-DE/, metadata/android/en-US/}
  ios/fastlane/{Fastfile, Appfile, Matchfile, metadata/de-DE/, metadata/en-US/}

/relay_server/                            # Self-hosted Relay-Server (Node.js/TypeScript)
  Dockerfile                              # node:22-bookworm-slim (NICHT alpine, wegen sharp/better-sqlite3), non-root, HEALTHCHECK
  docker-compose.yml
  .env.example
  package.json / tsconfig.json
  src/
    index.ts                              # Express-Bootstrap, HTTP+Socket.IO auf gleichem Port, Fail-Fast bei Default-Secrets
    config/env.ts                         # lädt & validiert Env-Vars (zod)
    db/
      schema.sql
      migrations/                         # user_version-basierter Runner, Backup vor Migration
      pragmas.ts                          # WAL, synchronous=NORMAL, busy_timeout, foreign_keys=ON
    auth/
      userAuth.ts                         # Registrierung (Username+Passwort, bcrypt/argon2), Login, JWT+Refresh
      deviceTokens.ts                     # Device-Token-Ausstellung/-Widerruf (Frame ≠ Account)
      recovery.ts                         # Wiederherstellungscode-Flow für Geräteverlust/-wechsel
      adminAuth.ts
    routes/
      auth.ts, frames.ts
      pairing.ts                          # create-code/redeem/leave/delete/rename, Rollen owner|member
      images.ts                           # Upload/List/Delete, sichere Auslieferung (kein express.static)
      configPush.ts                       # POST /frames/:id/config-push, GET /frames/:id/config-pending (E2E-verschlüsselt)
      account.ts                          # DELETE /me (DSGVO Art.17), GET /me/export (Art.20)
      admin.ts                            # Users/Frames/Pairings/Storage, REGISTRATION_ENABLED-Toggle
      health.ts                           # GET /healthz, GET /version (+ minimum_supported_app_version)
    realtime/socket.ts                    # JWT im Handshake, Room-Join erst nach Mitgliedschaftsprüfung
    storage/
      contentAddressedStore.ts            # /data/blobs/ab/cd/<hash>, Refcount vor unlink, Dedup pro Pairing
      thumbnails.ts                       # sharp: rotate(), limitInputPixels, EXIF-GPS-Strip
    middleware/{authGuard.ts, adminGuard.ts, quota.ts, rateLimit.ts}
    backup.ts                             # db.backup()-Skript, Cron, BACKUP_RETENTION_DAYS
  public/admin/                           # statische Admin-UI (Vanilla JS + fetch), CSRF-Token, httpOnly/SameSite-Cookie
    index.html, login.html, admin.js, admin.css
```

## State Management (App): Riverpod

`flutter_riverpod` (ohne Codegen in v1). `relay_socket_client.dart` liefert Realtime-Events als `StreamProvider`; Provider-Overrides erlauben Mocking von `PhotoSource`/`PairingRepository` in Tests; `ProviderContainer` für Unit-Tests von `SlideshowEngine`/`ShuffleBag` ohne Widget-Tree.

## PhotoSource-Abstraktion (überarbeitet nach Review)

```dart
abstract class PhotoSource {
  String get id;
  String get displayName;
  SourceType get type;                    // smb, nextcloud, local, sharedAlbum, mock (googleDrive später)
  Future<Result<ConnectionStatus>> testConnection({Duration timeout = const Duration(seconds: 8)});
  Stream<Result<PhotoFolder>> listFolders({PhotoFolder? parent, CancellationToken? token});
  Stream<Result<PhotoItem>> listImages(PhotoFolder folder, {bool recursive = true, CancellationToken? token});
  Future<Result<File>> fetchToCache(PhotoItem item, {CancellationToken? token}); // NICHT Uint8List – OOM-Risiko bei großen Fotos
  Stream<void> get changes;
  Future<void> dispose();
}
```

Wichtigste Korrekturen gegenüber der ersten Fassung: **Stream statt Future/List** für Listing (rekursives Scannen tausender SMB-Dateien braucht Fortschritt/Abbruch, kein blockierendes Warten), **`File` statt `Uint8List`** für Bildabruf (kein Voll-Decode großer Fotos in den Heap), **`CancellationToken` + Timeout überall** (sonst friert die Diashow bei WLAN-Verlust ein, weil Sessions hängen). Implementierungen: `SmbPhotoSource`, `NextcloudPhotoSource`, `LocalFolderSource`, `SharedAlbumPhotoSource`, `MockPhotoSource`.

## Persistenter Medien-Index

Live-Listing bei jedem Diashow-Start skaliert nicht (tausende SMB-Dateien). Stattdessen: `features/index/media_index.dart` mit lokaler SQLite-Tabelle (Paket `drift`) `media_index_entry(source_id, path, name, size, mtime, content_hash, width, height, taken_at, orientation, last_seen_at, cache_state)`. Ein inkrementeller Crawl je Quelle (Ordner-`mtime` als Skip-Heuristik, gelöschte Dateien über veraltetes `last_seen_at` erkannt) füllt den Index; die Diashow zieht Random-Rows direkt aus dem Index. Voraussetzung für: Hochkant-Paar-Layout (Breite/Höhe vorab bekannt), Favoriten, Datumsfilter, performantes Zufalls-Sampling ohne Netzwerk-Roundtrip pro Bild.

## Playlist-Modell (Schema jetzt, UI später)

`playlists/playlist.dart`: `Playlist { id, name, sources: List<sourceId>, folders: List<PhotoFolder>, filter: {favoritesOnly, dateRange, excludeIds}, schedule: TimeRange? }`. v1-UI bleibt einfach (eine aktive "Standard-Playlist" = aktuell konfigurierte Quellen), aber das Datenmodell wird jetzt so geschnitten, dass mehrere Playlists/Zeitpläne später ohne Rewrite ergänzt werden können.

## Diashow-Engine

- **`ShuffleBag`** (statt naivem `Random()`): persistierte Permutation ohne Zurücklegen pro Zyklus, zusätzlich Regel "nicht dasselbe Bild innerhalb der letzten X Anzeigen".
- **`SlideshowEngine`**: hält `currentItem`, prefetcht die nächsten 2–3 Items über `ImageCacheManager`, Timer mit konfigurierbarem Intervall löst Wechsel aus.
- **`ImageCacheManager`** (zweistufig): Thumbnail-Cache (~400px) für schnelle Vorschau/Overlay-Fälle, Vollbild-Cache (auf Displaygröße downscaliert beim Cachen) mit LRU-Eviction gegen konfigurierbares Größenlimit; die zuletzt erfolgreich angezeigten N Bilder werden **nie** evicted (Offline-Reserve, falls alle Quellen gleichzeitig unerreichbar sind).
- **`SourceLabelOverlay`** + **`ClockOverlay`** unten rechts/links, je per Setting ein-/ausblendbar.
- **Touch-Bedienung**: Tap → Overlay mit Pause/Weiter/Zurück/Info/Favorit; Doppeltap → Favorit; langer Druck → Settings (optional PIN-geschützt, damit Gäste nichts verstellen).
- **Nachtmodus/Zeitplan**: konfigurierbare Zeitspanne oder lokale Sonnenauf-/-untergangsberechnung (ohne Netz) dimmt Helligkeit (`screen_brightness`) oder blendet ein dunkles Overlay ein; Wake-on-Tap. Echtes Display-Aus ist für Drittanbieter-Apps technisch nicht möglich – wird so dokumentiert.
- **Offline-Zustandsmaschine** (`online/degraded/offline` in `connectivity_service.dart`): Diashow läuft zu 100 % aus dem lokalen Cache weiter, Sync-Fehler führen nie zu schwarzem Bildschirm, exponentielles Backoff, dezentes Status-Icon statt Fehlerdialog.
- **Barrierefreiheit**: "Bewegung reduzieren" (System-Setting) schaltet Ken-Burns/Übergänge automatisch ab (vestibuläre Beschwerden).

### Anzeige-Modi (Bilddarstellung)

- **Skalierung**: `contain`, `cover`, `blurredBackground` (Bild `contain` vor unscharfem, hochskaliertem Hintergrund desselben Bildes – löst Hochkant-auf-Querformat ohne harte Balken, Look von Aura/Frameo).
- **Übergänge**: `fade`, `slide`, `none` – austauschbare Strategie über `AnimatedSwitcher`/`PageView`, keine Zusatzpakete.
- **Ken-Burns-Effekt**: optionaler langsamer Zoom/Pan (`AnimationController`), abschaltbar (auch automatisch bei "Bewegung reduzieren").
- **Hochkant-Paar-Layout**: zwei aufeinanderfolgende Hochkant-Bilder nebeneinander, basierend auf Orientation-Daten aus dem Medien-Index.
- Umsetzung: `slideshow/domain/display_mode.dart` + `slideshow/presentation/widgets/slide_renderer.dart`.

### Cache-Verwaltung

- Settings zeigt Cache-Größe pro Quelle + gesamt, Schieberegler für Limit (z. B. 100 MB–5 GB), LRU-Eviction beim Überschreiten (Offline-Reserve ausgenommen).
- Buttons "Cache leeren" (gesamt) und pro Quelle; automatische Bereinigung beim Entfernen einer Quelle.

### SMB-Netzwerk-Discovery

Statt die Host-IP manuell einzutippen, bekommt `smb_config_form.dart` einen Button "Netzwerk durchsuchen": mDNS-Suche nach `_smb._tcp.local` (Paket `multicast_dns`, für moderne NAS/Samba-Avahi-Setups) sowie NetBIOS-Namensauflösung als Fallback für ältere Windows-Freigaben; Ergebnis ist eine Liste erkannter Hosts zur Auswahl statt Freitext-Eingabe. Reine Komfortfunktion – manuelle IP-Eingabe bleibt immer möglich, falls Discovery nichts findet (z. B. wegen Multicast-Einschränkungen im WLAN).

### Verbindungstests

- Jedes Quellen-Konfigurationsformular bekommt "Verbindung testen" (`testConnection()`) mit Klartext-Fehlermeldung (Host nicht erreichbar / Zugangsdaten falsch / Ordner nicht gefunden) statt generischem Fehler.
- `source_list_screen.dart` zeigt Status-Ampel pro Quelle (aus letztem Auto-Refresh) + manuellem Retry.
- Relay: `GET /api/v1/health` (offen, liefert Version+Status) für einen Schnellcheck vor Login/Registrierung.

## Relay-Server: Datenmodell & Ablauf (überarbeitet nach Review)

**SQLite-Tabellen (WAL-Modus, `foreign_keys=ON`):**
- `users(id, username UNIQUE, password_hash, created_at)`
- `device_tokens(id, frame_id, token_hash, last_seen_at, revoked_at)` – **Account und Gerät getrennt**: ein Reinstall/Geräteverlust darf nicht automatisch den Account/die Pairings vernichten; erlaubt außerdem "Gerät abmelden"/Fernsperre statt eines nicht widerrufbaren Dauer-JWTs
- `frames(id, user_id, display_name, public_key, created_at, last_seen_at)` – `last_seen_at` wird bei jedem Socket-Connect/Heartbeat aktualisiert; `public_key` für die Fernkonfiguration (siehe unten)
- `config_pushes(id, target_frame_id, sender_frame_id, ciphertext, created_at, applied_at, rejected_at)`
- `pairing_codes(code_hash, pairing_id, expires_at, consumed_at, attempt_count)` – Code selbst nie im Klartext gespeichert
- `pairings(id, name, created_at)`
- `pairing_members(pairing_id, frame_id, role)` – Rolle `owner|member`
- `images(id, pairing_id, uploaded_by_frame_id, content_hash, uploaded_at, width, height, client_upload_id UNIQUE)` – Pfade liegen NICHT hier, sondern werden aus `content_hash` abgeleitet (Content-Addressed Storage, siehe unten)

**Account-Recovery** (wichtigster Fund des Reviews): Automatische Registrierung beim ersten Start bleibt reibungslos (App generiert Username+Passwort selbst), aber nach dem ersten Pairing bietet die App aktiv **"Wiederherstellungscode anzeigen"** an (`recovery_code_screen.dart`) und einen Flow "Auf neuem Gerät anmelden" (`POST /api/v1/auth/recover`, rate-limited) – ohne das ist ein Reinstall gleichbedeutend mit permanentem Verlust aller geteilten Bilder/Pairings.

**Ablauf:**
1. **Registrierung**: `POST /api/v1/auth/register` (Username+Passwort, App-generiert) → JWT (kurzlebig) + Refresh-Token via `flutter_secure_storage`; `token_refresh_interceptor.dart` erneuert es transparent (relevant, da die App wochenlang durchläuft).
2. **Pairing erzeugen**: `POST /api/v1/pairing/create-code` → Code als Crockford-Base32 (~40 Bit Entropie), **nur gehasht gespeichert**, 15 Min TTL, max. 5 Fehlversuche (`attempt_count`), danach verbrannt; QR kodiert Relay-URL **und** Code als Deep-Link (`photoframe://pair?u=<relay>&c=<code>`), damit die Server-Adresse nicht manuell abgetippt werden muss; einladender Frame zeigt Bestätigungsdialog "Gerät XY möchte beitreten".
3. **Pairing beitreten**: `POST /api/v1/pairing/redeem`, constant-time Vergleich, Rate-Limit pro IP **und** pro Konto.
4. **Upload**: Client komprimiert, berechnet `content_hash`, lädt via `multer` `diskStorage` in ein tmp-Verzeichnis auf demselben Volume, dann atomares `rename` in den Content-Addressed Store (`/data/blobs/ab/cd/<hash>`, Refcount statt Duplikat – verhindert den Bug, dass ein `DELETE` versehentlich eine von mehreren Referenzen gemeinsam nutzende Datei für alle löscht); `client_upload_id` macht Retries nach Netzabbruch idempotent. `sharp` re-encoded (`.rotate()`, `limitInputPixels` gegen Decompression-Bombs), strippt EXIF-GPS, erzeugt Thumbnail. Server broadcastet `album:updated` per Socket.IO (Raum `pairing:<id>`, Beitritt erst nach serverseitiger Mitgliedschaftsprüfung im Handshake) an alle Mitglieder außer Uploader.
5. **Ansehen/Löschen**: `GET /api/v1/pairing/:id/images` + Socket-Live-Updates; `DELETE .../images/:id` nur durch Uploader oder `owner`-Rolle (globales Löschen), jedes Mitglied kann lokal ausblenden; propagiert per `album:imageDeleted`.
6. **Pairing/Konto-Lifecycle** (fehlte komplett in der ersten Fassung): `DELETE /pairings/:id/members/:frameId` (Selbst-Verlassen), `DELETE /pairings/:id` (Owner, kaskadiert Bilder), Umbenennen, `DELETE /me` (DSGVO Art. 17, kaskadiert alles), `GET /me/export` (Art. 20).
7. **Bildauslieferung**: **kein** `express.static` auf `/data`; `GET /images/:id/file` geht durch `authGuard` + Mitgliedschaftsprüfung, Dateinamen ausschließlich serverseitig generiert (kein Path Traversal).
8. **Frame-Online-Status**: jeder verbundene Socket aktualisiert `frames.last_seen_at`; `GET /api/v1/pairing/:id` liefert pro Mitglied `online` (aktive Socket-Verbindung im Speicher) und `lastSeenAt`. `pairing_screen.dart`/`shared_album_view_screen.dart` zeigen eine Online/Offline-Ampel pro gepaartem Frame samt "zuletzt aktiv vor X" – nützlich, um zu erkennen, ob ein Upload beim Empfänger überhaupt zeitnah ankommt.
9. **Frame-Fernkonfiguration** (z. B. SMB-Zugangsdaten vom Handy auf den Frame pushen, statt sie auf einem Tablet ohne Tastatur einzutippen) – läuft **über den bestehenden Relay-/Pairing-Account**, aber Ende-zu-Ende-verschlüsselt, damit der Relay-Betreiber niemals Klartext-Zugangsdaten sieht: Jeder Frame erzeugt bei der Registrierung ein Schlüsselpaar (`crypto_box`/libsodium sealed box, z. B. via `cryptography`/`sodium_libs`) und hinterlegt nur den **öffentlichen** Schlüssel als `frames.public_key`. Zum Konfigurieren verschlüsselt das sendende Handy den Source-Config-Payload (SMB-Host/Freigabe/Zugangsdaten) mit dem öffentlichen Schlüssel des Ziel-Frames und schickt ihn an `POST /api/v1/frames/:id/config-push` (nur erlaubt, wenn Sender und Ziel-Frame gemeinsam in mindestens einem Pairing sind) → Server speichert nur das Chiffrat in `config_pushes` und benachrichtigt den Ziel-Frame per Socket.IO (`config:pending`) oder beim nächsten Verbindungsaufbau, falls offline. Der Ziel-Frame entschlüsselt lokal mit seinem privaten Schlüssel, zeigt einen Bestätigungsdialog ("Neue SMB-Quelle von Handy XY übernehmen?") und wendet die Konfiguration erst nach Zustimmung an (`applied_at`) bzw. verwirft sie (`rejected_at`) – nie automatisch, um ein Kapern des Frames über einen kompromittierten gepaarten Account zu verhindern.
10. **Admin-Panel** (`/admin`, separater Login aus `ADMIN_USERNAME`/`ADMIN_PASSWORD`): Users/Frames/Pairings/Storage-Verbrauch, Nutzer/Frame löschen, **`REGISTRATION_ENABLED`/`REGISTRATION_INVITE_CODE`**-Toggle (ein WAN-erreichbarer Server mit dauerhaft offener Registrierung ist sonst ein öffentliches Filedrop). Admin-Session per `httpOnly/SameSite=Strict/Secure`-Cookie + CSRF-Token, `trust proxy` korrekt gesetzt (sonst greift Rate-Limiting hinter einem Reverse-Proxy nicht).

**Quotas & Missbrauchsschutz** (zwingend bei "Registrierung ohne Hürden", `content_hash`-Dedup allein schützt nicht vor Massen-Uploads unterschiedlicher Bilder): `MAX_UPLOAD_BYTES` (multer `limits.fileSize` + Content-Length-Vorprüfung), MIME-Whitelist, `storage_used_bytes` pro User (transaktional, 413 bei Überschreitung), Bildlimit pro Pairing, globaler `MAX_TOTAL_BYTES`, Upload-Rate-Limit pro Frame, optionale Retention (`RETENTION_DAYS`).

**Sicherheitsprinzipien:** bcrypt/argon2 für Passwörter, kurzlebiges JWT + widerrufbarer Refresh-Token (`device_tokens.revoked_at`), `authGuard` prüft Pairing-Mitgliedschaft pro Route, `adminGuard` getrennt vom User-Auth, `express-rate-limit` auf `/auth/*` und `/pairing/create-code`.

## Docker-Packaging

- **Dockerfile**: Multi-Stage, Basis-Image **`node:22-bookworm-slim`** (nicht Alpine – `bcrypt`/`better-sqlite3`/`sharp` sind native Module, auf musl/Alpine erfahrungsgemäß Dauerärger), non-root-User, `EXPOSE 8080`, `VOLUME /data`, `HEALTHCHECK` auf `GET /healthz`, **Fail-Fast beim Start**, wenn `JWT_SECRET`/`ADMIN_PASSWORD` leer oder ein Default-Wert sind.
- **Multi-Arch-Build** (`docker buildx`, amd64 **und** arm64) – Deployment auf NAS/Raspberry Pi ist ein realistischer Zielort für diesen Server.
- **docker-compose.yml**: ein Service, Port-Mapping `"${PORT:-8080}:8080"`, Volume `./data:/data`, `env_file: .env`.
- **.env.example**:
  ```
  PORT=8080
  PUBLIC_URL=https://mein-relay.example.com   # oder http://<lan-ip>:8080 – für QR-Deep-Links
  DATA_DIR=/data
  JWT_SECRET=change-me
  ADMIN_USERNAME=admin
  ADMIN_PASSWORD=change-me
  REGISTRATION_ENABLED=true
  REGISTRATION_INVITE_CODE=                   # optional, leer = offen
  MAX_UPLOAD_BYTES=26214400
  BACKUP_RETENTION_DAYS=14
  ```
- **Backup**: `src/backup.ts` nutzt SQLite `db.backup()` (kein `cp` im laufenden Betrieb), nächtlicher Cron im Container, dokumentierter Restore-Weg in README.
- **Migrationen**: `user_version`-basierter Runner beim Boot, idempotent, automatisches Backup vor jeder Migration.
- **API-Versionierung**: alle Routen unter `/api/v1`, `GET /version` liefert `minimum_supported_app_version`, damit alte Apps eine verständliche Meldung statt kryptischer Fehler bekommen.
- `docs/SECRETS.md` listet zusätzlich App-seitige Keys (aktuell keine zwingend nötig, da Google Drive zurückgestellt ist – Platzhalter-Abschnitt für spätere Google-OAuth-Client-IDs bleibt vorbereitet).

## Wichtige Pakete

- SMB: `samba-browser-flutter`/`libdsm`-Wrapper (Risiko, s. SMB-Spike oben), Fallback-Quelle `file_picker`/SAF für `LocalFolderSource`, `multicast_dns` für Netzwerk-Discovery
- Fernkonfiguration/E2E-Verschlüsselung: `cryptography` (Dart, sealed-box-kompatible asymmetrische Verschlüsselung) für `config_pushes`-Payloads
- WebDAV/Nextcloud: `webdav_client`/`nextcloud`
- Lokaler Medien-Index: `drift` + `sqlite3_flutter_libs`
- Relay-Anbindung: `dio` (REST, mit Refresh-Interceptor), `socket_io_client`, `flutter_secure_storage` (JWT **und** SMB/Nextcloud-Zugangsdaten)
- State: `flutter_riverpod`
- QR: `qr_flutter`, `mobile_scanner`
- Wakelock: `wakelock_plus`; Helligkeit: `screen_brightness`
- Bildauswahl: `image_picker`
- Persistenz (Settings/einfache KV): `shared_preferences`
- i18n: `flutter_localizations` + ARB (de/en)
- Sonstiges: `path_provider`, `go_router`, `crypto`, `permission_handler`, `connectivity_plus`, `cached_network_image`, `uuid`, `flutter_image_compress`, optional `workmanager` (nur Android, für Hintergrund-Refresh – siehe Plattform-Besonderheiten)
- **Relay-Server**: `express`, `better-sqlite3`, `bcrypt` (oder `@node-rs/bcrypt` für bessere Bookworm-Kompatibilität), `jsonwebtoken`, `socket.io`, `multer`, `sharp`, `express-rate-limit`, `zod`, `dotenv`, `node-cron` (Backup)

## Plattform-Besonderheiten

- **Hintergrund-Sync-Mechanismus**: primär ein **Foreground-Timer** (die App läuft im Kiosk ohnehin dauerhaft im Vordergrund) für periodisches Auto-Refresh der Quellen; `workmanager` optional nur als Android-Zusatz, wenn die App mal nicht im Vordergrund ist; **iOS `BGTaskScheduler` wird bewusst nicht versprochen** (unzuverlässig für diesen Use-Case). Android zusätzlich: Prompt zur Battery-Optimization-Whitelist.
- **Kiosk/Autostart**: App als Home-App registrieren (`CATEGORY_HOME`) + `startLockTask` für Screen-Pinning (Android); iOS nur manueller "Geführter Zugriff", kein Autostart – siehe P0-Entscheidung oben.
- **iOS**: `wakelock_plus` statt Background-Modes. Info.plist: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSLocalNetworkUsageDescription`/`NSBonjourServices` (SMB im LAN), ATS-Ausnahme nur für private IP-Ranges.
- **Android**: Permissions `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CAMERA`, `READ_MEDIA_IMAGES` (API 33+); `permission_handler` mit einfacher Rationale.
- **Bilddateiformate**: EXIF-Orientation wird beim Cachen aktiv "eingebrannt" (`bakeOrientation`), da Flutter sie bei manuell dekodierten Bytes (SMB/WebDAV) nicht automatisch anwendet – sonst sind gedrehte Hochkantfotos der auffälligste Bug. HEIC/HEIF (typisch bei iPhone-Fotos auf NAS) wird über `flutter_image_compress` dekodiert oder, falls nicht unterstützt, sichtbar übersprungen (Hinweis statt stillem Schwarzbild); GIF/RAW werden erkannt und sauber gefiltert.
- **Betrieb des Relay-Servers**: empfohlen hinter eigenem Reverse-Proxy (Traefik/Caddy/Nginx) für HTTPS/WAN-Erreichbarkeit – dokumentiert in README, nicht Teil des Images.

## Deployment-Prozess (Fastlane)

Passend zur Entscheidung "perspektivisch über Play Store/App Store": Fastlane automatisiert Build, Signierung und Upload für beide Plattformen, damit ein Release nicht manuell aus Android Studio/Xcode gemacht werden muss.

- **Android** (`android/fastlane/Fastfile`): Lane `build` (`gradle("bundleRelease")`, Signierung über Keystore aus Env-Vars, niemals committed), Lane `beta` (`upload_to_play_store(track: "internal")`), Lane `release` (`upload_to_play_store(track: "production")`). Versionierung über `versionCode`/`versionName` aus `pubspec.yaml` bzw. Git-Tag abgeleitet.
- **iOS** (`ios/fastlane/Fastfile`): Lane `build` (`gym`, Signierung über `match` – Zertifikate liegen in einem separaten privaten Git-Repo, nicht in `PhotoFrame`), Lane `beta` (`pilot`/`upload_to_testflight`), Lane `release` (`deliver` für App-Store-Submission). **iOS-Lanes können in dieser Linux-Sandbox nicht ausgeführt werden** (kein Xcode/macOS) – Fastfile/Konfiguration wird als geprüftes Gerüst geliefert, der tatsächliche Lauf erfolgt auf einem macOS-Runner (z. B. GitHub Actions `macos-latest`).
- **CI-Anbindung**: `.github/workflows/release.yml` triggert bei Git-Tag (`v*`) die passenden Fastlane-Lanes; alle Store-Credentials kommen ausschließlich aus GitHub Actions Secrets (siehe unten), nie aus dem Repo.
- **Benötigte Deployment-Secrets** (Ergänzung zu `docs/SECRETS.md`, getrennt von den Relay-Server-Secrets):
  ```
  # Android
  ANDROID_KEYSTORE_BASE64=          # base64-kodierte .jks-Datei
  ANDROID_KEYSTORE_PASSWORD=
  ANDROID_KEY_ALIAS=
  ANDROID_KEY_PASSWORD=
  GOOGLE_PLAY_JSON_KEY=             # Service-Account-JSON für upload_to_play_store

  # iOS
  APP_STORE_CONNECT_API_KEY_ID=
  APP_STORE_CONNECT_API_ISSUER_ID=
  APP_STORE_CONNECT_API_KEY_BASE64=
  MATCH_GIT_URL=                    # privates Repo für Zertifikate/Profile
  MATCH_PASSWORD=
  ```
  Diese Werte übergibt der Nutzer sauber über GitHub Actions Secrets (Repo-Settings) bzw. lokal über `.env`/Fastlane `Appfile`-Umgebungsvariablen – nie hart codiert.
- **Umfang in dieser Runde**: Fastlane-Grundgerüst (Fastfile/Appfile je Plattform, Lanes definiert, CI-Workflow verdrahtet) wird aufgesetzt und so weit wie möglich verifiziert (`fastlane android build` im Trockenlauf ohne echte Signierung, sofern Android-SDK in der Sandbox verfügbar ist); echte Store-Uploads erfordern reale Entwickler-Accounts/Zertifikate und laufen erst außerhalb dieser Session.

## Meilensteine

1. **M0** – Scaffolding: `flutter create mobile_app`, `/relay_server`-Grundgerüst, `.gitignore`, `analysis_options.yaml`, `docs/PLAN.md` (dieser Plan wird 1:1 ins Repo committed), `docs/DECISIONS.md`, CI-Workflows-Gerüst
2. **M1** – SMB-Machbarkeits-Spike (Android + iOS gegen echtes Share) – Ergebnis entscheidet, ob SMB in M4 vollwertig oder nur "best effort" umgesetzt wird
3. **M2** – App-Grundgerüst: Theme, Navigation, `ProviderScope`, i18n-Grundgerüst (de/en)
4. **M3** – PhotoSource-Abstraktion (Stream/File/Cancellation-Version) + Medien-Index (`drift`) + Diashow-Engine mit `MockPhotoSource`, Unit-Tests `ShuffleBag`
5. **M4** – `LocalFolderSource` (zuverlässiger Fallback) + SMB-Quelle gemäß Spike-Ergebnis
6. **M5** – Nextcloud-Quelle (WebDAV, Config-UI, Verbindungstest)
7. **M6** – Settings-UI (Intervall, Overlay-Toggle, Anzeige-Modi/Übergänge/Ken-Burns/Hochkant-Paare/Blur-Fill, Nachtmodus, Cache-Verwaltung, Touch-Steuerung, Quellenverwaltung, Relay-Server-URL) + Verbindungstests überall
8. **M7** – Relay-Server: Auth/Registrierung, Device-Tokens + Recovery-Flow, Pairing-Routen (inkl. Leave/Delete/Rename/Rollen, Online-Status via `last_seen_at`), Content-Addressed Upload/Thumbnail/Delete, Config-Push-Endpunkte (E2E-verschlüsselt), Socket.IO mit Auth, Quotas/Rate-Limits/Invite-Code, Admin-API + Admin-UI, Backup, Migrationen, Docker-Packaging (Multi-Arch) + `docker-compose.yml` + `.env.example`
9. **M8** – Flutter-Pairing-Feature gegen Relay-Server: Server-URL-Setup, QR-Anzeige/Scan (inkl. Deep-Link), Wiederherstellungscode-Screen, `SharedAlbumPhotoSource`, Upload/View/Delete, Realtime, Online-Status-Anzeige gepaarter Frames, Fernkonfiguration (Schlüsselpaar-Erzeugung, Config-Push senden/empfangen mit Bestätigungsdialog), SMB-Netzwerk-Discovery (mDNS/NetBIOS) im Quellen-Formular
10. **M9** – Zusammenführung/Polish v1 + `README.md`/`docs/PLAN.md` (dieser Plan, committed)/`docs/ARCHITECTURE.md`/`docs/SECRETS.md`/`docs/PRIVACY.md`; explizit als "v1 – weitere Härtung siehe P2-Liste, folgt in separater Opus-Runde" markiert
11. **M10** – Fastlane-Grundgerüst (Android+iOS Fastfile/Appfile/Lanes) + `.github/workflows/release.yml`, Deployment-Secrets in `docs/SECRETS.md` dokumentiert

## Verifikation (in dieser Session möglich)

- **App**: `flutter pub get`, `flutter analyze`, `flutter test` (v. a. `shuffle_bag_test.dart`, `slideshow_engine_test.dart` mit `fake_async` gegen `MockPhotoSource`), `flutter build apk --debug`
- **Relay-Server**: `npm run build`, `npm test` (Pairing-Code-Ablauf/Hashing, Dedup/Refcount-Logik, Quota-Middleware, Auth-Middleware gegen Temp-SQLite), `npm run lint`
- **Docker**: `docker build`/`docker buildx` als Build-Probe, **sofern in dieser Sandbox ein Docker-Daemon verfügbar ist** – sonst explizit als "nicht verifiziert" vermerkt
- **Fastlane**: `fastlane android build` als Trockenlauf (sofern Android-SDK/Gradle in der Sandbox verfügbar ist, ohne echte Signierung/Upload); `fastlane ios ...` nur als Konfigurations-/Syntax-Check, kein echter Lauf möglich

**Nicht in dieser Sandbox testbar**: echte SMB-/Nextcloud-Verbindungen, echtes Deployment inkl. Reverse-Proxy/HTTPS, echtes iOS-Build (Linux-Sandbox, kein Xcode/macOS), echte Fastlane-Store-Uploads (fehlende reale Entwickler-Accounts/Zertifikate), physisches QR-Scannen zwischen echten Geräten, echte Kiosk-/Autostart-Konfiguration auf einem realen Tablet.

## P2 – Spätere Härtung (bewusst nicht in v1, aber Datenmodell kompatibel gehalten)

- Video-Clips (kurzer Loop wie bei Frameo) – `MediaType`-Enum in `PhotoItem` ist bereits vorgesehen, damit das kein Breaking Change wird
- Favoriten / "nie wieder zeigen" – stabile Item-IDs (`sourceId + pathHash`) jetzt festlegen, Feature später
- "Heute vor N Jahren"/Datumsfilter – kostenlos, sobald `taken_at` im Index liegt
- Wetter-Overlay (braucht externen API-Key)
- Certificate Pinning
- Crash-Reporting (opt-in), OSS-Lizenzseite (`showLicensePage`)

**Auf Nutzerwunsch nach v1 vorgezogen** (drei ursprünglich hier gelistete Punkte – siehe Detailbeschreibung in den jeweiligen Abschnitten oben): Frame-Fernkonfiguration über den Relay-Account, mDNS/NetBIOS-SMB-Discovery, Frame-Online-Status im Pairing-Screen.

## Google Drive – zurückgestellt

Zwei Optionen für eine spätere Runde, sobald der Vertriebsweg konkreter ist:
1. **`drive.file`-Scope**: kein Verification-Aufwand, aber nur einzeln per Google-Picker gewählte Dateien/Ordner – kein "automatisch jeden Ordner abgleichen".
2. **`drive.readonly`-Scope**: volle Funktionalität wie ursprünglich gewünscht, erfordert OAuth-Verification + laufendes CASA-Assessment – erst sinnvoll bei breiterer Verteilung über die Stores.

Die `PhotoSource`-Abstraktion ist so geschnitten, dass `GoogleDrivePhotoSource` ohne Änderungen am Rest der App nachgerüstet werden kann.
