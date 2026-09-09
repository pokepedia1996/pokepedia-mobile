import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/sent_proposal.dart';

/// The row shape `fetchSentProposals` selects, so the mapping is exercised
/// against what PostgREST actually returns.
Map<String, dynamic> _row({
  List<String>? photos,
  String? message,
  String? seenAt,
  String status = 'pending',
  String? expiresAt = '2026-09-08T09:00:00+00:00',
  String cardImage = 'https://cdn2.pokepedia.id/cards/charizard.webp',
}) => {
  'slug': 'prop-1',
  'status': status,
  'proposed_quantity': 2,
  'proposed_price': 150000,
  'condition': 'NM',
  'message': message,
  'seen_at': seenAt,
  'photos': photos,
  'created_at': '2026-09-01T09:00:00+00:00',
  'expires_at': expiresAt,
  'bid': {
    'id': 5,
    'price': 120000,
    'user_id': 'buyer-1',
    'cards': {
      'id': 7,
      'name_id': 'Charizard ex',
      'expansion_code': 'SV2a',
      'collector_number': '201/165',
      'rarity': 'SAR',
      'category': 'Pokemon',
      'language': 'id',
      'variant': 'normal',
      'image_url': cardImage,
      'details': <String, dynamic>{},
    },
  },
};

void main() {
  test('carries the photos the seller attached', () {
    final p = SentProposalModel.fromRow(
      _row(photos: const ['https://x/a.jpg', 'https://x/b.jpg']),
      buyerUsername: 'ash',
    );
    expect(p.photos, hasLength(2));
    expect(p.photos.first, 'https://x/a.jpg');
  });

  test('a proposal without photos reads as empty, not null', () {
    expect(SentProposalModel.fromRow(_row()).photos, isEmpty);
    expect(SentProposalModel.fromRow(_row(photos: const [])).photos, isEmpty);
  });

  test('drops blank entries rather than rendering broken tiles', () {
    final p = SentProposalModel.fromRow(
      _row(photos: const ['https://x/a.jpg', '']),
    );
    expect(p.photos, ['https://x/a.jpg']);
  });

  test('catalog art as the first photo is stock, not the seller copy', () {
    // `isStockPhoto`: the badge tells a buyer whether they're looking at the
    // real card or the catalogue render.
    const art = 'https://cdn2.pokepedia.id/cards/charizard.webp';
    final stock = SentProposalModel.fromRow(
      _row(photos: const [art, 'https://x/b.jpg'], cardImage: art),
    );
    expect(stock.usesStockPhoto, isTrue);

    final own = SentProposalModel.fromRow(
      _row(photos: const ['https://x/own.jpg'], cardImage: art),
    );
    expect(own.usesStockPhoto, isFalse);
  });

  test('no photos is never reported as stock', () {
    expect(SentProposalModel.fromRow(_row()).usesStockPhoto, isFalse);
  });

  group('seen state', () {
    test('an unopened proposal reports no seen time', () {
      expect(SentProposalModel.fromRow(_row()).seenAt, isNull);
    });

    test('an opened one carries when the buyer looked', () {
      final p = SentProposalModel.fromRow(
        _row(seenAt: '2026-09-02T10:00:00+00:00'),
      );
      expect(p.seenAt, isNotNull);
      expect(p.seenAt!.toUtc().day, 2);
    });
  });

  group('expiry', () {
    test('a pending proposal counts down', () {
      final p = SentProposalModel.fromRow(
        _row(
          expiresAt: DateTime.now()
              .add(const Duration(hours: 5))
              .toIso8601String(),
        ),
      );
      expect(p.remaining, isNotNull);
      expect(p.remaining!.inHours, inInclusiveRange(4, 5));
    });

    test('a lapsed one clamps at zero rather than counting upward', () {
      final p = SentProposalModel.fromRow(
        _row(
          expiresAt: DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        ),
      );
      expect(p.remaining, Duration.zero);
    });

    test('a settled proposal has no clock left to show', () {
      // Web only renders the countdown while pending.
      final p = SentProposalModel.fromRow(_row(status: 'accepted'));
      expect(p.remaining, isNull);
    });
  });
}
