# PhotoFrame – Arbeitsliste

Lokale Liste der offenen Punkte (ersetzt das Kanban-Board).

## Offen
- [x] 1 – Ruhigere Uhr/Datum-Anzeige (größer, dezenter)
- [ ] 2 – Ortsname aus EXIF-GPS in der Bildinfo (offen: Ortsnamen brauchen einen Online-Dienst, Koordinaten würden dorthin gesendet – Entscheidung nötig)
- [x] 3 – Schriftgröße und hoher Kontrast als Einstellung
- [x] 4 – Fehlerzustände mit Aktionsbutton (Erneut versuchen / Quelle prüfen)
- [x] 5 – Status in der Quellenliste (Bilder und Stand stehen im Untertitel, Verbindung als Farbe des Symbols; kein eigenes Badge)
- [x] 6 – Suche in den Einstellungen (Dunkel-Design folgt dem System; nicht einzeln geprüft)
- [x] 7 – Nächstes Bild im Hintergrund vorladen (Netzwerkquellen)
- [ ] 8 – Miniaturen-Cache für die Übersicht (zurückgestellt: Netzwerkfotos würden beim Scrollen jedes Mal neu geladen; braucht eigenen Thumbnail-Speicher)
- [ ] 9 – Index in SQLite statt JSON (zurückgestellt: JSON bleibt bei ~20.000 Fotos im Bereich von Millisekunden)
- [x] 12 – Ken-Burns-Varianten (Schwenk, sanftes Heranzoomen, ohne Bewegung)
- [x] 13 – Kombinierte Übergänge (Ken Burns liegt schon unter jedem Übergang) (Weichzeichnen mit Ken Burns)
- [ ] Tablet-Layout – Screenshot vom Nutzer abwarten

## In Arbeit
- [ ] Tagesauswahl: 2 Bilder pro Ordner im Wechsel (Round-Robin), Zahl 100–5000

## Erledigt
- [x] Verkleinerte Fotos auf dem Gerät (Batches à 100, fortlaufend), Diashow und Übersicht nutzen sie
- [x] Startseite mit Hintergrundfoto und Status; Haus-Symbol in der Diashow
- [x] Diashow-Intervall Standard 20 s
- [x] Index direkt pro Quelle starten, mit Status (läuft / Anzahl / Fehler) in der Quellenliste
- [x] Dauer-Modus Standard "immer an", Vollbild im Diashow-Modus, SMB-Download-Race behoben
- [x] Index, Tagesauswahl, Cache, Hintergrund-Refresh, Wischen, Übergänge, 2×2-Raster
- [x] Quellen bearbeiten, Ordnerauswahl SMB/Nextcloud, mehrere SMB-Freigaben
- [x] SMB-Ordner-Browser lädt nur eine Ebene
