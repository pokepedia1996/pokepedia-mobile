import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';

/// `listing_offers.status` check constraint — a buyer negotiating a price
/// on a seller's ask listing.
enum OfferStatus { pending, accepted, rejected, expired, withdrawn }

extension OfferStatusX on OfferStatus {
  String get label {
    switch (this) {
      case OfferStatus.pending:
        return 'Menunggu';
      case OfferStatus.accepted:
        return 'Diterima';
      case OfferStatus.rejected:
        return 'Ditolak';
      case OfferStatus.expired:
        return 'Kedaluwarsa';
      case OfferStatus.withdrawn:
        return 'Ditarik';
    }
  }
}

/// `listing_offers.last_actor` check constraint.
enum OfferActor { buyer, seller }

/// A price negotiation on an ask listing, mirroring
/// `public.listing_offers` in
/// `supabase/migrations/00000000000000_baseline.sql`.
class ListingOfferModel {
  const ListingOfferModel({
    required this.slug,
    required this.card,
    required this.condition,
    required this.quantity,
    required this.listingPrice,
    required this.currentPrice,
    required this.lastActor,
    required this.status,
    required this.storeName,
    required this.createdAt,
    required this.expiresAt,
    this.buyerCounterCount = 0,
    this.sellerCounterCount = 0,
  });

  final String slug;
  final CardModel card;
  final CardCondition condition;
  final int quantity;
  final int listingPrice;
  final int currentPrice;
  final OfferActor lastActor;
  final OfferStatus status;
  final String storeName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int buyerCounterCount;
  final int sellerCounterCount;

  bool get isCountered => buyerCounterCount + sellerCounterCount > 0;
}
