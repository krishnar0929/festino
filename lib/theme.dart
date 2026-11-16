import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A main color people can pick for the app (Account → App color).
class AppColor {
  const AppColor(this.id, this.name, this.color);
  final String id;
  final String name;
  final Color color;
}

const appColors = [
  AppColor('violet', 'Violet', Color(0xFF6C4CF5)),
  AppColor('ocean', 'Ocean', Color(0xFF1F6FEB)),
  AppColor('forest', 'Forest', Color(0xFF13895C)),
  AppColor('rose', 'Rose', Color(0xFFD6336C)),
  AppColor('tangerine', 'Tangerine', Color(0xFFE8590C)),
  AppColor('grape', 'Grape', Color(0xFF8E2FC4)),
  AppColor('teal', 'Teal', Color(0xFF0E8C94)),
  AppColor('midnight', 'Midnight', Color(0xFF34318A)),
];

AppColor appColorFor(String? id) => appColors.firstWhere((c) => c.id == id, orElse: () => appColors.first);

/// Switches the app's main color. Call [refreshAllScreens] afterwards.
void applyAppColor(String? id) => HC.violet = appColorFor(id).color;

/// Redraws every screen so a new app color shows everywhere right away.
void refreshAllScreens() {
  void walk(Element e) {
    e.markNeedsBuild();
    e.visitChildren(walk);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) walk(root);
}

/// Festino colors, taken from the approved design.
class HC {
  static const ink = Color(0xFF17142B);

  /// The app's main color (buttons, links, highlights). Violet unless the
  /// person picked another in Account → App color.
  static Color violet = const Color(0xFF6C4CF5);
  static const lime = Color(0xFFC8F560);
  static const coral = Color(0xFFFF6B4A);
  static const ground = Color(0xFFF6F5FB);
  static const card = Colors.white;
  static const line = Color(0xFFE3E0F0);
  static const track = Color(0xFFE9E6F5);
  static const muted = Color(0xFF5E5A72);
  static const nightCard = Color(0xFF26233A);
  static const nightMuted = Color(0xFFC9C5DA);

  /// Soft tile colors for game thumbnails and vendor photos.
  static const tiles = [
    Color(0xFFFFE0D8),
    Color(0xFFE4DCFF),
    Color(0xFFE9F8C6),
    Color(0xFFD9EEFF),
  ];
}

/// Space Grotesk for headings and big numbers.
TextStyle display(double size, {Color color = HC.ink, FontWeight weight = FontWeight.w700}) {
  return GoogleFonts.spaceGrotesk(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.08,
    letterSpacing: -0.025 * size,
  );
}

/// Inter for everything else.
TextStyle body(double size, {Color color = HC.ink, FontWeight weight = FontWeight.w400}) {
  return GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: 1.35);
}

TextStyle overline({Color color = HC.muted}) {
  return GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: color,
    letterSpacing: 0.6,
  );
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: HC.violet, primary: HC.violet, surface: HC.ground),
    scaffoldBackgroundColor: HC.ground,
  );
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: HC.ink, displayColor: HC.ink),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HC.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: HC.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: HC.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: HC.violet, width: 1.5)),
    ),
  );
}
