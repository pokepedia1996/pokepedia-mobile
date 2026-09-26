import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/config/app_config.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/presentation/widgets/card_market_header.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The share button sits beside the wishlist heart on the card header. It
/// sends the web URL, not a deep link: the recipient may not have the app,
/// and both clients serve /expansions/{packSlug}/{cardId}.
const _card = CardModel(
  id: 98_765,
  category: CardCategory.pokemon,
  nameId: 'Oshawott',
  expansionCode: 'M-P',
  packSlug: 'm-p',
  collectorNumber: '151/M-P',
  rarity: 'PROMO',
);

void main() {
  testWidgets('renders as a pill beside the heart', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: ShareCardButton(card: _card))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.share2), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('links to the card on the web, matching the store share link', () {
    // Same host the store poster shares, so both point at one place.
    final button = const ShareCardButton(card: _card);
    expect(
      button.url,
      '${AppConfig.appUrl}/expansions/m-p/98765',
    );
  });
}
