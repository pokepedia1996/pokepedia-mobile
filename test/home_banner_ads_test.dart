import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/ads/repository/ads_repository.dart';
import 'package:pokepedia_mobile/features/ads/usecase/ad_link.dart';
import 'package:pokepedia_mobile/features/ads/usecase/ads_notifier.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/home_banner_carousel.dart';

/// Beranda's banners come only from the `ads` table: every booking for
/// `home` is a banner in the carousel, and each `href` is read the same way.
AdModel _ad(int id, String type, {String href = '/scan'}) => AdModel.fromRow({
  'id': id,
  'company_name': 'Iklan $id',
  'image_url': 'https://example.com/banner-$id.png',
  'href': href,
  'slot_position': id,
  'ad_type': type,
})!;

Widget _app(Widget child, List<AdModel> ads) => ProviderScope(
  overrides: [adsProvider(AdPlacement.home).overrideWith((ref) async => ads)],
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('href', () {
    test('an app path opens in the app; a tab is switched to', () {
      final scan = AdLinkTarget.parse('/scan') as AdInAppLink;
      expect(scan.location, '/scan');
      expect(scan.isTab, isFalse);
      expect((AdLinkTarget.parse(' /seller ') as AdInAppLink).isTab, isTrue);
      expect(
        (AdLinkTarget.parse('/market?tab=toko') as AdInAppLink).isTab,
        isTrue,
      );
    });

    test('a pokepedia.id link opens in the app by its path', () {
      final link =
          AdLinkTarget.parse('https://www.pokepedia.id/market/toko-ash?x=1')
              as AdInAppLink;
      expect(link.location, '/market/toko-ash?x=1');
      expect(
        (AdLinkTarget.parse('https://pokepedia.id') as AdInAppLink).location,
        '/',
      );
    });

    test("anyone else's site opens in the browser", () {
      final link =
          AdLinkTarget.parse('https://tokoku.example/promo') as AdExternalLink;
      expect(link.uri.host, 'tokoku.example');
    });

    test('nothing usable does nothing', () {
      expect(AdLinkTarget.parse(''), isNull);
      expect(AdLinkTarget.parse('scan'), isNull);
      expect(AdLinkTarget.parse('//evil.example/x'), isNull);
      expect(AdLinkTarget.parse('javascript:alert(1)'), isNull);
    });
  });

  testWidgets('every booking for home is a banner, in slot order', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const HomeBannerCarousel(), [_ad(1, 'sliding'), _ad(2, 'static')]),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Iklan 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Iklan 2'), findsOneWidget);
    // One dot per banner.
    expect(find.byType(AnimatedContainer), findsNWidgets(2));
  });

  testWidgets('nothing booked means no banner row at all', (tester) async {
    await tester.pumpWidget(_app(const HomeBannerCarousel(), const []));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsNothing);
    expect(
      tester.getSize(find.byType(HomeBannerCarousel)).height,
      0,
      reason: 'no gap left behind either',
    );
  });
}
