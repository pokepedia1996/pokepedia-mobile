import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/wantlist_model.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/portfolio_repository.dart';

void main() {
  group('WantlistModel.fromRow', () {
    test('maps a lists row with its embedded card count', () {
      final list = WantlistModel.fromRow({
        'id': '3f1b0c9e-6d2a-4f7b-9c11-2a5d8e4f6a01',
        'name': 'Buying List',
        'description': 'Kartu yang mau dibeli',
        'share_code': 'aBcD-eF9h',
        'created_at': '2026-08-01T04:00:00+00:00',
        'updated_at': '2026-08-20T09:30:00+00:00',
        // PostgREST returns an embedded aggregate as a one-element list.
        'list_cards': [
          {'count': 12},
        ],
      });

      expect(list.id, '3f1b0c9e-6d2a-4f7b-9c11-2a5d8e4f6a01');
      expect(list.name, 'Buying List');
      expect(list.description, 'Kartu yang mau dibeli');
      expect(list.shareCode, 'aBcD-eF9h');
      expect(list.cardCount, 12);
      expect(list.createdAt?.year, 2026);
      expect(list.updatedAt?.day, 20);
    });

    test('an empty list has no count row to read', () {
      final list = WantlistModel.fromRow({
        'id': 'abc',
        'name': 'Kosong',
        'share_code': 'aaaa-bbbb',
        'list_cards': <dynamic>[],
      });

      expect(list.cardCount, 0);
      expect(list.description, '');
    });

    test('tolerates a missing description and timestamps', () {
      final list = WantlistModel.fromRow({
        'id': 'abc',
        'name': 'Tanpa deskripsi',
        'description': null,
        'share_code': 'aaaa-bbbb',
        'created_at': null,
      });

      expect(list.description, '');
      expect(list.createdAt, isNull);
      expect(list.cardCount, 0);
    });
  });

  group('generateShareCode', () {
    test('is nine characters hyphenated in the middle', () {
      final code = generateShareCode();
      expect(code, hasLength(10)); // 9 chars + the hyphen
      expect(code[4], '-');
    });

    test('avoids the glyphs that misread when typed by hand', () {
      // The web alphabet deliberately drops I, l, O, 0 and 1.
      for (var i = 0; i < 200; i++) {
        expect(generateShareCode(), isNot(matches(RegExp(r'[IlO01]'))));
      }
    });

    test('does not repeat itself', () {
      final codes = {for (var i = 0; i < 200; i++) generateShareCode()};
      expect(codes, hasLength(200));
    });
  });

  group('list field limits', () {
    test('match the web MAX_NAME_LEN / MAX_DESC_LEN', () {
      expect(listNameMaxLength, 100);
      expect(listDescriptionMaxLength, 500);
    });
  });
}
