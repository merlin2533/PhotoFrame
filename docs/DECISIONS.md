# Architektur-Entscheidungen (ADRs)

Kurzformat je Entscheidung: Kontext / Entscheidung / Konsequenzen. Siehe `docs/PLAN.md` für die ausführliche Herleitung.

---

## ADR-001: Framework-Wahl Flutter

**Kontext:** PhotoFrame soll als eine Codebasis auf iOS und Android laufen (Diashow im Kiosk-Modus, Sharing/Pairing). Native Doppelentwicklung (Swift + Kotlin) verdoppelt Aufwand und Divergenzrisiko für ein Ein-Personen-/Kleinteam-Projekt.

**Entscheidung:** Flutter als Cross-Platform-Framework, State-Management via `flutter_riverpod` (ohne Codegen in v1).

**Konsequenzen:**
- Eine Codebasis für UI, Diashow-Engine, Caching, Quellen-Abstraktion.
- Plattformspezifisches Verhalten (Kiosk/Autostart, Hintergrund-Sync, HEIC-Handling) muss weiterhin explizit pro Plattform behandelt werden – Flutter abstrahiert das nicht vollständig weg (siehe ADR-004).
- Abhängigkeit von Plugin-Reife für Nischen-Funktionalität (z.B. SMB-Zugriff) – deshalb wurde ein SMB-Machbarkeits-Spike vorgezogen (siehe `docs/PLAN.md`).

---

## ADR-002: Eigener Relay-Server statt Firebase/BaaS

**Kontext:** Für das Pairing/Sharing-Feature wird ein Backend gebraucht (Account, Pairing, Bild-Upload, Realtime-Benachrichtigung). Firebase/BaaS-Angebote wären schneller initial verfügbar, binden aber an einen Drittanbieter (Kosten bei Wachstum, Datenschutz/DSGVO-Verantwortlichkeit beim Anbieter, kein Self-Hosting für datenschutzsensible Nutzer, Vendor-Lock-in).

**Entscheidung:** Ein eigener, self-hosted Node/TypeScript-Relay-Server (`/relay_server`) als Docker-All-in-one-Image mit genau einem Port, eingebetteter SQLite-Datenbank (WAL-Modus), kleinem Admin-Panel und eigener Benutzerverwaltung.

**Konsequenzen:**
- Voller Betreiber selbst verantwortlich für Hosting, HTTPS (Reverse-Proxy), Backups, Updates – dafür volle Kontrolle über Daten und Kosten.
- Server-Betreiber wird datenschutzrechtlich Verantwortlicher (siehe `docs/PRIVACY.md`).
- Mehr Eigenentwicklungsaufwand (Auth, Realtime via Socket.IO, Content-Addressed Storage, Moderation) statt fertiger BaaS-Bausteine.
- Ermöglicht Deployment auf NAS/Raspberry Pi (Multi-Arch-Image amd64+arm64).

---

## ADR-003: Google Drive zurückgestellt

**Kontext:** Automatischer Ordner-Abgleich mit Google Drive als Bildquelle würde den restricted OAuth-Scope `drive.readonly` benötigen. Dieser erfordert eine kostenpflichtige, jährlich wiederkehrende CASA-Sicherheitsprüfung durch Google; ohne bestandene Verification bleibt eine App auf 100 Testnutzer begrenzt.

**Entscheidung:** Google Drive wird aus v1 gestrichen. Die `PhotoSource`-Abstraktion wird jedoch so entworfen, dass Google Drive später nachrüstbar ist, ohne bestehende Quellen anzufassen.

**Konsequenzen:**
- Kein CASA-Assessment/Kosten in v1 nötig.
- Zwei Optionen bleiben für eine spätere Runde dokumentiert (`docs/PLAN.md`, Abschnitt "Google Drive – zurückgestellt"): `drive.file`-Scope (kein Verification-Aufwand, aber nur einzeln per Picker gewählte Dateien) oder voller `drive.readonly`-Scope (volle Funktionalität, aber Verification/CASA-Pflicht).
- Nutzer, die Google Drive heute schon nutzen wollen, müssen auf Nextcloud/WebDAV, SMB oder `LocalFolderSource` ausweichen.

---

## ADR-004: Kiosk/Autostart-Grenzen

**Kontext:** Ein digitaler Fotorahmen soll nach Boot automatisch in die Diashow starten, ohne dass jemand die App manuell öffnet. Android verbietet seit API 29 das Starten von Activities aus dem Hintergrund – ein reiner `BOOT_COMPLETED`-Receiver startet die App **nicht** zuverlässig. Auf iOS existiert grundsätzlich kein API für Autostart durch Drittanbieter-Apps.

**Entscheidung:** Android: App registriert sich als Home-App/Launcher (`CATEGORY_HOME`-Intent-Filter), wodurch sie nach Boot automatisch als Standard-Bildschirm geladen wird, kombiniert mit Screen-Pinning (`startLockTask`) für Kiosk-Verhalten. iOS: kein Autostart – nur der manuelle, vom Nutzer aktivierte "Geführte Zugriff"-Modus (Guided Access) wird unterstützt und dokumentiert.

**Konsequenzen:**
- Android-Nutzer müssen die App explizit als Standard-Startbildschirm auswählen (Systemdialog), kein transparenter Autostart ohne Nutzerinteraktion.
- iOS-Nutzer müssen nach jedem Geräteneustart die App manuell öffnen und "Geführten Zugriff" aktivieren – dies wird in README/Nutzerdokumentation explizit als Plattformgrenze kommuniziert, um keine falsche Erwartungshaltung zu wecken.
- Kein echtes Display-Aus im Nachtmodus möglich (nur Dimmen/Overlay), da Drittanbieter-Apps das Display nicht ausschalten dürfen.

---

## ADR-005: Key-Fingerprint + Trust-On-First-Use für Config-Push

**Kontext:** Die Frame-Fernkonfiguration (z.B. SMB-Zugangsdaten von einem Handy auf einen Frame pushen) läuft Ende-zu-Ende-verschlüsselt über den Relay-Server, der nur das Chiffrat sieht (`config_pushes.ciphertext`, verschlüsselt mit dem öffentlichen Schlüssel des Ziel-Frames, `frames.public_key`). Ein böswilliger oder kompromittierter Relay-Betreiber könnte jedoch beim erstmaligen Schlüsselaustausch den öffentlichen Schlüssel eines Frames durch seinen eigenen ersetzen (Man-in-the-Middle bei der Schlüssel-Distribution) und so Konfigurations-Payloads mitlesen, die eigentlich Ende-zu-Ende verschlüsselt sein sollen.

**Entscheidung:** Jeder Frame zeigt seinen öffentlichen Schlüssel als kurzen, für Menschen vergleichbaren Fingerprint (z.B. Base32/Hex-Kurzform eines Hashes des Public Keys) im UI an. Beim Pairing bzw. vor dem ersten Config-Push wird dieser Fingerprint nach dem Trust-On-First-Use-Prinzip (TOFU) lokal auf dem sendenden Gerät gespeichert; ändert sich der vom Relay ausgelieferte Fingerprint für einen bereits bekannten Frame später unerwartet (z.B. weil ein Angreifer den Schlüssel im Nachhinein austauscht), wird eine unübersehbare Warnung angezeigt statt den Config-Push stillschweigend zuzulassen.

**Konsequenzen:**
- Schützt gegen nachträgliche Schlüssel-Substitution durch einen bösartigen/kompromittierten Relay-Betreiber, nicht aber gegen eine Manipulation exakt beim allerersten Pairing (klassische TOFU-Grenze – wie bei SSH).
- Erfordert UI für Fingerprint-Anzeige/-Vergleich und lokale Speicherung bekannter Fingerprints pro gepaartem Frame (`flutter_secure_storage`).
- Der Nutzer muss die Warnung bei einer echten, legitimen Geräte-Neuregistrierung (z.B. Reinstall des Ziel-Frames) bewusst bestätigen können – dies wird als expliziter "erneut vertrauen"-Dialog umgesetzt, nicht automatisch.

---

## ADR-006: Blob-GC-Design (separate `blobs`-Tabelle mit Refcount statt Inline-Unlink)

**Kontext:** Bilder werden Content-Addressed gespeichert (`/data/blobs/ab/cd/<hash>`), damit identische Uploads (z.B. dasselbe Bild von zwei Frames in einem Pairing) nicht mehrfach auf der Platte liegen. Würde `DELETE /images/:id` die zugehörige Blob-Datei direkt inline per `unlink()` löschen, entsteht eine Race Condition: Lädt Frame A ein Bild hoch (Hash X) während gleichzeitig Frame B ein zuvor hochgeladenes Bild mit demselben Hash X löscht, kann der Löschvorgang die Datei entfernen, obwohl gerade eine neue Referenz auf denselben Hash entsteht bzw. bereits besteht – Ergebnis: eine `images`-Zeile verweist auf eine nicht mehr existierende Datei.

**Entscheidung:** Eine explizite `blobs`-Tabelle (`hash PRIMARY KEY, ref_count, size, created_at`) führt Buch über Referenzen. `DELETE` einer `images`-Zeile dekrementiert nur den Refcount transaktional (kein sofortiges `unlink()`). Das tatsächliche Entfernen verwaister Blob-Dateien (`ref_count <= 0`) übernimmt ein separater, periodischer GC-Job, der außerhalb der Lösch-Transaktion läuft.

**Konsequenzen:**
- Kein Race zwischen parallelem Upload und Delete desselben Hashes: Der Refcount wird immer transaktional zusammen mit dem Einfügen/Löschen der referenzierenden `images`-Zeile aktualisiert; das physische Löschen passiert erst später und nur, wenn der Refcount zum GC-Zeitpunkt tatsächlich bei 0 steht.
- Kleiner Nachteil: Speicherplatz von gelöschten, unreferenzierten Blobs wird nicht sofort freigegeben, sondern erst beim nächsten GC-Lauf (akzeptabel, da Storage-Nutzung ohnehin über Quotas begrenzt ist).
- GC-Job muss idempotent und gegen weitere Race-Fenster (Refcount steigt zwischen GC-Scan und tatsächlichem `unlink()` wieder auf >0) robust sein, z.B. durch erneute Prüfung des Refcounts unmittelbar vor dem `unlink()` innerhalb derselben GC-Transaktion.

---

## ADR-007: Blob-Refcount/Storage-Accounting bei Cascade-Delete und `commitBlob()`-Transaktionsgrenze

**Kontext:** Das Code-Review-Backlog (siehe `docs/PLAN.md`) hatte zwei zusammenhängende Lecks identifiziert: (1) `ON DELETE CASCADE` bei `DELETE /pairings/:id` und dem Admin-User-Löschen entfernt `images`-Zeilen, ohne `blobs.refcount` zu dekrementieren – Referenzen bleiben für immer "hängen", der GC-Job löscht die Datei nie, weil er auf `refcount <= 0` wartet. (2) `commitBlob()` (das den Blob-Refcount transaktional mit dem `images`-Insert führen soll, siehe ADR-006) wurde in der ursprünglichen Implementierung **außerhalb** der Insert-Transaktion aufgerufen – ein Fehler zwischen beiden Schritten konnte einen erhöhten Refcount ohne zugehörige `images`-Zeile hinterlassen (derselbe permanente Leak, nur beim Anlegen statt beim Löschen).

**Entscheidung:**
1. Für JEDEN Lösch-Pfad, der `images`-Zeilen per Cascade oder direkt entfernt (`DELETE /pairings/:id`, Admin-User-Löschen, Admin-Bild-Löschen, `DELETE /images/:id`, `DELETE /account`), wird VOR dem eigentlichen Löschen/der Cascade die betroffenen `images.content_hash`/`uploaded_by_frame_id` selektiert und über eine neue, einzige Hilfsfunktion `releaseImageAccounting()` (`src/storage/imageCleanup.ts`) sowohl `releaseBlobRef()` als auch die `storage_used_bytes`-Freigabe aufgerufen – beides innerhalb derselben Transaktion wie das eigentliche Löschen, damit ein Absturz dazwischen die Zähler nicht von den tatsächlich gelöschten Zeilen abkoppelt.
2. Statt `commitBlob()` in einen Kompensations-Mechanismus (try/catch mit explizitem `releaseBlobRef()` im Fehlerfall) zu verpacken, wird `commitBlob()` direkt **in denselben `runInTransaction`-Block wie das `images`-Insert** verschoben (`routes/images.ts`). Das ist der von `contentAddressedStore.ts`s eigenem Docstring geforderte, sauberere Weg: node:sqlite's `DatabaseSync` unterstützt keine verschachtelten Transaktionen, aber da beide Aufrufe dieselbe Connection nutzen, reicht es, sie als aufeinanderfolgende Statements innerhalb eines `BEGIN`/`COMMIT` auszuführen – kein zusätzlicher Kompensationscode nötig, und ein `ROLLBACK` bei einem fehlgeschlagenen Insert nimmt automatisch auch die `blobs`-Zeile/den Refcount zurück. Bewusst akzeptierter Rest-Kompromiss: Der physische `rename()`/`writeFileSync()` auf die Blob-/Thumbnail-Datei liegt außerhalb der SQL-Transaktion (Dateisystem kennt kein Rollback) – im seltenen Fall eines Absturzes zwischen Rename und einem rollenden `ROLLBACK` kann eine einzelne verwaiste Datei ohne zugehörige `blobs`-Zeile zurückbleiben. Das ist ein begrenzter, einmaliger Streuverlust (kein driftender Zähler) und damit klar besser als das ursprüngliche Problem.

**Storage-Accounting-Semantik (bewusste Vereinfachung):** `storage_used_bytes` wird beim Upload für JEDE akzeptierte `images`-Zeile um die (re-encodierte) Bildgröße erhöht – auch dann, wenn der zugrunde liegende Blob bereits durch einen anderen Uploader dedupliziert existiert (`commitBlob()` erhöht in diesem Fall nur den Refcount, ohne neue Bytes auf die Platte zu schreiben). Korrespondierend wird beim Löschen einer `images`-Zeile IMMER die volle beim Upload gebuchte Bytezahl wieder freigegeben – unabhängig vom aktuellen `blobs.refcount`-Zustand. Diese Entscheidung weicht bewusst von einer zunächst erwogenen Variante ab ("nur freigeben, wenn dies wirklich die letzte Referenz war"), weil letztere voraussetzen würde, dass auch das Hochladen dedupliziert bereits vorhandener Inhalte nicht gebucht wird – eine invasivere Änderung mit eigenem Abstimmungsbedarf (wer "besitzt" die Quota eines geteilten Bytes?). Die hier gewählte, symmetrische Variante (jede Buchung hat genau eine Freigabe) ist garantiert driftfrei in beide Richtungen; der Preis dafür ist, dass `SUM(storage_used_bytes)` über alle Nutzer hinweg den tatsächlichen Plattenverbrauch übersteigen kann, wenn Inhalte zwischen Nutzern dedupliziert werden. Der tatsächliche Plattenverbrauch bleibt davon unberührt korrekt, weil er ausschließlich über `blobs.bytes`/`refcount` (ADR-006) geführt wird, nicht über `storage_used_bytes`.

Zusätzlich wurde die vorbestehende Inkonsistenz behoben, dass die Quota-Prüfung beim Upload `req.file.size` (Rohgröße vor Re-Encoding) nutzte, während die Buchung `processed.originalBuffer.length` (Größe nach Re-Encoding) verwendete – beide Schritte nutzen jetzt einheitlich `processed.originalBuffer.length`.

**Konsequenzen:**
- Kein weiteres Wachstum verwaister Refcounts bei Pairing-/User-Löschung; der GC-Job kann Blobs nach einer Cascade-Löschung tatsächlich einsammeln.
- `storage_used_bytes` kann jetzt sinken (vorher ein Einweg-Zähler, der Nutzer nach Erreichen der Quota dauerhaft blockiert hätte).
- `SUM(storage_used_bytes)` ist kein exaktes Abbild des Plattenverbrauchs bei Cross-User-Dedup – dokumentiert als akzeptierter Trade-off, nicht als Bug.

---

## ADR-008: Live-Updates über bestehende Socket.IO-Singleton statt neuem Emitter-Modul

**Kontext:** Der `pairing:<id>`-Socket.IO-Raum existierte bereits (Beitritt nach Mitgliedschaftsprüfung, siehe `docs/ARCHITECTURE.md` Abschnitt 3), aber niemand sendete tatsächlich `album:updated`/`album:imageDeleted` hinein – der Raum war bis zu dieser Runde funktionslos.

**Entscheidung:** `routes/images.ts` sendet nach erfolgreichem Upload `album:updated` (an `pairing:<id>`, mit `.except('frame:<uploaderFrameId>')`, da jeder Socket beim Connect automatisch seinem `frame:<id>`-Raum beitritt – das bildet "an alle Mitglieder außer dem Uploader" ab, wie in `docs/PLAN.md` Ablaufpunkt 4 gefordert) und nach erfolgreichem Löschen `album:imageDeleted` (an alle Mitglieder, ohne Ausnahme). Für den Zugriff auf die Socket.IO-`io`-Instanz wird bewusst **kein neues Singleton-Modul** eingeführt, sondern die bereits vorhandene `getIo()`-Exportfunktion aus `realtime/socket.ts` wiederverwendet (dieselbe Funktion, die `configPush.ts` bereits für `config_push`-Events nutzt) – sie ist schon ein Singleton-Getter mit derselben Eigenschaft (liefert `null` vor `initSocket()`, z.B. in Tests, die nur `createApp()` ohne HTTP-Server/Socket.IO instanziieren), ein zusätzliches `realtime/emitter.ts` hätte nur denselben Zustand doppelt gehalten.

**Konsequenzen:**
- Kein zusätzliches Modul/keine zusätzliche Indirektion; Konsistenz mit dem bereits etablierten `configPush.ts`-Muster.
- `getIo()?.to(...)` ist überall `null`-sicher, wodurch Routen-Tests, die `createApp()` ohne laufenden Socket.IO-Server instanziieren (siehe `relay_server/test/http/*.test.ts`), nicht fehlschlagen.
- Der Cascade-Delete-Pfad (`DELETE /pairings/:id`, Admin-Löschung) sendet aktuell **kein** `album:imageDeleted` pro betroffenem Bild – das wäre ein separates, potenziell großes Event-Fanout (ein komplettes Pairing kann hunderte Bilder enthalten) und ist bewusst nicht Teil dieser Runde; ein Client, der ein gelöschtes Pairing weiter anzeigt, bemerkt das spätestens beim nächsten `GET /pairing/:id/images`-Poll bzw. beim Room-Verlassen.
- Die in `realtime/socket.ts` dokumentierte Grenze (Mitgliedschaft wird nur beim `join_pairing` geprüft, nicht bei jedem nachfolgenden Event) besteht unverändert fort – siehe Code-Kommentar dort; nicht in dieser Runde behoben, um nicht mit der parallel laufenden Member-Block-Implementierung zu kollidieren.

---

## ADR-009: i18n-Scaffold via ARB/`flutter gen-l10n`, nur ein Teil der Screens migriert

**Kontext:** Die App enthält bislang ausschließlich hartkodierte deutsche UI-Strings direkt in den Widget-Bäumen (`lib/features/**/presentation/*.dart`). Damit die App künftig mehrsprachig werden kann (und damit deutsche Strings überhaupt an einer zentralen Stelle statt über Dutzende Dateien verstreut gepflegt werden), braucht es ein Lokalisierungs-Grundgerüst. Eine vollständige Migration aller Screens in einem Rutsch wäre riskant (großer Diff, hohe Kollisionswahrscheinlichkeit mit parallel laufenden Feature-Branches auf denselben Dateien) und war nicht Ziel dieser Runde.

**Entscheidung:**
- Flutters Standard-Ansatz wird verwendet: ARB-Dateien (`mobile_app/lib/l10n/app_de.arb` als Template/Default-Locale, `app_en.arb` als zweite Sprache) plus `flutter_localizations`/`intl` und codegenerierte `AppLocalizations` (`flutter gen-l10n`, gesteuert über `mobile_app/l10n.yaml`, `generate: true` in `pubspec.yaml`). Deutsch bleibt die Standard-/Primärsprache der App (`locale: const Locale('de')` in `app.dart`), Englisch ist als zweite ARB-Sprache angelegt, aber noch nicht über einen Sprachumschalter in den Einstellungen erreichbar (App-Locale ist aktuell hart auf `de` gesetzt, nicht an `Platform.localeName`/eine Nutzereinstellung gekoppelt – das ist ein bewusst ausgeklammerter Folgeschritt).
- **Nur eine Handvoll zentraler Screens wurde als Beispiel/Muster vollständig migriert:** `settings_screen.dart`, `onboarding_screen.dart` (inkl. des neuen OEM-Autostart-Hinweisschritts, siehe unten) und `cache_settings_screen.dart`. `slideshow_settings_screen.dart` wurde bewusst NICHT migriert, obwohl ursprünglich als drittes Beispiel vorgesehen, weil zeitgleich ein anderer Agent an genau dieser Datei arbeitete (Kollisionsvermeidung in einem gemeinsamen, nicht Worktree-isolierten Arbeitsverzeichnis) – `cache_settings_screen.dart` wurde stattdessen als drittes Beispiel gewählt.
- **Alle übrigen `lib/features/**/presentation/*.dart`-Screens enthalten weiterhin hartkodierte deutsche Strings und sind NICHT migriert.** Explizite Liste (Stand dieser Runde), damit das nicht als "erledigt" missverstanden wird:
  - `lib/features/settings/presentation/always_on_settings_screen.dart`
  - `lib/features/settings/presentation/night_mode_settings_screen.dart`
  - `lib/features/settings/presentation/slideshow_settings_screen.dart`
  - `lib/features/settings/presentation/accessibility_settings_screen.dart`
  - `lib/features/settings/presentation/pool_settings_screen.dart`
  - `lib/features/settings/presentation/sharing_settings_screen.dart`
  - `lib/features/settings/presentation/weather_settings_screen.dart` (falls/sobald vorhanden)
  - `lib/features/pairing/presentation/*.dart` (alle Screens: `pairing_screen.dart`, `pairing_qr_display_screen.dart`, `pairing_scan_screen.dart`, `config_push_confirmation_screen.dart`, `recovery_code_screen.dart`, `relay_server_setup_screen.dart`, `shared_album_view_screen.dart`, `upload_screen.dart`)
  - `lib/features/sources/presentation/add_source_screen.dart`
  - `lib/features/sources/presentation/source_list_screen.dart`
  - `lib/features/slideshow/presentation/slideshow_screen.dart` und `lib/features/slideshow/presentation/widgets/*.dart` (Overlays, Touch-Controls)
  - `lib/features/settings/presentation/autostart_help_screen.dart` — **Ausnahme:** dieser neue Screen (Task "OEM-Autostart-Hinweis") wurde direkt mit `AppLocalizations` statt mit hartkodierten Strings angelegt, ist also bereits migriert.

**Konsequenzen:**
- Neue zentrale Strings (Settings-Hub, Onboarding, Cache-Verwaltung, OEM-Autostart-Hinweis) sind jetzt in `app_de.arb`/`app_en.arb` gepflegt statt im Code verstreut; jede neue ARB-Message trägt eine `@key`-Beschreibung für Übersetzer.
- Der Großteil der App bleibt bis auf Weiteres hartkodiert deutsch – funktional unverändert (keine Regressionen), aber die oben gelistete Restmenge muss in einer Folgerunde schrittweise nachgezogen werden, bevor die App wirklich mehrsprachig ist.
- `flutter gen-l10n` erzeugt `lib/l10n/app_localizations*.dart` nicht-synthetisch (kein `flutter_gen`-Paket, kein `.dart_tool`-Pfad) – diese generierten Dateien liegen im normalen `lib/`-Baum und werden wie regulärer Code behandelt/committet, analog zu vielen aktuellen Flutter-Projekten, die `synthetic-package: true` (die alte Default-Vorgehensweise) bewusst nicht mehr nutzen.

---

## ADR-010: `getFreeDiskSpaceBytes` – MethodChannel + `StatFs` statt Drittanbieter-Paket

**Kontext:** `ImageCacheManager` (`lib/services/cache/image_cache_manager.dart`) hatte bereits einen injizierbaren `Future<int> Function() getFreeDiskSpaceBytes`-Callback für Tests, aber keine echte Plattform-Implementierung als Default – der Cache wurde nie tatsächlich gegen den realen freien Gerätespeicher gedeckelt, nur gegen das konfigurierte Limit.

**Entscheidung:** Statt eines Drittanbieter-Pakets (`disk_space_plus`, `system_info_plus` o. ä. – beide ungeprüft/nicht in dieser Umgebung gegen ein echtes Gerät verifizierbar, siehe bereits bestehendes Muster bei `smb_connect` in `pubspec.yaml`) wird ein schlanker, selbst kontrollierter MethodChannel `photoframe/diskspace` (Methode `getFreeBytes`, Argument `path`) verwendet:
- Dart-Seite (`defaultGetFreeDiskSpaceBytes()` in `image_cache_manager.dart`): ermittelt das Cache-Verzeichnis über `path_provider`s `getTemporaryDirectory()` und ruft den Channel mit diesem Pfad auf.
- Android-Seite (`MainActivity.kt`): registriert den Channel in `configureFlutterEngine` und beantwortet `getFreeBytes` mit `android.os.StatFs(path).availableBlocksLong * blockSizeLong`.
- iOS/Desktop/Tests: kein passender Plattform-Handler registriert → `MissingPluginException` wird abgefangen; ebenso jede sonstige Exception (fehlgeschlagenes `StatFs`, `path_provider`-Fehler). In allen Fehlerfällen (und auf Nicht-Android-Plattformen) wird ein großzügiger Default von 10 GB (`kFallbackFreeDiskSpaceBytes`) zurückgegeben, damit eine fehlgeschlagene Speicherplatzabfrage den Cache nie künstlich aushungert.
- Dieser echte Default wird als Standardwert des `getFreeDiskSpaceBytes`-Konstruktorparameters verdrahtet (`getFreeDiskSpaceBytes ?? defaultGetFreeDiskSpaceBytes`); Tests können weiterhin ihren eigenen Fake-Callback injizieren, wie bisher.

**Konsequenzen:**
- Keine zusätzliche, ungeprüfte Paketabhängigkeit für eine einzelne Zahl; `StatFs` ist Teil des Android-SDK, kein zusätzlicher Wartungsaufwand durch ein möglicherweise unmaintaintes drittes Paket.
- iOS bekommt (noch) keine echte Speicherplatz-Deckelung – der Cache verlässt sich dort ausschließlich auf die konfigurierten Tier-Limits. Das ist ein bewusst akzeptierter Rest-Scope für diese Runde; eine iOS-Implementierung (z. B. via `NSFileManager`s `volumeAvailableCapacityForImportantUsageKey` über denselben Channel) ist ein sauberer Folgeschritt mit demselben Channel-Namen/derselben Methode, ohne Dart-seitige Änderungen.
- Unit-Tests (`flutter test`, kein echter Android-Host) laufen ebenfalls über den Fallback-Pfad (`MissingPluginException`), was für die bestehenden Cache-Tests unschädlich ist, da 10 GB abzüglich der 1-GB-Reserve weit über allen in Tests konfigurierten Cache-Limits liegt – das Verhalten der bestehenden Tests ändert sich dadurch nicht.
