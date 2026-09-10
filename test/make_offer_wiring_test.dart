import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/listing_offer_model.dart';
import 'package:pokepedia_mobile/features/proposals/repository/proposals_repository.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

ListingOfferModel _offer({
  String slug = 'offer-1',
  String listingSlug = 'listing-1',
  OfferStatus status = OfferStatus.pending,
}) => ListingOfferModel(
  slug: slug,
  listingSlug: listingSlug,
  card: const CardModel(
    id: 1,
    category: CardCategory.pokemon,
    nameId: 'Pikachu',
    expansionCode: 'SV2a',
    packSlug: 'sv2a',
    collectorNumber: '025/165',
    rarity: 'Rare',
  ),
  condition: CardCondition.nm,
  quantity: 1,
  listingPrice: 100000,
  currentPrice: 80000,
  lastActor: OfferActor.buyer,
  status: status,
  storeName: 'Toko Ash',
  createdAt: DateTime(2026, 8, 1),
  expiresAt: DateTime(2026, 8, 5),
);

void main() {
  group('myOfferOnListingProvider', () {
    test('finds a live offer on the listing being viewed', () async {
      final container = ProviderContainer(
        overrides: [
          myOffersProvider.overrideWith((ref) async => [_offer()]),
        ],
      );
      addTearDown(container.dispose);

      await container.read(myOffersProvider.future);
      expect(
        container.read(myOfferOnListingProvider('listing-1')).valueOrNull?.slug,
        'offer-1',
      );
    });

    test('ignores offers on other listings', () async {
      final container = ProviderContainer(
        overrides: [
          myOffersProvider.overrideWith(
            (ref) async => [_offer(listingSlug: 'somewhere-else')],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(myOffersProvider.future);
      expect(
        container.read(myOfferOnListingProvider('listing-1')).valueOrNull,
        isNull,
      );
    });

    test('an accepted offer still blocks a second one', () async {
      // `submit_offer` answers `offer_already_accepted` until it lapses.
      final container = ProviderContainer(
        overrides: [
          myOffersProvider.overrideWith(
            (ref) async => [_offer(status: OfferStatus.accepted)],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(myOffersProvider.future);
      expect(
        container.read(myOfferOnListingProvider('listing-1')).valueOrNull,
        isNotNull,
      );
    });

    test('a settled offer leaves the buyer free to try again', () async {
      // Rejected, withdrawn and expired are history — the RPC accepts a new
      // offer, so the button must not stay stuck on "already sent".
      for (final status in [
        OfferStatus.rejected,
        OfferStatus.withdrawn,
        OfferStatus.expired,
      ]) {
        final container = ProviderContainer(
          overrides: [
            myOffersProvider.overrideWith(
              (ref) async => [_offer(status: status)],
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(myOffersProvider.future);
        expect(
          container.read(myOfferOnListingProvider('listing-1')).valueOrNull,
          isNull,
          reason: '$status',
        );
      }
    });

    test('an offer with no listing slug never matches', () async {
      // Rows predating the embed carry a blank slug; matching on it would
      // attach someone else's offer to whichever listing is open.
      final container = ProviderContainer(
        overrides: [
          myOffersProvider.overrideWith(
            (ref) async => [_offer(listingSlug: '')],
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(myOffersProvider.future);
      expect(container.read(myOfferOnListingProvider('')).valueOrNull, isNull);
    });
  });

  group('submit_offer error wording', () {
    // Built directly rather than through the provider: `debugMessageFor` is
    // a pure lookup, and reaching for `Supabase.instance` would need the
    // whole SDK initialised to read a string table.
    final repository = ProposalsRepository(
      SupabaseClient('http://localhost:54321', 'anon-key'),
    );

    test('a duplicate offer is named, not left generic', () async {
      // The buyer's move is to open the offer they already have, so the
      // message has to say one exists rather than "coba lagi".
      expect(
        repository.debugMessageFor('offer_already_pending'),
        'Kamu sudah punya penawaran aktif untuk listing ini.',
      );
    });

    test('every submit_offer refusal has buyer-facing copy', () async {
      // These are the codes `submit_offer` can return; an unmapped one
      // surfaces as the generic fallback and tells the buyer nothing.
      const codes = [
        'invalid_quantity',
        'invalid_price',
        'message_too_long',
        'trading_disabled',
        'order_not_found',
        'order_not_available',
        'not_an_ask_order',
        'offers_not_accepted',
        'cannot_offer_on_own_listing',
        'offer_not_below_price',
        'offer_already_pending',
        'offer_already_accepted',
        'insufficient_quantity',
        'phone_not_verified',
        'bidding_banned',
      ];

      for (final code in codes) {
        final message = repository.debugMessageFor(code);
        expect(
          message,
          isNot('Gagal memproses penawaran. Coba lagi.'),
          reason: code,
        );
        expect(message, isNot(contains('_')), reason: code);
      }
    });
  });
}
