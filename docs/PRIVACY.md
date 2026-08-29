# Datenschutzerklärung (Vorlage für Server-Betreiber)

**Diese Datei ist eine Vorlage.** Wer eine eigene Instanz des PhotoFrame-Relay-Servers betreibt, ist datenschutzrechtlich Verantwortlicher (Art. 4 Nr. 7 DSGVO) für die auf dieser Instanz verarbeiteten Daten und muss diese Vorlage vor Inbetriebnahme vervollständigen, insbesondere alle mit `[Platzhalter]` markierten Angaben ersetzen und den Text ggf. juristisch prüfen lassen. Diese Vorlage ersetzt keine Rechtsberatung.

---

## 1. Verantwortlicher

```
[Platzhalter: Name/Firma des Betreibers]
[Platzhalter: Anschrift]
[Platzhalter: Kontakt-E-Mail]
[Platzhalter: ggf. Telefonnummer]
```

Betreiber dieser PhotoFrame-Relay-Server-Instanz unter der Basis-URL `[Platzhalter: PUBLIC_URL]` ist die oben genannte Person/Organisation.

## 2. Welche Daten verarbeitet werden

Die Relay-Server-Instanz verarbeitet folgende personenbezogene bzw. personenbeziehbare Daten:

- **Kontodaten**: Benutzername und Passwort-Hash (niemals das Passwort im Klartext – gehasht mit bcrypt/argon2). Registrierung erfolgt automatisch durch die App; ein Klarname ist nicht erforderlich, ein Benutzername kann dennoch personenbeziehbar sein, falls der Nutzer ihn entsprechend wählt.
- **Frame-/Gerätemetadaten**: pro Frame ein Anzeigename, ein öffentlicher Schlüssel (für Ende-zu-Ende-verschlüsselte Fernkonfiguration), Zeitstempel des letzten Kontakts (`last_seen_at`), Geräte-Token zur Authentifizierung.
- **Pairing-Daten**: Zuordnung, welche Frames miteinander gepaart sind (Gruppenmitgliedschaft), nicht jedoch Standortdaten der Geräte selbst.
- **Hochgeladene Bilder**: Von Nutzern über die Sharing-Funktion hochgeladene Fotos, inklusive Bildabmessungen und Upload-Zeitpunkt. **EXIF-GPS-Daten werden serverseitig beim Verarbeiten des Uploads aktiv entfernt (gestrippt)**, bevor das Bild gespeichert wird – die auf dem Server abgelegte Bilddatei enthält keine Standortmetadaten mehr. Andere EXIF-Felder (z.B. Aufnahmedatum) können je nach Implementierungsstand erhalten bleiben; falls dies für den Betrieb relevant ist, sollte dies hier ergänzt und im Quellcode (`relay_server`) verifiziert werden.
- **Meldungen (Moderation)**: Wenn ein Nutzer ein von einem anderen gepaarten Mitglied hochgeladenes Bild meldet, wird gespeichert, welches Bild gemeldet wurde, von wem (meldendes Konto) und ggf. ein Grund/Zeitstempel, damit der Betreiber die Meldung im Admin-Panel prüfen kann.
- **Admin-Protokoll**: Administrative Aktionen (Nutzer/Frame löschen, Registrierung umschalten) werden protokolliert, um Missbrauch durch Admin-Zugriff nachvollziehbar zu machen.
- **Technische Protokolldaten**: Übliche Server-/Zugriffsprotokolle (IP-Adressen, Zeitstempel), soweit vom Betreiber bzw. einem vorgeschalteten Reverse-Proxy geführt – Umfang und Aufbewahrung hängen von der konkreten Deployment-Konfiguration ab und sind vom Betreiber zu ergänzen.

## 3. Zweck der Verarbeitung

Die Verarbeitung dient ausschließlich der Bereitstellung der Kernfunktion: Kontoerstellung, Pairing zwischen Geräten, Austausch/Anzeige gemeinsam geteilter Fotos sowie der Betriebssicherheit (Missbrauchsschutz, Moderation gemeldeter Inhalte).

## 4. Aufbewahrung und Löschung (DSGVO Art. 17, Art. 20)

- **Aufbewahrung**: Kontodaten, Frame-/Pairing-Daten und hochgeladene Bilder werden gespeichert, solange das Konto bzw. das Pairing aktiv besteht. Automatische Datenbank-Backups werden gemäß `BACKUP_RETENTION_DAYS` (siehe `docs/SECRETS.md`) rotiert.
- **Recht auf Löschung (Art. 17 DSGVO)**: Über `DELETE /me` kann ein Nutzer sein Konto vollständig löschen; dies kaskadiert auf alle zugehörigen Frames, Pairing-Mitgliedschaften und – soweit keine anderen Mitglieder mehr referenzieren – die zugehörigen Bilder (Content-Addressed Storage: ein Bild wird erst physisch entfernt, wenn keine Referenz mehr darauf besteht, siehe `docs/DECISIONS.md` ADR-006). Einzelne Bilder können jederzeit über die Lösch-Funktion der App entfernt werden (durch den Uploader oder ein Mitglied mit `owner`-Rolle im jeweiligen Pairing).
- **Recht auf Datenübertragbarkeit (Art. 20 DSGVO)**: Über `GET /me/export` kann ein Nutzer seine gespeicherten Daten in strukturierter Form exportieren.
- Der konkrete Betreiber sollte hier eine tatsächliche Löschfrist für inaktive Konten ergänzen, falls eine solche Policy eingeführt wird (z.B. "Konten ohne Aktivität seit X Monaten werden nach vorheriger Ankündigung gelöscht") – dies ist aktuell **kein** automatisierter Mechanismus des Relay-Servers.

## 5. Weitergabe an Dritte

Es findet keine Weitergabe von Nutzerdaten an Dritte statt, sofern der Betreiber nicht selbst zusätzliche Dienste einbindet (z.B. externe Backup-Speicherorte, E-Mail-Versand). Werden solche Dienste ergänzt, muss dieser Abschnitt entsprechend erweitert werden (ggf. inkl. Auftragsverarbeitungsvertrag).

## 6. Melde-Funktion für nutzergenerierte Inhalte (UGC)

Da Bilder zwischen gepaarten Nutzern ausgetauscht werden, kann es zu unerwünschten oder missbräuchlichen Inhalten kommen. Jedes Mitglied eines Pairings kann ein Bild über die App melden. Gemeldete Bilder werden dem Betreiber im Admin-Panel zur Prüfung angezeigt; der Betreiber kann gemeldete Inhalte entfernen. Nutzer können ein Bild zusätzlich jederzeit unabhängig von einer Meldung lokal für sich ausblenden, ohne dass dies andere Mitglieder betrifft oder eine Meldung erzeugt.

## 7. Kontakt für Betroffenenanfragen

```
[Platzhalter: Kontakt-E-Mail oder -Adresse für Auskunfts-, Lösch- und Berichtigungsanfragen nach Art. 15 ff. DSGVO]
```

## 8. Änderungen dieser Erklärung

Der Betreiber sollte diese Erklärung aktuell halten, insbesondere wenn sich Funktionsumfang, Speicherorte oder eingebundene Dritt-Dienste ändern.
