import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';

/// `bid_proposals.status` — a seller offering to fulfil a buyer's bid
/// (WTB) listing, mirroring `public.bid_proposals` in
/// `supabase/migrations/00000000000000_baseline.sql`.
enum BidProposalStatus { pending, accepted, rejected, expired, withdrawn }

extension BidProposalStatusX on BidProposalStatus {
  /// `bid_proposals.status`. Unknown values read as pending rather than
  /// throwing — a status the app doesn't know yet is still awaiting someone.
  static BidProposalStatus fromRaw(String? raw) => switch (raw) {
    'accepted' => BidProposalStatus.accepted,
    'rejected' => BidProposalStatus.rejected,
    'expired' => BidProposalStatus.expired,
    'withdrawn' => BidProposalStatus.withdrawn,
    _ => BidProposalStatus.pending,
  };

  String get label {
    switch (this) {
      case BidProposalStatus.pending:
        return 'Menunggu';
      case BidProposalStatus.accepted:
        return 'Diterima';
      case BidProposalStatus.rejected:
        return 'Ditolak';
      case BidProposalStatus.expired:
        return 'Kedaluwarsa';
      case BidProposalStatus.withdrawn:
        return 'Ditarik';
    }
  }
}

class BidProposalModel {
  const BidProposalModel({
    required this.slug,
    required this.card,
    required this.condition,
    required this.proposedQuantity,
    required this.sellerStoreName,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.seenAt,
    this.message,
    this.proposedPrice,
    this.bidPrice,
    this.photos = const [],
  });

  final String slug;
  final CardModel card;
  final CardCondition condition;
  final int proposedQuantity;
  final String sellerStoreName;
  final BidProposalStatus status;

  /// When the bid's owner first opened this proposal. Null is what the
  /// market banner counts as "baru".
  final DateTime? seenAt;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? message;

  /// What the seller is asking for this copy.
  final int? proposedPrice;

  /// What the buyer's own bid offers — the number [proposedPrice] is being
  /// judged against.
  final int? bidPrice;

  /// Photos of the actual copy. A proposal is an offer of one specific card,
  /// and its condition is a word until you can see it.
  final List<String> photos;

  /// Whether the seller is asking more than the bid offers.
  ///
  /// At the bid price the seller has simply taken the offer; above it they
  /// are countering, and the buyer never committed to that number.
  bool get isAboveBid =>
      proposedPrice != null && bidPrice != null && proposedPrice! > bidPrice!;
}
