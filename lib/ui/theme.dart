import 'package:flutter/material.dart';

const ink = Color(0xFF1E1A17);
const paper = Color(0xFFF3F0E8);
const card = Color(0xFFFFFCF7);
const line = Color(0xFFE4DDD2);
const accent = Color(0xFF0F6E56);
const transit = Color(0xFF3E5870);
const layoverAmber = Color(0xFF8A5A00);
const gapInk = Color(0xFF8C4A32);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.light,
    surface: card,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
      surface: card,
      onSurface: ink,
    ),
    scaffoldBackgroundColor: paper,
    dividerColor: line,
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: paper,
      selectedIconTheme: IconThemeData(color: accent),
      indicatorColor: Color(0xFFDCE8E3),
    ),
  );
}

Color countryColor(String code) {
  const palette = <int>[
    0xFF0F6E56,
    0xFF1D4E89,
    0xFF8C4A32,
    0xFF6B4C9A,
    0xFFA15C07,
    0xFF0F766E,
    0xFF9F1239,
    0xFF3F6212,
    0xFF1E3A8A,
    0xFF155E75,
    0xFF7C2D12,
    0xFF831843,
    0xFF334155,
    0xFF0E7490,
    0xFF365314,
    0xFF92400E,
  ];
  if (code.length < 2) return transit;
  final index = (code.codeUnitAt(0) * 31 + code.codeUnitAt(1)) % palette.length;
  return Color(palette[index]);
}
