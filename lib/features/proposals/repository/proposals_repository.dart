import '../../../shared/data/dummy_catalog.dart';
import '../../../shared/models/card_condition.dart';
import 'models/bid_proposal_model.dart';
import 'models/listing_offer_model.dart';

/// Data access for the Proposals/Offers feature. Stands in for the web's
/// `listing_offers` (buyer negotiates a price on an ask listing) and
/// `bid_proposals` (seller offers to fulfil a buyer's WTB bid) Supabase
/// queries while this pass only ports the UI with dummy data.
class ProposalsRepository {
  Future<List<ListingOfferModel>> fetchMyOffers() async {
    await Future.delayed(const Duration(milliseconds: 200));
    final cards = DummyCatalog.allCards.take(4).toList();
    final statuses = OfferStatus.values;
    final now = DateTime(2026, 7, 16);
    return List.generate(cards.length, (i) {
      final card = cards[i];
      final listingPrice = card.marketPrice ?? 30000;
      final currentPrice = listingPrice - 2000 * i;
      return ListingOfferModel(
        slug: 'off-${1000 + i}',
        card: card,
        condition: CardCondition.values[i % rawConditions.length],
        quantity: 1 + (i % 3),
        listingPrice: listingPrice,
        currentPrice: currentPrice,
        lastActor: i.isEven ? OfferActor.buyer : OfferActor.seller,
        status: statuses[i % statuses.length],
        storeName: DummyCatalog.stores[i % DummyCatalog.stores.length].storeName,
        createdAt: now.subtract(Duration(hours: i + 1)),
        expiresAt: now.add(Duration(hours: 24 - i)),
        buyerCounterCount: i,
        sellerCounterCount: i.isEven ? 1 : 0,
      );
    });
  }

  Future<List<BidProposalModel>> fetchReceivedProposals() async {
    await Future.delayed(const Duration(milliseconds: 200));
    final cards = DummyCatalog.allCards.skip(4).take(3).toList();
    final statuses = BidProposalStatus.values;
    final now = DateTime(2026, 7, 16);
    return List.generate(cards.length, (i) {
      return BidProposalModel(
        slug: 'bpr-${1000 + i}',
        card: cards[i],
        condition: CardCondition.values[(i + 2) % rawConditions.length],
        proposedQuantity: 1 + (i % 2),
        sellerStoreName: DummyCatalog.stores[(i + 1) % DummyCatalog.stores.length].storeName,
        status: statuses[(i + 1) % statuses.length],
        createdAt: now.subtract(Duration(hours: i + 2)),
        expiresAt: now.add(Duration(hours: 48 - i * 6)),
        message: i.isEven ? 'Kondisi mulus, siap kirim hari ini.' : null,
      );
    });
  }
}
