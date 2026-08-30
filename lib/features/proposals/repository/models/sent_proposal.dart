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
}
