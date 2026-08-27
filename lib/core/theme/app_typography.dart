import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale ported from the `.typo-*` utility classes in
/// `globals.css`. Heading styles use the bundled CalSans font
/// (`assets/fonts/CalSans-Regular.ttf`); body styles use Urbanist via
/// google_fonts, mirroring the web app's `--font-heading` / `--font-body`.
class AppTypography {
  AppTypography._();

  static const _heading = 'CalSans';

  static TextStyle display(Color color) => TextStyle(
    fontFamily: _heading,
    fontSize: 39,
    height: 1.15,
    letterSpacing: -0.4,
    color: color,
  );

  static TextStyle h1(Color color) => TextStyle(
    fontFamily: _heading,
    fontSize: 31,
    height: 1.2,
    letterSpacing: -0.2,
    color: color,
  );

  static TextStyle h2(Color color) =>
      TextStyle(fontFamily: _heading, fontSize: 25, height: 1.25, color: color);

  static TextStyle h3(Color color) =>
      TextStyle(fontFamily: _heading, fontSize: 20, height: 1.3, color: color);

  static TextStyle body(Color color) =>
      GoogleFonts.urbanist(fontSize: 16, height: 1.5, color: color);

  static TextStyle bodySemibold(Color color) => GoogleFonts.urbanist(
    fontSize: 16,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: color,
  );

  static TextStyle bodySm(Color color) =>
      GoogleFonts.urbanist(fontSize: 14, height: 1.5, color: color);

  static TextStyle bodySmSemibold(Color color) => GoogleFonts.urbanist(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w600,
    color: color,
  );

  static TextStyle caption(Color color) =>
      GoogleFonts.urbanist(fontSize: 12, height: 1.4, color: color);

  static TextStyle captionSemibold(Color color) => GoogleFonts.urbanist(
    fontSize: 12,
    height: 1.4,
    fontWeight: FontWeight.w600,
    color: color,
  );

  static TextStyle overline(Color color) => GoogleFonts.urbanist(
    fontSize: 11,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: color,
  );

  static TextStyle badge(Color color) => GoogleFonts.urbanist(
    fontSize: 11,
    height: 1.0,
    fontWeight: FontWeight.w700,
    color: color,
  );

  static TextTheme textTheme(Color foreground) => TextTheme(
    displayMedium: display(foreground),
    headlineLarge: h1(foreground),
    headlineMedium: h2(foreground),
    headlineSmall: h3(foreground),
    bodyLarge: body(foreground),
    bodyMedium: bodySm(foreground),
    bodySmall: caption(foreground),
    labelLarge: bodySmSemibold(foreground),
    labelMedium: overline(foreground),
    labelSmall: badge(foreground),
  );
}
