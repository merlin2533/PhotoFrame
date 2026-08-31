// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'PhotoFrame';

  @override
  String commonError(String message) {
    return 'Fehler: $message';
  }

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonBack => 'Zurück';

  @override
  String get commonNext => 'Weiter';

  @override
  String get settingsScreenTitle => 'Einstellungen';

  @override
  String get settingsGroupSlideshow => 'Diashow';

  @override
  String get settingsGroupContent => 'Inhalte';

  @override
  String get settingsGroupSharing => 'Teilen';

  @override
  String get settingsGroupGeneral => 'Allgemein';

  @override
  String get settingsSlideshowTitle => 'Diashow';

  @override
  String get settingsSlideshowSubtitle =>
      'Intervall, Overlays, Anzeige-Modus, Übergänge';

  @override
  String get settingsAlwaysOnTitle => 'Dauer-Modus';

  @override
  String get settingsAlwaysOnSubtitle => 'Bildschirm dauerhaft an lassen';

  @override
  String get settingsNightModeTitle => 'Nachtmodus';

  @override
  String get settingsNightModeSubtitle => 'Zeitplan, Dimm-Stärke';

  @override
  String get settingsWeatherTitle => 'Wetter';

  @override
  String get settingsWeatherSubtitle => 'Overlay an/aus, Ort';

  @override
  String get settingsSourcesTitle => 'Quellen';

  @override
  String get settingsSourcesSubtitle =>
      'Ordner, Freigaben, Nextcloud verwalten';

  @override
  String get settingsCacheTitle => 'Cache-Verwaltung';

  @override
  String get settingsCacheSubtitle => 'Belegter Speicher, Limit, Cache leeren';

  @override
  String get settingsPoolTitle => 'Pool/Index';

  @override
  String get settingsPoolSubtitle =>
      'Arbeitsmenge, Auffüll-Intervall, neue Bilder';

  @override
  String get settingsSharingTitle => 'Sharing/Relay';

  @override
  String get settingsSharingSubtitle => 'Relay-Server-URL, Pairing';

  @override
  String get settingsAccessibilityTitle => 'Barrierefreiheit';

  @override
  String get settingsAutostartHelpTitle =>
      'Autostart auf diesem Handy-Hersteller';

  @override
  String get settingsAutostartHelpSubtitle =>
      'Xiaomi, Huawei, Samsung, OnePlus & Co.';

  @override
  String get settingsKioskTitle => 'Fotorahmen-Startbildschirm';

  @override
  String get settingsKioskSubtitle =>
      'Als Home-Bildschirm einrichten, Bildschirm fixieren';

  @override
  String get kioskScreenTitle => 'Fotorahmen-Startbildschirm';

  @override
  String get kioskToggleTitle => 'Als Fotorahmen-Startbildschirm verwenden';

  @override
  String get kioskToggleSubtitle =>
      'Registriert die App als Home-Bildschirm und fixiert den Bildschirm während der Diashow';

  @override
  String get kioskIntro =>
      'Verwandelt dieses Gerät in einen dedizierten digitalen Fotorahmen: PhotoFrame wird als Startbildschirm (Home-App) auswählbar, und der Bildschirm wird beim Betreten der Diashow fixiert (Screen-Pinning), damit niemand versehentlich zu anderen Apps wechselt.';

  @override
  String get kioskExitNowButton => 'Bildschirmfixierung jetzt sofort beenden';

  @override
  String get kioskHomeAppNote =>
      'Nach dem Aktivieren erscheint beim nächsten Drücken der Home-Taste ein Systemdialog, mit dem du PhotoFrame als Standard-Startbildschirm festlegen kannst. Das musst du selbst bestätigen - Android erlaubt es Apps nicht, diesen Dialog automatisch zu bestätigen oder zu umgehen.';

  @override
  String get kioskPinningNote =>
      'Sobald die Diashow startet, wird der Bildschirm fixiert (Screen-Pinning). Da diese App keine Geräteverwaltungs-/MDM-Rechte hat, zeigt Android dabei am oberen Bildschirmrand ggf. einen kleinen \"Entsperren\"/\"Verlassen\"-Hinweis an - das ist Plattformverhalten und kann von dieser App nicht vollständig unterdrückt werden.';

  @override
  String get kioskAndroidOnlyNote =>
      'Nur auf Android verfügbar. Auf iOS gibt es keinen vergleichbaren Autostart-Mechanismus für Drittanbieter-Apps - dort hilft nur der systemeigene \"Geführte Zugriff\" (siehe Onboarding).';

  @override
  String get settingsReplayOnboardingTitle => 'Setup-Guide erneut anzeigen';

  @override
  String get cacheScreenTitle => 'Cache-Verwaltung';

  @override
  String get cacheUsedStorageLabel => 'Belegter Speicher';

  @override
  String cacheUsedOfLimit(String used, String limit) {
    return '$used von $limit belegt';
  }

  @override
  String cacheLimitLabel(String limit) {
    return 'Cache-Limit: $limit';
  }

  @override
  String get cacheLimitDeviceCapHint =>
      'Das Limit wird zusätzlich gegen den tatsächlich freien Gerätespeicher gedeckelt (mind. 1 GB/10% Reserve).';

  @override
  String get cacheClearButton => 'Cache leeren';

  @override
  String get cacheClearedSnackbar => 'Cache geleert';

  @override
  String get onboardingSkip => 'Überspringen';

  @override
  String get onboardingAddSourceCta => 'Quelle hinzufügen';

  @override
  String get onboardingWelcomeTitle => 'Willkommen bei PhotoFrame';

  @override
  String get onboardingWelcomeBody =>
      'PhotoFrame verwandelt dieses Gerät in einen digitalen Fotorahmen: Es zeigt Bilder aus deinen Ordnern (z. B. Netzwerkfreigabe, Nextcloud oder lokaler Speicher) als Endlos-Diashow und kann Fotos mit anderen Frames teilen. Dieser kurze Guide richtet das Gerät in wenigen Schritten dafür ein.';

  @override
  String get onboardingAlwaysOnTitle => 'Dauer-Modus: Bildschirm bleibt an';

  @override
  String get onboardingAlwaysOnBody =>
      'Ein Fotorahmen soll dauerhaft leuchten - deshalb kann PhotoFrame verhindern, dass der Bildschirm ausgeht oder das Gerät sich sperrt. Das ist das Kernfeature dieser App, kostet aber spürbar Akku.';

  @override
  String get onboardingAlwaysOnRecommendation =>
      'Empfehlung: Dauer-Modus nur bei dauerhaft angeschlossenem Ladekabel verwenden (z. B. wandmontiert). Du kannst später in den Einstellungen zwischen \"immer an\", \"nur während der Diashow\" und einem Zeitplan (kombiniert mit dem Nachtmodus) wählen.';

  @override
  String get onboardingAndroidHomeAppTitle => 'Als Startbildschirm einrichten';

  @override
  String get onboardingAndroidHomeAppSkippedBody =>
      'Dieser Schritt betrifft nur Android-Geräte und wird auf diesem Gerät übersprungen.';

  @override
  String get onboardingAndroidHomeAppBody =>
      'Damit PhotoFrame nach jedem Neustart automatisch erscheint, kannst du die App als Standard-Startbildschirm (Home-App/Launcher) festlegen: Android-Einstellungen -> Apps -> Standard-Apps -> Startbildschirm-App -> PhotoFrame auswählen.';

  @override
  String get onboardingOpenAndroidSettings => 'Android-Einstellungen öffnen';

  @override
  String get onboardingBatteryOptTitle => 'Von Akku-Optimierung ausnehmen';

  @override
  String get onboardingBatteryOptBody =>
      'Android beendet App-Aktivität im Hintergrund gerne, um Akku zu sparen - das kann die Diashow ausbremsen oder Bilder verzögert aktualisieren. Nimm PhotoFrame in den Einstellungen unter \"Akku -> Nicht optimieren\"/\"Akkuoptimierung ignorieren\" aus der Optimierung aus, damit sie dauerhaft zuverlässig läuft.';

  @override
  String get onboardingOpenAppSettings => 'App-Einstellungen öffnen';

  @override
  String get onboardingIosGuidedAccessTitle => 'iOS: Geführter Zugriff';

  @override
  String get onboardingIosGuidedAccessBody =>
      'iOS erlaubt Apps grundsätzlich keinen Autostart und keinen echten Kiosk-Modus. Der ehrliche, zuverlässige Weg auf iPhone/iPad ist der systemeigene \"Geführte Zugriff\" (Einstellungen -> Bedienungshilfen -> Geführter Zugriff aktivieren, danach dreimal die Seitentaste drücken, während PhotoFrame geöffnet ist). Das muss nach jedem Neustart des Geräts manuell erneut gestartet werden - das ist eine Plattformgrenze, keine Einschränkung dieser App.';

  @override
  String get onboardingAutostartHintsTitle =>
      'Android-Hersteller: Autostart erlauben';

  @override
  String get onboardingAutostartHintsIntro =>
      'Viele Android-Hersteller drosseln Apps im Hintergrund zusätzlich zu den Android-eigenen Einstellungen noch mit eigenen Mechanismen. Falls PhotoFrame nach einem Neustart nicht zuverlässig startet oder die Diashow einfriert, prüfe je nach Hersteller:';

  @override
  String get onboardingAutostartXiaomi =>
      'Xiaomi / MIUI: In der App \"Sicherheit\" (Security) unter \"Autostart\" (Autostart-Verwaltung) PhotoFrame erlauben.';

  @override
  String get onboardingAutostartHuawei =>
      'Huawei / EMUI: Unter \"Geschützte Apps\" (Protected apps) bzw. Akku-Manager PhotoFrame als geschützt markieren, damit sie nicht beendet wird.';

  @override
  String get onboardingAutostartSamsung =>
      'Samsung: Unter Akku -> \"Nicht überwachte Apps\" (Unmonitored apps) PhotoFrame hinzufügen, damit Samsung die App nicht automatisch schließt.';

  @override
  String get onboardingAutostartOnePlusOppoVivo =>
      'OnePlus / OPPO / Vivo: In den Akku-/Autostart-Einstellungen (oft \"Autostart-Verwaltung\" oder \"Akku-Optimierung\") PhotoFrame auf die Whitelist setzen.';

  @override
  String get onboardingAutostartOutro =>
      'Die genauen Menübezeichnungen unterscheiden sich je nach Android-Version und Hersteller-Skin geringfügig. Diese Seite öffnet bewusst keine herstellerspezifischen Einstellungen automatisch, da sich deren Pfade zu häufig ändern - nutze stattdessen die App-/Akku-Einstellungen deines Geräts.';

  @override
  String get onboardingAddSourceTitle => 'Quelle hinzufügen';

  @override
  String get onboardingAddSourceBody =>
      'Fast geschafft! Füge jetzt eine Bildquelle hinzu (z. B. einen lokalen Ordner, eine Netzwerkfreigabe oder Nextcloud), damit die Diashow starten kann. Du kannst das auch später jederzeit über Einstellungen -> Quellen erledigen.';

  @override
  String get onboardingAndroidOnlyStepBody =>
      'Dieser Schritt betrifft nur Android-Geräte und wird auf diesem Gerät übersprungen.';

  @override
  String get settingsLanguageTitle => 'Sprache';

  @override
  String get settingsLanguageSubtitle => 'App-Sprache festlegen';

  @override
  String get languageScreenTitle => 'Sprache';

  @override
  String get languageSystemOption => 'Systemsprache';

  @override
  String get pairingSendConfigButton => 'Konfiguration an Gerät senden';

  @override
  String get pairingNoRelayHint =>
      'Erst einen Relay-Server einrichten, um Geräte zu koppeln.';

  @override
  String get pairingNoActivePairingHint =>
      'Noch keine Pairing-Gruppe verbunden.';

  @override
  String configPushConfirmSmbTitle(String senderLabel) {
    return 'Neue SMB-Quelle von $senderLabel übernehmen?';
  }
}
