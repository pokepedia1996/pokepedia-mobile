import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';
import 'bid_proposal_model.dart';

/// Stands in for the card of a sent proposal whose bid the seller can no
/// longer read: `listings` RLS only shows another user's bid while it is
/// open, and `bid_proposals` carries no `card_id` of its own. Every such
/// proposal folds into this one group rather than vanishing from the list.
const unavailableProposalCard = CardModel(
  id: 0,
  category: CardCategory.pokemon,
  nameId: 'Kartu tidak tersedia',
  expansionCode: '',
  packSlug: '',
  collectorNumber: '',
  rarity: null,
);

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

  /// Maps a `bid_proposals` row embedding `bid` (the buyer's listing) and
  /// `match` (the `order_items` row an accepted proposal produced).
  ///
  /// Either embed may be null. Web reads this list with a service client so
  /// the bid is always there; the app reads it as the seller, who loses
  /// sight of the bid once it closes. The match is visible to both parties
  /// for good, so an accepted proposal still recovers its card and buyer
  /// from it; anything else falls back to [unavailableProposalCard].
  factory SentProposalModel.fromRow(
    Map<String, dynamic> row, {
    String? buyerUsername,
  }) {
    final bid = row['bid'] as Map<String, dynamic>?;
    final match = row['match'] as Map<String, dynamic>?;
    final cardRow = (bid?['cards'] ?? match?['card']) as Map<String, dynamic>?;
    return SentProposalModel(
      slug: row['slug'] as String? ?? '',
      card: cardRow == null
          ? unavailableProposalCard
          : CardModel.fromRow(cardRow),
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      proposedQuantity: (row['proposed_quantity'] as num?)?.toInt() ?? 1,
      status: BidProposalStatusX.fromRaw(row['status'] as String?),
      bidPrice: (bid?['price'] as num?)?.toInt(),
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

  /// Whose bid [row] answers: the bid's owner while it is readable, the
  /// match's buyer once it isn't.
  static String? buyerIdOf(Map<String, dynamic> row) {
    final bid = row['bid'] as Map<String, dynamic>?;
    final match = row['match'] as Map<String, dynamic>?;
    return (bid?['user_id'] ?? match?['bid_user_id']) as String?;
  }

  final String slug;
  final CardModel card;
  final CardCondition condition;
  final int proposedQuantity;
  final BidProposalStatus status;

  /// What the buyer's bid offers per card — the number the proposal is
  /// negotiating against. Null once the bid is out of the seller's sight.
  final int? bidPrice;

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
  /// they're offering. Required for graded conditions.
  final List<String> photos;

  /// Ports `isStockPhoto`: the first photo being the catalog art means
  /// the seller sent stock imagery rather than their own copy.
  bool get usesStockPhoto => photos.isNotEmpty && photos.first == card.imageUrl;

  /// Whether [card] is the real card rather than [unavailableProposalCard].
  bool get hasCard => card.id != unavailableProposalCard.id;

  /// The price actually being proposed, falling back to the bid's own.
  /// Null when neither is known.
  int? get effectivePrice => proposedPrice ?? bidPrice;

  /// Web strikes through the bid price only when the seller asked for more.
  bool get isCounterOffer {
    final proposed = proposedPrice;
    final bid = bidPrice;
    return proposed != null && bid != null && proposed > bid;
  }

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
