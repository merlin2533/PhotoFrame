# Architektur-Überblick

Ausführliche Herleitung und weitere Details: `docs/PLAN.md`. Entscheidungsbegründungen: `docs/DECISIONS.md`.

## 1. PhotoSource-Abstraktion

Zentrale Schnittstelle für alle Bildquellen (SMB, Nextcloud/WebDAV, `LocalFolderSource`, gepaarte Alben, Mock):

```dart
abstract class PhotoSource {
  String get id;
  String get displayName;
  SourceType get type;
  Future<Result<ConnectionStatus>> testConnection({Duration timeout = const Duration(seconds: 8)});
  Stream<Result<PhotoFolder>> listFolders({PhotoFolder? parent, CancellationToken? token});
  Stream<Result<PhotoItem>> listImages(PhotoFolder folder, {bool recursive = true, CancellationToken? token});
  Future<Result<File>> fetchToCache(PhotoItem item, {CancellationToken? token});
  Stream<void> get changes;
  Future<void> dispose();
}
```

Designentscheidungen:
- **Stream statt Future/List** für Listing-Operationen, damit rekursives Scannen großer Verzeichnisse (tausende SMB-Dateien) Fortschritt liefert und abbrechbar bleibt, statt die UI blockierend warten zu lassen.
- **`File` statt `Uint8List`** für den Bildabruf, um volles In-Memory-Decoding großer Fotos (OOM-Risiko) zu vermeiden.
- **`CancellationToken` + Timeout überall**, damit die Diashow bei WLAN-Verlust nicht einfriert, weil eine Netzwerk-Session unbegrenzt hängt.
- `Stream<void> get changes` ist bewusst ehrlich benannt: SMB/WebDAV/SAF liefern in der Praxis keine Server-Push-Benachrichtigungen; der Stream bleibt für die meisten Quellen dauerhaft leer. Nur `SharedAlbumPhotoSource` (Relay-Anbindung) füllt ihn tatsächlich via Socket.IO. Die eigentliche periodische Aktualisierung aller anderen Quellen läuft über Polling (`source_registry.dart`), nicht über diesen Stream.

### UploadablePhotoSource (Fähigkeit statt Pflichtmethode)

Nicht jede Quelle kann beschrieben werden (viele SMB-Freigaben sind read-only gemountet, `LocalFolderSource` ist rein lokal). Statt Upload künstlich ins Basis-Interface zu zwingen, gibt es ein optionales Zusatz-Interface:

```dart
abstract class UploadablePhotoSource {
  bool get canUpload;
  Future<Result<void>> uploadImage(File file, {PhotoFolder? targetFolder});
}
```

`NextcloudPhotoSource` und `SharedAlbumPhotoSource` implementieren `PhotoSource` **und** `UploadablePhotoSource`. Die UI prüft einheitlich `source is UploadablePhotoSource && source.canUpload`, statt Sonderfälle pro Quellentyp zu kennen – neue schreibbare Quellen (z.B. später Google Drive mit `drive.file`-Scope) lassen sich ergänzen, ohne bestehende, nicht-schreibbare Quellen anzufassen.

### CacheLease-Konzept

`fetchToCache()` liefert das Bild in den `ImageCacheManager`, der Bilder per LRU evicten darf, sobald ein konfigurierbares Cache-Limit erreicht ist. Damit ein gerade angezeigtes oder vorausgeladenes Bild dabei nicht verschwindet, liefert `fetchToCache` zusätzlich ein `CacheLease`-Objekt mit `release()`:

- Solange eine Lease nicht freigegeben ist, zählt ein Pin-Counter im `ImageCacheManager` das zugehörige Bild als "in Benutzung" und schließt es von der Eviction aus.
- `SlideshowEngine` hält die Lease für das aktuell angezeigte Bild plus die vorausgeladenen 2–3 nächsten Bilder und gibt ältere Leases erst frei, nachdem der nächste Wechsel erfolgt ist.
- Zusätzlich zur Lease bleiben die zuletzt erfolgreich angezeigten N Bilder als Offline-Reserve grundsätzlich von der Eviction ausgenommen, falls alle Quellen gleichzeitig unerreichbar werden.

## 2. Medien-Index & Working-Set-Pool

### Persistenter Medien-Index

Live-Listing bei jedem Diashow-Start skaliert nicht. `features/index/media_index.dart` hält eine lokale SQLite-Tabelle (`drift`):

```
media_index_entry(source_id, path, name, size, mtime, content_hash, width, height,
                   taken_at, orientation, last_seen_at, cache_state)
```

Ein inkrementeller Crawl pro Quelle nutzt Ordner-`mtime` als Skip-Heuristik; gelöschte Dateien werden über veraltetes `last_seen_at` erkannt. Die Diashow zieht ihre Kandidaten direkt aus diesem Index statt live von der Quelle zu listen.

**`content_hash` wird lazy berechnet, nicht eager beim Crawl** – ein voller Read jeder Datei würde den Crawl bei tausenden SMB-Dateien unbrauchbar langsam machen. Änderungserkennung läuft stattdessen über `size + mtime` (zusätzlich `ETag`, falls die Quelle einen liefert, z.B. WebDAV). `content_hash` ist daher `nullable` und wird nachgetragen, sobald das Bild ohnehin beim ersten `fetchToCache()` komplett gelesen wird – kein zusätzlicher Roundtrip.

### Working-Set-Pool

Ein Random-Sample direkt über den gesamten Medien-Index (potenziell zehntausende Einträge über Jahre) lässt neue Bilder statistisch kaum auftauchen. Dazwischen sitzt `index/working_set_pool.dart`: eine begrenzte Arbeitsmenge in `pool_entries(source_id, item_id, added_to_pool_at, shown_count, last_shown_at)`, auf der die Diashow tatsächlich zufällig zieht.

- **Zielgröße**: Standard 1000 Einträge.
- **`newImageQuota`**: Standard 20 % des Pools reserviert für "neue" Bilder (`shown_count == 0` oder `added_to_pool_at` jünger als 30 Tage), damit frisch hinzugekommene Fotos zuverlässig zeitnah auftauchen statt im Zufalls-Rauschen unterzugehen.
- `pool_maintenance_job.dart` läuft als Foreground-Timer (Standardintervall stündlich, umschaltbar auf täglich): Crawl anstoßen → abgelaufene Einträge durch neue Kandidaten aus dem Medien-Index ersetzen, unter Berücksichtigung der `newImageQuota`. Zu wenige Kandidaten (kleine Quelle) ist kein Fehlerzustand, der Pool bleibt dann kleiner als die Zielgröße.
- Zusätzlicher ereignisgesteuerter Trigger: Sofortiges Refill, sobald der Pool nahezu erschöpft ist (< 10 % unverbrauchte Einträge), damit ein kurzes Diashow-Intervall nicht sichtbar vor dem nächsten geplanten Lauf wiederholt.
- `ShuffleBag` arbeitet auf dem `WorkingSetPool`, nicht auf dem Rohindex: persistierte Permutation ohne Zurücklegen über `pool_entries`, jede Anzeige erhöht `shown_count` und fließt direkt in die Auffüll-Logik zurück.

## 3. Pairing-Flow

1. **Code-Erzeugung**: `POST /api/v1/pairing/create-code` erzeugt einen Code als Crockford-Base32 (~40 Bit Entropie). Der Code selbst wird **nie im Klartext gespeichert** – gespeichert wird ausschließlich ein HMAC-Hash über einen serverseitigen Pepper (`PAIRING_CODE_PEPPER`, siehe `docs/SECRETS.md`) in `pairing_codes(code_hash, pairing_id, expires_at, consumed_at, attempt_count)`. TTL 15 Minuten, max. 5 Fehlversuche, danach verbrannt.
2. **Distribution**: QR kodiert Relay-URL **und** Code als Deep-Link (`photoframe://pair?u=<relay>&c=<code>`), damit die Server-Adresse nicht manuell abgetippt werden muss.
3. **Redeem**: `POST /api/v1/pairing/redeem` vergleicht den eingehenden Code konstant-zeitig gegen den gespeicherten Hash, rate-limited pro IP **und** pro Konto. Der einladende Frame zeigt einen Bestätigungsdialog ("Gerät XY möchte beitreten").
4. **Realtime via Socket.IO Rooms**: Nach erfolgreichem Pairing treten beide Frames dem Raum `pairing:<id>` bei – der Beitritt wird erst nach serverseitiger Mitgliedschaftsprüfung im Socket-Handshake gewährt (kein Raum-Beitritt allein durch Kenntnis der `pairing_id`). Uploads/Löschungen broadcasten `album:updated`/`album:imageDeleted` an alle Mitglieder außer dem Auslöser. Jeder verbundene Socket aktualisiert zusätzlich `frames.last_seen_at`, wodurch pro Mitglied ein Online/Offline-Status ableitbar ist.

## 4. Relay-Datenmodell (Überblick)

SQLite, WAL-Modus, `foreign_keys=ON`:

| Tabelle | Zweck |
|---|---|
| `users` | Account (Username, Passwort-Hash) |
| `frames` | Eine App-Installation im Frame-Modus; hält `public_key` für Config-Push (E2E-Verschlüsselung), `last_seen_at` |
| `device_tokens` | Trennung Account/Gerät: Refresh-Token pro Gerät, widerrufbar (`revoked_at`), erlaubt Fernabmeldung ohne den Account zu zerstören |
| `pairings` | Eine Gruppe gepaarter Frames |
| `pairing_members` | Zuordnung Frame ↔ Pairing, Rolle `owner`/`member` |
| `pairing_codes` | Nur Hash des Pairing-Codes, TTL, Fehlversuchszähler |
| `images` | Metadaten eines geteilten Bildes (`content_hash`, Abmessungen, `client_upload_id` für idempotente Retries) – **keine Pfade**, diese werden aus `content_hash` abgeleitet (Content-Addressed Storage) |
| `blobs` | Refcount-Buchhaltung für die tatsächlichen Bilddateien im Content-Addressed Store, siehe `docs/DECISIONS.md` ADR-006 |
| `image_hidden` | Pro-Mitglied lokales Ausblenden eines Bildes, ohne es global für alle zu löschen |
| `admin_audit` | Protokoll administrativer Aktionen (Nutzer/Frame löschen, Registrierung umschalten etc.) |
| `reports` | Meldungen von Bildern durch Nutzer (UGC-Moderation, siehe Abschnitt 6) |
| `config_pushes` | Verschlüsselte Konfigurations-Payloads für Fernkonfiguration (`ciphertext`, `applied_at`/`rejected_at`) |

## 5. Sicherheitsmodell

- **Passwörter**: bcrypt/argon2-Hashing, nie Klartext.
- **Auth**: kurzlebiges JWT + widerrufbarer Refresh-Token pro Gerät (`device_tokens.revoked_at`). `authGuard` prüft bei jeder Route zusätzlich die Pairing-Mitgliedschaft; `adminGuard` ist strikt vom User-Auth getrennt.
- **Rate-Limiting**: `express-rate-limit` auf `/auth/*` und `/pairing/create-code`; `pairing/redeem` zusätzlich pro IP und pro Konto begrenzt.
- **Bildauslieferung**: kein `express.static` auf `/data`. `GET /images/:id/file` läuft durch `authGuard` + Mitgliedschaftsprüfung; Dateinamen werden ausschließlich serverseitig generiert (kein Path Traversal möglich). Antwort-Header: `Cache-Control: public, max-age=31536000, immutable` (Bilder sind content-addressed, also unveränderlich unter ihrer ID) + `ETag` (= `content_hash`) + `X-Content-Type-Options: nosniff`. Es findet **kein Original-Byte-Passthrough** statt: jedes Bild wird serverseitig über `sharp` re-encoded (`.rotate()` zum Einbrennen der EXIF-Orientation, `limitInputPixels` gegen Decompression-Bomb-Angriffe, EXIF-GPS wird gestrippt), bevor es im Content-Addressed Store landet.
- **Key-Fingerprint + Trust-On-First-Use (Config-Push)**: Die Frame-Fernkonfiguration ist Ende-zu-Ende-verschlüsselt mit dem öffentlichen Schlüssel des Ziel-Frames (`frames.public_key`); der Relay-Server sieht nur Chiffrat. Um einen bösartigen/kompromittierten Relay-Betreiber daran zu hindern, nachträglich einen fremden Public Key unterzuschieben, zeigt jeder Frame einen kurzen, vergleichbaren Fingerprint seines Schlüssels an. Das sendende Gerät merkt sich diesen Fingerprint nach TOFU-Prinzip; ändert er sich später unerwartet, erscheint eine unübersehbare Warnung statt eines stillschweigenden Config-Push. Details/Grenzen: `docs/DECISIONS.md` ADR-005.
- **Moderation (Melde-/Block-Funktion für UGC)**: Da Uploads zwischen gepaarten Nutzern ausgetauscht werden (User-Generated Content), kann jedes Pairing-Mitglied ein Bild melden (`reports`-Tabelle: Bild-ID, meldendes Mitglied, Grund, Zeitstempel). Gemeldete Bilder werden im Admin-Panel sichtbar und können dort vom Betreiber geprüft/entfernt werden; zusätzlich kann jedes Mitglied ein Bild jederzeit lokal für sich ausblenden (`image_hidden`), unabhängig von einer Meldung. Globales Löschen bleibt dem Uploader oder der `owner`-Rolle vorbehalten.
- **Quotas/Missbrauchsschutz**: `MAX_UPLOAD_BYTES` (multer `limits.fileSize` + Content-Length-Vorprüfung), MIME-Whitelist, `storage_used_bytes` pro User (transaktional geprüft, HTTP 413 bei Überschreitung), Bildlimit pro Pairing, Upload-Rate-Limit pro Frame.
