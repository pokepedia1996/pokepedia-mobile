import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/utils/sealed_image.dart';
import 'package:pokepedia_mobile/shared/utils/variant_label.dart';

CardModel _card({required int id, String category = 'Pokemon'}) =>
    CardModel.fromRow({
      'id': id,
      'category': category,
      'name_id': 'Kartu $id',
      'expansion_code': 'SV1',
      'collector_number': '001',
    });

void main() {
  group('isSealedCardId (lib/sealed/keys.test.ts)', () {
    test('ids above the base are sealed', () {
      expect(isSealedCardId(sealedCardIdBase + 1), isTrue);
      expect(isSealedCardId(9000162), isTrue);
    });

    test('the base itself and catalog ids are not', () {
      expect(isSealedCardId(sealedCardIdBase), isFalse);
      expect(isSealedCardId(12345), isFalse);
      expect(isSealedCardId(null), isFalse);
    });
  });

  group('CardModel.isSealed', () {
    test('the Sealed category maps to its own member', () {
      final card = _card(id: 42, category: 'Sealed');
      expect(card.category, CardCategory.sealed);
      expect(card.category.raw, 'Sealed');
      expect(card.category.labelId, 'Produk Segel');
      expect(card.isSealed, isTrue);
    });

    test('an id alone is enough, for rows built from a listing', () {
      expect(_card(id: 9000001).isSealed, isTrue);
    });

    test('a single is not sealed', () {
      expect(_card(id: 42).isSealed, isFalse);
    });
  });

  group('tradeCondition', () {
    test('a sealed product is always written as NM', () {
      final sealed = _card(id: 9000001, category: 'Sealed');
      expect(
        sealed.tradeCondition(CardCondition.values.last),
        CardCondition.nm,
      );
      for (final c in CardCondition.values) {
        expect(sealed.tradeCondition(c), CardCondition.nm);
      }
    });

    test('a single keeps what was picked', () {
      final single = _card(id: 42);
      for (final c in CardCondition.values) {
        expect(single.tradeCondition(c), c);
      }
    });

    test('the NM sent for sealed is the raw value the RPCs expect', () {
      final sealed = _card(id: 9000001);
      expect(
        sealed.tradeCondition(CardCondition.values.last).raw,
        CardCondition.nm.raw,
      );
    });
  });

  test('excludeSealed drops products and keeps singles in order', () {
    final cards = [
      _card(id: 1),
      _card(id: 9000001, category: 'Sealed'),
      _card(id: 2, category: 'Trainer'),
      _card(id: 9000002),
    ];
    expect(excludeSealed(cards).map((c) => c.id), [1, 2]);
  });

  group('cardTileImage', () {
    const master = 'https://cdn.pokepedia.id/sealed/sv1/booster-box.webp';

    test('sealed art is contained, from its thumbnail', () {
      final tile = cardTileImage(master);
      expect(tile.contain, isTrue);
      expect(
        tile.url,
        'https://cdn.pokepedia.id/sealed/sv1/booster-box_480.webp',
      );
    });

    test('a thumbnail URL is not suffixed twice', () {
      const thumb = 'https://cdn.pokepedia.id/sealed/sv1/booster-box_480.webp';
      expect(sealedThumbUrl(thumb), thumb);
    });

    test('card scans and foreign hosts stay cropped and untouched', () {
      const scan = 'https://cdn.pokepedia.id/cards/sv1/001.webp';
      expect(cardTileImage(scan), (url: scan, contain: false));
      const foreign = 'https://example.com/sealed/x.webp';
      expect(cardTileImage(foreign), (url: foreign, contain: false));
      expect(cardTileImage(null), (url: null, contain: false));
    });
  });

  group('formatCardVariant (formatVariantLabel)', () {
    test('normal prints show nothing', () {
      expect(formatCardVariant('normal'), isNull);
      expect(formatCardVariant(null), isNull);
      expect(formatCardVariant(''), isNull);
    });

    test('printings keep their name, patterns read as Holo', () {
      expect(formatCardVariant('1st-edition'), '1st Edition');
      expect(formatCardVariant('reverse holo'), 'Holo Reverse Holo');
      expect(formatCardVariant('pokeball'), 'Holo Pokeball');
    });
  });
}
