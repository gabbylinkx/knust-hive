import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// KNUST Hive palette — forest green + gold, inspired by KNUST regalia
/// and Ghana's flag colors, without leaning on the literal tricolor.
class AppColors {
  static const forest = Color(0xFF1B4332);
  static const forestLight = Color(0xFF2D6A4F);
  static const gold = Color(0xFFE3AE38);
  static const goldSoft = Color(0xFFF3D98B);
  static const clay = Color(0xFFB94A32); // alerts, "reported" states
  static const paper = Color(0xFFF3F5EE);
  static const paperDim = Color(0xFFE7EADD);
  static const ink = Color(0xFF152318);

  // Dark mode
  static const darkBg = Color(0xFF0E1912);
  static const darkSurface = Color(0xFF16261C);
  static const darkLine = Color(0xFF2A3B2E);
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.paper,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.forest,
        secondary: AppColors.gold,
        surface: Colors.white,
        error: AppColors.clay,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displaySmall: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        titleLarge: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        titleMedium: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.forest,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.paperDim),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.forest,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.paperDim),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.forest,
        unselectedItemColor: Color(0xFF8A9080),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.darkBg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.gold,
        secondary: AppColors.forestLight,
        surface: AppColors.darkSurface,
        error: AppColors.clay,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displaySmall: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700, color: Colors.white),
        titleLarge: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700, color: Colors.white),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.darkLine),
        ),
      ),
    );
  }
}
