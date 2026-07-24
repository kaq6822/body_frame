import 'package:flutter/material.dart';

/// 앱 테마. Material 3 기반.
class AppTheme {
  AppTheme._();

  static const Color _seed = Color(0xFF3D5AFE);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        appBarTheme: const AppBarTheme(centerTitle: true),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(centerTitle: true),
      );
}
