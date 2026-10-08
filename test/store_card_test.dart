import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';
import 'package:pokepedia_mobile/shared/widgets/reputation_star.dart';
import 'package:pokepedia_mobile/shared/widgets/seller_avatar.dart';
import 'package:pokepedia_mobile/shared/widgets/store_card.dart';

/// The market's Toko tab drew every store as a lettered circle with no
/// reputation, though `search_stores` returns the logo, the owner's avatar,
/// the feedback score and the positive share. Web's card shows all four.
void main() {
  StoreModel store({
    String? logoUrl,
    String? avatarUrl,
    int? feedbackScore,
    double? positivePct,
    String cityName = 'Kota Administrasi Jakarta Selatan',
  }) => StoreModel(
    handle: 'card-sanctuary',
    storeName: 'Card Sanctuary HQ',
    tagline: '',
    activeListingCount: 477,
    cityName: cityName,
    isVerified: true,
    topRated: false,
    itemsSoldCount: 0,
    followersCount: 0,
    logoUrl: logoUrl,
    avatarUrl: avatarUrl,
    feedbackScore: feedbackScore,
    positivePct: positivePct,
  );

  Future<void> pump(WidgetTester tester, StoreModel s, {double width = 400}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: StoreCard(store: s, onTap: () {}),
              ),
            ),
          ),
        ),
      );

  group('fromDirectoryRow', () {
    test('keeps what search_stores returns for the card', () {
      final s = StoreModel.fromDirectoryRow({
        'store_slug': 'card-sanctuary',
        'store_name': 'Card Sanctuary HQ',
        'store_logo_url': null,
        'avatar_url': 'https://example.com/me.png',
        'feedback_score': 20,
        'positive_pct': 97.5,
      });
      expect(s.imageUrl, isNotNull, reason: 'avatar stands in for a logo');
      expect(s.feedbackScore, 20);
      expect(s.positivePct, 97.5);
    });
  });

  testWidgets('shows the logo, or the owner\'s avatar without one', (
    tester,
  ) async {
    await pump(tester, store(avatarUrl: 'https://example.com/me.png'));
    final avatar = tester.widget<SellerAvatar>(find.byType(SellerAvatar));
    expect(avatar.imageUrl, 'https://example.com/me.png');

    await pump(
      tester,
      store(logoUrl: 'https://example.com/logo.png', avatarUrl: 'x'),
    );
    expect(
      tester.widget<SellerAvatar>(find.byType(SellerAvatar)).imageUrl,
      'https://example.com/logo.png',
    );
  });

  testWidgets('carries the reputation star and positive share', (tester) async {
    await pump(tester, store(feedbackScore: 20, positivePct: 100));
    expect(find.byType(ReputationStar), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    await pump(tester, store(feedbackScore: 3, positivePct: 87.5));
    expect(find.text('87.5%'), findsOneWidget);
  });

  testWidgets('an unrated store says nothing rather than 0%', (tester) async {
    await pump(tester, store());
    expect(find.byType(ReputationStar), findsNothing);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('a long city wraps instead of overflowing a narrow phone', (
    tester,
  ) async {
    await pump(tester, store(feedbackScore: 20, positivePct: 99), width: 300);
    expect(tester.takeException(), isNull);
  });
}
