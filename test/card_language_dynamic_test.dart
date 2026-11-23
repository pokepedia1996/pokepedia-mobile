import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/catalog_language_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/widgets/card_language_badge.dart';
import 'package:pokepedia_mobile/shared/widgets/catalog_language_toggle.dart';

/// The catalogs are rows in `catalog_categories` now, not an enum: a new one
/// reaches the app without a release, and one the app has never heard of
/// stays itself instead of passing for Indonesian.
void main() {
  tearDown(CardLanguage.resetKnown);

  group('CardLanguage.fromRaw', () {
    test('Chinese is a catalog of its own, not Indonesian', () {
      expect(CardLanguage.fromRaw('cn'), CardLanguage.cn);
      expect(CardLanguage.fromRaw('cn').shortLabel, 'CN');
    });

    test('an unknown code keeps its own code as its label', () {
      final kr = CardLanguage.fromRaw('kr');
      expect(kr.raw, 'kr');
      expect(kr.shortLabel, 'KR');
      expect(kr, isNot(CardLanguage.id));
    });

    test('a missing code is Indonesian, as every row was before', () {
      expect(CardLanguage.fromRaw(null), CardLanguage.id);
      expect(CardLanguage.fromRaw(''), CardLanguage.id);
    });

    test("the server's list names a catalog the build does not know", () {
      CardLanguage.useServerList([
        CardLanguage.id,
        CardLanguage.fromCatalogRow({
          'code': 'kr',
          'label': 'KR',
          'name': 'Korea',
          'icon_url': '/flags/kr.svg',
          'in_scanner': false,
        })!,
      ]);
      expect(CardLanguage.fromRaw('kr').labelId, 'Korea');
      expect(CardLanguage.known.map((l) => l.raw), ['id', 'kr']);
    });

    test('an empty server list keeps the built-in one', () {
      CardLanguage.useServerList(const []);
      expect(CardLanguage.known, CardLanguage.builtIn);
    });
  });

  group('the catalog switch', () {
    Future<void> pump(WidgetTester tester, List<CardLanguage> languages) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              catalogLanguagesProvider.overrideWith((ref) async => languages),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: CatalogLanguageToggle()),
            ),
          ),
        );

    testWidgets('offers every catalog the server lists', (tester) async {
      await pump(tester, CardLanguage.builtIn);
      await tester.pump();
      for (final label in ['ID', 'EN', 'JP', 'CN']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('drops one the server switched off', (tester) async {
      await pump(tester, [CardLanguage.id, CardLanguage.en]);
      await tester.pump();
      expect(find.text('JP'), findsNothing);
      expect(find.text('CN'), findsNothing);
    });
  });

  group('the flag badge', () {
    Future<void> pump(WidgetTester tester, CardLanguage language) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(body: CardLanguageBadge(language: language)),
          ),
        );

    testWidgets('CN has its own bundled flag', (tester) async {
      await pump(tester, CardLanguage.cn);
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('a catalog with no artwork shows its code', (tester) async {
      await pump(tester, CardLanguage.fromRaw('kr'));
      expect(find.text('KR'), findsOneWidget);
    });
  });
}
