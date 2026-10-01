import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/card_pricing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pricing is a garnish on the collection, not a precondition for it. The
/// grid, the header total and the chart all cope with a null price — so a
/// pricing call that fails must leave the cards unpriced and hand them back,
/// never throw. A throw here surfaces as "Gagal memuat data" over a
/// collection that loaded perfectly well.
CardModel _card(int id) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: 'Kartu $id',
  expansionCode: 'SV3',
  packSlug: 'sv3',
  collectorNumber: '$id/197',
  rarity: 'SAR',
  owned: 1,
);

void main() {
  test(
    'an unreachable price RPC leaves the cards unpriced, not thrown',
    () async {
      // Nothing is listening on this port, so every chunk fails.
      final client = SupabaseClient('http://localhost:1', 'anon-key');
      addTearDown(client.dispose);

      final cards = [for (var i = 1; i <= 900; i++) _card(i)];
      final priced = await priceCards(client, cards);

      expect(priced.length, cards.length);
      expect(priced.every((c) => c.marketPrice == null), isTrue);
    },
  );

  test('an empty collection is handed straight back', () async {
    final client = SupabaseClient('http://localhost:1', 'anon-key');
    addTearDown(client.dispose);

    expect(await priceCards(client, const []), isEmpty);
  });
}
