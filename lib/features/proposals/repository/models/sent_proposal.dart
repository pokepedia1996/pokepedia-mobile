import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';
import 'bid_proposal_model.dart';

/// A proposal this user sent **as a seller** against someone else's WTB bid.
///
/// The mirror of [BidProposalModel], which is the same table read from the
/// buyer's side. Kept separate because the two rows answer different
/// questions: a received proposal is "who is offering me this card", a sent
/// one is "what did I offer, and did they take it".
class SentProposalModel {
  const SentProposalModel({
    required this.slug,
    required this.card,
    required this.condition,
    required this.proposedQuantity,
    required this.status,
    required this.bidPrice,
    this.proposedPrice,
    this.buyerUsername,
    this.createdAt,
    this.expiresAt,
    this.message,
    this.seenAt,
    this.photos = const [],
  });

  factory SentProposalModel.fromRow(
    Map<String, dynamic> row, {
    String? buyerUsername,
  }) {
    final bid = row['bid'] as Map<String, dynamic>;
    return SentProposalModel(
      slug: row['slug'] as String? ?? '',
      card: CardModel.fromRow(bid['cards'] as Map<String, dynamic>),
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      proposedQuantity: (row['proposed_quantity'] as num?)?.toInt() ?? 1,
      status: BidProposalStatusX.fromRaw(row['status'] as String?),
      bidPrice: (bid['price'] as num?)?.toInt() ?? 0,
      proposedPrice: (row['proposed_price'] as num?)?.toInt(),
      buyerUsername: buyerUsername,
      createdAt: DateTime.tryParse(
        row['created_at'] as String? ?? '',
      )?.toLocal(),
      expiresAt: DateTime.tryParse(
        row['expires_at'] as String? ?? '',
      )?.toLocal(),
      message: row['message'] as String?,
      seenAt: DateTime.tryParse(row['seen_at'] as String? ?? '')?.toLocal(),
      photos: [
        for (final url in (row['photos'] as List? ?? const []))
          if (url is String && url.isNotEmpty) url,
      ],
    );
  }

  final String slug;
  final CardModel card;
  final CardCondition condition;
  final int proposedQuantity;
  final BidProposalStatus status;

  /// What the buyer's bid offers per card — the number the proposal is
  /// negotiating against.
  final int bidPrice;

  /// What this seller asked for instead. Null means they accepted the bid
  /// price as it stands.
  final int? proposedPrice;

  final String? buyerUsername;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String? message;

  /// `bid_proposals.seen_at` — when the buyer first opened it. Null means
  /// they haven't, which the row says out loud so a seller isn't left
  /// wondering whether silence means refusal.
  final DateTime? seenAt;

  /// `bid_proposals.photos` — what the seller attached to prove the card
  /// they're offering. Required above Rp100.000, so most rows have them.
  final List<String> photos;

  /// Ports `isStockPhoto`: the first photo being the catalog art means
  /// the seller sent stock imagery rather than their own copy.
  bool get usesStockPhoto => photos.isNotEmpty && photos.first == card.imageUrl;

  /// The price actually being proposed, falling back to the bid's own.
  int get effectivePrice => proposedPrice ?? bidPrice;

  /// Web strikes through the bid price only when the seller asked for more.
  bool get isCounterOffer => proposedPrice != null && proposedPrice! > bidPrice;

  /// Only a settled proposal can be cleared from the list —
  /// `dismiss_bid_proposal` refuses while it is still pending.
  bool get isDismissible => status != BidProposalStatus.pending;

  bool get isExpiringSoon {
    final expiresAt = this.expiresAt;
    return status == BidProposalStatus.pending && expiresAt != null;
  }

  /// How long the buyer still has to answer, or null when the proposal has
  /// settled and the clock no longer matters. Clamped at zero so a lapsed
  /// proposal never counts upward.
  Duration? get remaining {
    final expiresAt = this.expiresAt;
    if (status != BidProposalStatus.pending || expiresAt == null) return null;
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}
