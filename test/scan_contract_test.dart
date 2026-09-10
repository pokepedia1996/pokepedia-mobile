import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/repository/models/scan_models.dart';

Map<String, dynamic> _card(int id, {int? artworkGroupId}) => {
  'id': id,
  'name_id': 'Charizard ex',
  'image_url': null,
  'expansion_code': 'SV2a',
  'collector_number': '201/165',
  'language': 'id',
  'variant': 'normal',
  'base_name_id': 'Charizard ex',
  'artwork_group_id': artworkGroupId,
};

void main() {
  group('ScanResponse.confident', () {
    test('is read from the server, never derived from distances', () {
      // The handoff is explicit that the 0.35 / 0.02 / 0.05 thresholds live
      // in the Next.js route and the Python embedder and must change
      // together. A client that recomputed the verdict would be a third copy
      // that drifts silently. These distances would fail a local
      // recomputation — the server said confident, so the client says so.
      final response = ScanResponse.fromJson({
        'confident': true,
        'matches': [
          {'card': _card(1), 'distance': 0.44},
          {'card': _card(2), 'distance': 0.441},
        ],
        'variants': <dynamic>[],
        'logId': 4821,
      });

      expect(response.confident, isTrue);
    });

    test('and the reverse: tight distances stay unconfident if told so', () {
      final response = ScanResponse.fromJson({
        'confident': false,
        'matches': [
          {'card': _card(1), 'distance': 0.01},
          {'card': _card(2), 'distance': 0.30},
        ],
        'variants': <dynamic>[],
      });

      expect(response.confident, isFalse);
    });

    test('a missing flag is treated as unconfident', () {
      // Unconfident shows the user their candidates; assuming confidence
      // from a malformed response would present a guess as an answer.
      final response = ScanResponse.fromJson({
        'matches': [
          {'card': _card(1), 'distance': 0.1},
        ],
        'variants': <dynamic>[],
      });
      expect(response.confident, isFalse);
    });
  });

  group('card passthrough', () {
    test('only id is required; everything else may be absent', () {
      // The response card is a passthrough object — the server adds fields
      // without warning and only `id` is guaranteed.
      final card = ScanCard.fromJson({'id': 99});

      expect(card.id, 99);
      expect(card.nameId, isNull);
      expect(card.displayName, '—');
      expect(card.printingLabel, '—');
      expect(card.variant, 'normal');
    });

    test('unknown extra fields are tolerated, not rejected', () {
      final card = ScanCard.fromJson({
        ..._card(7),
        'some_future_column': 'whatever',
        'another': 42,
      });
      expect(card.id, 7);
    });

    test(
      'an unparseable language leaves the badge off rather than guessing',
      () {
        final card = ScanCard.fromJson({..._card(7), 'language': null});
        expect(card.language, isNull);
      },
    );
  });

  group('empty results', () {
    test('no matches is a real answer, not an error', () {
      final response = ScanResponse.fromJson({
        'ok': true,
        'confident': false,
        'matches': <dynamic>[],
        'variants': <dynamic>[],
      });

      expect(response.matches, isEmpty);
      expect(response.variants, isEmpty);
      expect(response.logId, isNull);
    });
  });

  group('constants that are ours to hold', () {
    test('card aspect matches the trained CARD_ASPECT', () {
      // Shared with the corner model's training data and the warp output;
      // a crop off this ratio hands CLIP a stretched card.
      expect(cardAspect, 0.7159);
    });

    test('the blur floor is mirrored deliberately', () {
      // The one number the handoff says to mirror: web rejects an
      // unconfident match below this Laplacian variance rather than showing
      // a low-quality result.
      expect(captureMinSharpness, 2000.0);
    });
  });
}
