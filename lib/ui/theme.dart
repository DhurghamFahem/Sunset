import 'package:flutter/material.dart';

// Shared studio palette; text colors retain contrast on paper surfaces.
const forest = Color(0xFF254B40);
const ivory = Color(0xFFF8F7F2);
const muted = Color(0xFF66736B);
const ink = Color(0xFF22392F);
const sage = Color(0xFFE8EEE6);
const line = Color(0xFFDDE3D9);
const paper = Color(0xFFFFFFFF);
const clay = Color(0xFF866449);

ThemeData catalogTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: forest,
    primary: forest,
    onPrimary: paper,
    primaryContainer: sage,
    onPrimaryContainer: forest,
    secondary: clay,
    secondaryContainer: sage,
    onSecondaryContainer: forest,
    surface: ivory,
    onSurface: ink,
    outline: muted,
    outlineVariant: line,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoArabic',
    fontFamilyFallback: const ['G2GSymbols'],
    scaffoldBackgroundColor: ivory,
    colorScheme: scheme,
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 36,
        height: 1.5,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        height: 1.5,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        height: 1.5,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        height: 1.5,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.6,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.6,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.7, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.7, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.6, color: muted),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ivory,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 72,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoArabic',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      shape: Border(bottom: BorderSide(color: line)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: paper,
      hintStyle: const TextStyle(color: muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: forest, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'NotoArabic',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        shape: shape,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        side: const BorderSide(color: line),
        backgroundColor: paper,
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: paper,
      selectedColor: sage,
      checkmarkColor: forest,
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(
        fontFamily: 'NotoArabic',
        color: forest,
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    cardTheme: CardThemeData(
      color: paper,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: line),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ivory,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: ivory,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: line,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
      iconColor: forest,
      textColor: forest,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: forest,
      linearTrackColor: sage,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: paper,
      indicatorColor: sage,
    ),
  );
}
