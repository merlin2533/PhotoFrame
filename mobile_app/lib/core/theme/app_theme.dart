import 'package:flutter/material.dart';

/// Central Material 3 theme definitions for the app. Kept as simple static
/// [ThemeData] getters (no theme-extension machinery) since the app has no
/// custom branding requirements yet beyond a consistent seed color.
abstract final class AppTheme {
  static const Color _seedColor = Colors.indigo;

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: _seedColor,
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: _seedColor,
      );
}
