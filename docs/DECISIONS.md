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
