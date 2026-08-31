import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// Name der App, z. B. im Fenster-/Task-Titel.
  ///
  /// In de, this message translates to:
  /// **'PhotoFrame'**
  String get appTitle;

  /// Generische Fehleranzeige mit eingebetteter Fehlermeldung.
  ///
  /// In de, this message translates to:
  /// **'Fehler: {message}'**
  String commonError(String message);

  /// Beschriftung eines Abbrechen-Buttons.
  ///
  /// In de, this message translates to:
  /// **'Abbrechen'**
  String get commonCancel;

  /// Beschriftung eines Zurück-Buttons (z. B. im Onboarding).
  ///
  /// In de, this message translates to:
  /// **'Zurück'**
  String get commonBack;

  /// Beschriftung eines Weiter-Buttons (z. B. im Onboarding).
  ///
  /// In de, this message translates to:
  /// **'Weiter'**
  String get commonNext;

  /// AppBar-Titel der zentralen Einstellungen-Übersicht.
  ///
  /// In de, this message translates to:
  /// **'Einstellungen'**
  String get settingsScreenTitle;

  /// Gruppenüberschrift in den Einstellungen.
  ///
  /// In de, this message translates to:
  /// **'Diashow'**
  String get settingsGroupSlideshow;

  /// Gruppenüberschrift in den Einstellungen.
  ///
  /// In de, this message translates to:
  /// **'Inhalte'**
  String get settingsGroupContent;

  /// Gruppenüberschrift in den Einstellungen.
  ///
  /// In de, this message translates to:
  /// **'Teilen'**
  String get settingsGroupSharing;

  /// Gruppenüberschrift in den Einstellungen.
  ///
  /// In de, this message translates to:
  /// **'Allgemein'**
  String get settingsGroupGeneral;

  /// Titel des Diashow-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Diashow'**
  String get settingsSlideshowTitle;

  /// Untertitel des Diashow-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Intervall, Overlays, Anzeige-Modus, Übergänge'**
  String get settingsSlideshowSubtitle;

  /// Titel des Dauer-Modus-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Dauer-Modus'**
  String get settingsAlwaysOnTitle;

  /// Untertitel des Dauer-Modus-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Bildschirm dauerhaft an lassen'**
  String get settingsAlwaysOnSubtitle;

  /// Titel des Nachtmodus-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Nachtmodus'**
  String get settingsNightModeTitle;

  /// Untertitel des Nachtmodus-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Zeitplan, Dimm-Stärke'**
  String get settingsNightModeSubtitle;

  /// Titel des Wetter-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Wetter'**
  String get settingsWeatherTitle;

  /// Untertitel des Wetter-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Overlay an/aus, Ort'**
  String get settingsWeatherSubtitle;

  /// Titel des Quellen-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Quellen'**
  String get settingsSourcesTitle;

  /// Untertitel des Quellen-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Ordner, Freigaben, Nextcloud verwalten'**
  String get settingsSourcesSubtitle;

  /// Titel des Cache-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Cache-Verwaltung'**
  String get settingsCacheTitle;

  /// Untertitel des Cache-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Belegter Speicher, Limit, Cache leeren'**
  String get settingsCacheSubtitle;

  /// Titel des Pool/Index-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Pool/Index'**
  String get settingsPoolTitle;

  /// Untertitel des Pool/Index-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Arbeitsmenge, Auffüll-Intervall, neue Bilder'**
  String get settingsPoolSubtitle;

  /// Titel des Sharing-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Sharing/Relay'**
  String get settingsSharingTitle;

  /// Untertitel des Sharing-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Relay-Server-URL, Pairing'**
  String get settingsSharingSubtitle;

  /// Titel des Barrierefreiheit-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Barrierefreiheit'**
  String get settingsAccessibilityTitle;

  /// Titel des Eintrags, der zur OEM-Autostart-Hilfeseite führt.
  ///
  /// In de, this message translates to:
  /// **'Autostart auf diesem Handy-Hersteller'**
  String get settingsAutostartHelpTitle;

  /// Untertitel des Eintrags, der zur OEM-Autostart-Hilfeseite führt.
  ///
  /// In de, this message translates to:
  /// **'Xiaomi, Huawei, Samsung, OnePlus & Co.'**
  String get settingsAutostartHelpSubtitle;

  /// Titel des Kiosk-Modus-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Fotorahmen-Startbildschirm'**
  String get settingsKioskTitle;

  /// Untertitel des Kiosk-Modus-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Als Home-Bildschirm einrichten, Bildschirm fixieren'**
  String get settingsKioskSubtitle;

  /// AppBar-Titel der Kiosk-Modus-Einstellungsseite.
  ///
  /// In de, this message translates to:
  /// **'Fotorahmen-Startbildschirm'**
  String get kioskScreenTitle;

  /// Beschriftung des Kiosk-Modus-Schalters.
  ///
  /// In de, this message translates to:
  /// **'Als Fotorahmen-Startbildschirm verwenden'**
  String get kioskToggleTitle;

  /// Untertitel des Kiosk-Modus-Schalters.
  ///
  /// In de, this message translates to:
  /// **'Registriert die App als Home-Bildschirm und fixiert den Bildschirm während der Diashow'**
  String get kioskToggleSubtitle;

  /// Einleitungstext der Kiosk-Modus-Einstellungsseite.
  ///
  /// In de, this message translates to:
  /// **'Verwandelt dieses Gerät in einen dedizierten digitalen Fotorahmen: PhotoFrame wird als Startbildschirm (Home-App) auswählbar, und der Bildschirm wird beim Betreten der Diashow fixiert (Screen-Pinning), damit niemand versehentlich zu anderen Apps wechselt.'**
  String get kioskIntro;

  /// Button, der die Bildschirmfixierung (Screen-Pinning) sofort beendet, unabhängig vom Schalter-Zustand.
  ///
  /// In de, this message translates to:
  /// **'Bildschirmfixierung jetzt sofort beenden'**
  String get kioskExitNowButton;

  /// Hinweis zum Home-App-Auswahldialog auf der Kiosk-Modus-Einstellungsseite.
  ///
  /// In de, this message translates to:
  /// **'Nach dem Aktivieren erscheint beim nächsten Drücken der Home-Taste ein Systemdialog, mit dem du PhotoFrame als Standard-Startbildschirm festlegen kannst. Das musst du selbst bestätigen - Android erlaubt es Apps nicht, diesen Dialog automatisch zu bestätigen oder zu umgehen.'**
  String get kioskHomeAppNote;

  /// Hinweis zum Screen-Pinning-Verhalten auf der Kiosk-Modus-Einstellungsseite.
  ///
  /// In de, this message translates to:
  /// **'Sobald die Diashow startet, wird der Bildschirm fixiert (Screen-Pinning). Da diese App keine Geräteverwaltungs-/MDM-Rechte hat, zeigt Android dabei am oberen Bildschirmrand ggf. einen kleinen \"Entsperren\"/\"Verlassen\"-Hinweis an - das ist Plattformverhalten und kann von dieser App nicht vollständig unterdrückt werden.'**
  String get kioskPinningNote;

  /// Hinweis zur Plattformgrenze (nur Android) auf der Kiosk-Modus-Einstellungsseite.
  ///
  /// In de, this message translates to:
  /// **'Nur auf Android verfügbar. Auf iOS gibt es keinen vergleichbaren Autostart-Mechanismus für Drittanbieter-Apps - dort hilft nur der systemeigene \"Geführte Zugriff\" (siehe Onboarding).'**
  String get kioskAndroidOnlyNote;

  /// Titel des Eintrags, der das Onboarding erneut öffnet.
  ///
  /// In de, this message translates to:
  /// **'Setup-Guide erneut anzeigen'**
  String get settingsReplayOnboardingTitle;

  /// AppBar-Titel der Cache-Verwaltung.
  ///
  /// In de, this message translates to:
  /// **'Cache-Verwaltung'**
  String get cacheScreenTitle;

  /// Überschrift über der Speicher-Fortschrittsanzeige.
  ///
  /// In de, this message translates to:
  /// **'Belegter Speicher'**
  String get cacheUsedStorageLabel;

  /// Zeigt an, wie viel vom Cache-Limit bereits belegt ist.
  ///
  /// In de, this message translates to:
  /// **'{used} von {limit} belegt'**
  String cacheUsedOfLimit(String used, String limit);

  /// Beschriftung des Sliders zum Einstellen des Cache-Limits.
  ///
  /// In de, this message translates to:
  /// **'Cache-Limit: {limit}'**
  String cacheLimitLabel(String limit);

  /// Erklärender Hinweistext unter dem Cache-Limit-Slider.
  ///
  /// In de, this message translates to:
  /// **'Das Limit wird zusätzlich gegen den tatsächlich freien Gerätespeicher gedeckelt (mind. 1 GB/10% Reserve).'**
  String get cacheLimitDeviceCapHint;

  /// Beschriftung des Buttons zum Leeren des Bild-Caches.
  ///
  /// In de, this message translates to:
  /// **'Cache leeren'**
  String get cacheClearButton;

  /// Bestätigungsmeldung nach dem Leeren des Caches.
  ///
  /// In de, this message translates to:
  /// **'Cache geleert'**
  String get cacheClearedSnackbar;

  /// Button, um das Onboarding zu überspringen.
  ///
  /// In de, this message translates to:
  /// **'Überspringen'**
  String get onboardingSkip;

  /// Beschriftung des letzten Weiter-Buttons im Onboarding.
  ///
  /// In de, this message translates to:
  /// **'Quelle hinzufügen'**
  String get onboardingAddSourceCta;

  /// Titel der ersten Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'Willkommen bei PhotoFrame'**
  String get onboardingWelcomeTitle;

  /// Erklärtext der ersten Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'PhotoFrame verwandelt dieses Gerät in einen digitalen Fotorahmen: Es zeigt Bilder aus deinen Ordnern (z. B. Netzwerkfreigabe, Nextcloud oder lokaler Speicher) als Endlos-Diashow und kann Fotos mit anderen Frames teilen. Dieser kurze Guide richtet das Gerät in wenigen Schritten dafür ein.'**
  String get onboardingWelcomeBody;

  /// Titel der Dauer-Modus-Erklärseite im Onboarding.
  ///
  /// In de, this message translates to:
  /// **'Dauer-Modus: Bildschirm bleibt an'**
  String get onboardingAlwaysOnTitle;

  /// Erklärtext der Dauer-Modus-Seite im Onboarding.
  ///
  /// In de, this message translates to:
  /// **'Ein Fotorahmen soll dauerhaft leuchten - deshalb kann PhotoFrame verhindern, dass der Bildschirm ausgeht oder das Gerät sich sperrt. Das ist das Kernfeature dieser App, kostet aber spürbar Akku.'**
  String get onboardingAlwaysOnBody;

  /// Empfehlungs-Hinweisbox auf der Dauer-Modus-Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'Empfehlung: Dauer-Modus nur bei dauerhaft angeschlossenem Ladekabel verwenden (z. B. wandmontiert). Du kannst später in den Einstellungen zwischen \"immer an\", \"nur während der Diashow\" und einem Zeitplan (kombiniert mit dem Nachtmodus) wählen.'**
  String get onboardingAlwaysOnRecommendation;

  /// Titel der Android-Home-App-Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'Als Startbildschirm einrichten'**
  String get onboardingAndroidHomeAppTitle;

  /// Hinweistext, wenn ein Android-spezifischer Onboarding-Schritt auf anderen Plattformen übersprungen wird.
  ///
  /// In de, this message translates to:
  /// **'Dieser Schritt betrifft nur Android-Geräte und wird auf diesem Gerät übersprungen.'**
  String get onboardingAndroidHomeAppSkippedBody;

  /// Erklärtext der Android-Home-App-Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'Damit PhotoFrame nach jedem Neustart automatisch erscheint, kannst du die App als Standard-Startbildschirm (Home-App/Launcher) festlegen: Android-Einstellungen -> Apps -> Standard-Apps -> Startbildschirm-App -> PhotoFrame auswählen.'**
  String get onboardingAndroidHomeAppBody;

  /// Button, der die Android-Systemeinstellungen öffnet.
  ///
  /// In de, this message translates to:
  /// **'Android-Einstellungen öffnen'**
  String get onboardingOpenAndroidSettings;

  /// Titel der Akku-Optimierung-Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'Von Akku-Optimierung ausnehmen'**
  String get onboardingBatteryOptTitle;

  /// Erklärtext der Akku-Optimierung-Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'Android beendet App-Aktivität im Hintergrund gerne, um Akku zu sparen - das kann die Diashow ausbremsen oder Bilder verzögert aktualisieren. Nimm PhotoFrame in den Einstellungen unter \"Akku -> Nicht optimieren\"/\"Akkuoptimierung ignorieren\" aus der Optimierung aus, damit sie dauerhaft zuverlässig läuft.'**
  String get onboardingBatteryOptBody;

  /// Button, der die App-Einstellungen öffnet.
  ///
  /// In de, this message translates to:
  /// **'App-Einstellungen öffnen'**
  String get onboardingOpenAppSettings;

  /// Titel der iOS-Guided-Access-Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'iOS: Geführter Zugriff'**
  String get onboardingIosGuidedAccessTitle;

  /// Erklärtext der iOS-Guided-Access-Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'iOS erlaubt Apps grundsätzlich keinen Autostart und keinen echten Kiosk-Modus. Der ehrliche, zuverlässige Weg auf iPhone/iPad ist der systemeigene \"Geführte Zugriff\" (Einstellungen -> Bedienungshilfen -> Geführter Zugriff aktivieren, danach dreimal die Seitentaste drücken, während PhotoFrame geöffnet ist). Das muss nach jedem Neustart des Geräts manuell erneut gestartet werden - das ist eine Plattformgrenze, keine Einschränkung dieser App.'**
  String get onboardingIosGuidedAccessBody;

  /// Titel der OEM-Autostart-Hinweisseite im Onboarding.
  ///
  /// In de, this message translates to:
  /// **'Android-Hersteller: Autostart erlauben'**
  String get onboardingAutostartHintsTitle;

  /// Einleitungstext der OEM-Autostart-Hinweisseite.
  ///
  /// In de, this message translates to:
  /// **'Viele Android-Hersteller drosseln Apps im Hintergrund zusätzlich zu den Android-eigenen Einstellungen noch mit eigenen Mechanismen. Falls PhotoFrame nach einem Neustart nicht zuverlässig startet oder die Diashow einfriert, prüfe je nach Hersteller:'**
  String get onboardingAutostartHintsIntro;

  /// Hersteller-spezifischer Autostart-Hinweis für Xiaomi/MIUI.
  ///
  /// In de, this message translates to:
  /// **'Xiaomi / MIUI: In der App \"Sicherheit\" (Security) unter \"Autostart\" (Autostart-Verwaltung) PhotoFrame erlauben.'**
  String get onboardingAutostartXiaomi;

  /// Hersteller-spezifischer Autostart-Hinweis für Huawei/EMUI.
  ///
  /// In de, this message translates to:
  /// **'Huawei / EMUI: Unter \"Geschützte Apps\" (Protected apps) bzw. Akku-Manager PhotoFrame als geschützt markieren, damit sie nicht beendet wird.'**
  String get onboardingAutostartHuawei;

  /// Hersteller-spezifischer Autostart-Hinweis für Samsung.
  ///
  /// In de, this message translates to:
  /// **'Samsung: Unter Akku -> \"Nicht überwachte Apps\" (Unmonitored apps) PhotoFrame hinzufügen, damit Samsung die App nicht automatisch schließt.'**
  String get onboardingAutostartSamsung;

  /// Hersteller-spezifischer Autostart-Hinweis für OnePlus/OPPO/Vivo.
  ///
  /// In de, this message translates to:
  /// **'OnePlus / OPPO / Vivo: In den Akku-/Autostart-Einstellungen (oft \"Autostart-Verwaltung\" oder \"Akku-Optimierung\") PhotoFrame auf die Whitelist setzen.'**
  String get onboardingAutostartOnePlusOppoVivo;

  /// Abschließender Hinweis auf der OEM-Autostart-Hinweisseite.
  ///
  /// In de, this message translates to:
  /// **'Die genauen Menübezeichnungen unterscheiden sich je nach Android-Version und Hersteller-Skin geringfügig. Diese Seite öffnet bewusst keine herstellerspezifischen Einstellungen automatisch, da sich deren Pfade zu häufig ändern - nutze stattdessen die App-/Akku-Einstellungen deines Geräts.'**
  String get onboardingAutostartOutro;

  /// Titel der letzten Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'Quelle hinzufügen'**
  String get onboardingAddSourceTitle;

  /// Erklärtext der letzten Onboarding-Seite.
  ///
  /// In de, this message translates to:
  /// **'Fast geschafft! Füge jetzt eine Bildquelle hinzu (z. B. einen lokalen Ordner, eine Netzwerkfreigabe oder Nextcloud), damit die Diashow starten kann. Du kannst das auch später jederzeit über Einstellungen -> Quellen erledigen.'**
  String get onboardingAddSourceBody;

  /// Generischer Hinweis für Android-only Onboarding-Schritte auf anderen Plattformen.
  ///
  /// In de, this message translates to:
  /// **'Dieser Schritt betrifft nur Android-Geräte und wird auf diesem Gerät übersprungen.'**
  String get onboardingAndroidOnlyStepBody;

  /// Titel des Sprach-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get settingsLanguageTitle;

  /// Untertitel des Sprach-Einstellungseintrags.
  ///
  /// In de, this message translates to:
  /// **'App-Sprache festlegen'**
  String get settingsLanguageSubtitle;

  /// AppBar-Titel der Sprachauswahl-Seite.
  ///
  /// In de, this message translates to:
  /// **'Sprache'**
  String get languageScreenTitle;

  /// Option in der Sprachauswahl, die der Systemsprache des Geräts folgt.
  ///
  /// In de, this message translates to:
  /// **'Systemsprache'**
  String get languageSystemOption;

  /// Button auf der Pairing-Übersichtsseite, der zum Senden einer Konfiguration an ein anderes gepaartes Gerät führt.
  ///
  /// In de, this message translates to:
  /// **'Konfiguration an Gerät senden'**
  String get pairingSendConfigButton;

  /// Hinweistext, wenn noch keine Relay-Server-URL konfiguriert ist.
  ///
  /// In de, this message translates to:
  /// **'Erst einen Relay-Server einrichten, um Geräte zu koppeln.'**
  String get pairingNoRelayHint;

  /// Hinweistext, wenn ein Relay-Server konfiguriert ist, aber noch keine Pairing-Gruppe aktiv ist.
  ///
  /// In de, this message translates to:
  /// **'Noch keine Pairing-Gruppe verbunden.'**
  String get pairingNoActivePairingHint;

  /// Bestätigungsfrage auf der Config-Push-Bestätigungsseite für eine empfangene SMB-Quelle.
  ///
  /// In de, this message translates to:
  /// **'Neue SMB-Quelle von {senderLabel} übernehmen?'**
  String configPushConfirmSmbTitle(String senderLabel);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
