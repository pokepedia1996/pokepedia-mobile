import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_colors.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';

/// Converts an OKLCH triple to sRGB, the way the browser does.
///
/// Kept here rather than in `lib/`: the app ships hex constants, and this is
/// only the arithmetic that proves they are the right ones.
Color _oklch(double l, double c, double hDeg) {
  final h = hDeg * math.pi / 180;
  final a = c * math.cos(h);
  final b = c * math.sin(h);

  final lp = l + 0.3963377774 * a + 0.2158037573 * b;
  final mp = l - 0.1055613458 * a - 0.0638541728 * b;
  final sp = l - 0.0894841775 * a - 1.2914855480 * b;
  final l3 = lp * lp * lp, m3 = mp * mp * mp, s3 = sp * sp * sp;

  int enc(double u) {
    final v = u > 0.0031308 ? 1.055 * math.pow(u, 1 / 2.4) - 0.055 : 12.92 * u;
    return (v * 255).round().clamp(0, 255);
  }

  return Color.fromARGB(
    255,
    enc(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3),
    enc(-1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3),
    enc(-0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3),
  );
}

/// Every `--color-brand-*` token the site defines, read from its own CSS so
/// the expectation can't be copied wrong.
Map<String, Color> _webBrandColours() {
  final css = File('../pokepedia-web/app/globals.css').readAsStringSync();
  final pattern = RegExp(
    r'--color-brand-([a-z]+)(?:-(\d+))?:\s*oklch\(([\d.]+)%\s+([\d.]+)\s+([\d.]+)\)',
  );
  return {
    for (final m in pattern.allMatches(css))
      '${m.group(1)}${m.group(2) ?? ''}': _oklch(
        double.parse(m.group(3)!) / 100,
        double.parse(m.group(4)!),
        double.parse(m.group(5)!),
      ),
  };
}

const _palette = <String, Color>{
  'black10': AppColors.black10,
  'black20': AppColors.black20,
  'black30': AppColors.black30,
  'black40': AppColors.black40,
  'black50': AppColors.black50,
  'black': AppColors.black,
  'black60': AppColors.black60,
  'black70': AppColors.black70,
  'black80': AppColors.black80,
  'black90': AppColors.black90,
  'black100': AppColors.black100,
  'red10': AppColors.red10,
  'red20': AppColors.red20,
  'red30': AppColors.red30,
  'red40': AppColors.red40,
  'red50': AppColors.red50,
  'red': AppColors.red,
  'red60': AppColors.red60,
  'red70': AppColors.red70,
  'red80': AppColors.red80,
  'red90': AppColors.red90,
  'red100': AppColors.red100,
};

void main() {
  test('the brand ramp matches the site token for token', () {
    final web = _webBrandColours();
    // Guard the guard: a regex that matched nothing would pass everything.
    expect(web.length, greaterThan(50), reason: 'no tokens parsed from CSS');

    final wrong = <String>[];
    _palette.forEach((name, mobile) {
      final expected = web[name];
      if (expected == null) return;
      if (expected.toARGB32() != mobile.toARGB32()) {
        wrong.add(
          '$name: site '
          '#${expected.toARGB32().toRadixString(16).substring(2).toUpperCase()}'
          ' vs app '
          '#${mobile.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
        );
      }
    });
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  // testWidgets, not test: building the theme resolves the Google font,
  // which needs a binding.
  testWidgets('primary and error are the brand red the site uses', (
    tester,
  ) async {
    final web = _webBrandColours();
    // `--primary` and `--destructive` are the same token on the site:
    // brand-red in light, brand-red-50 in dark.
    expect(AppTheme.light.colorScheme.primary, web['red']);
    expect(AppTheme.light.colorScheme.error, web['red']);
    expect(AppTheme.dark.colorScheme.primary, web['red50']);
    expect(AppTheme.dark.colorScheme.error, web['red50']);
  });
}
