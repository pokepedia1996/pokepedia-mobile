import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';

/// One of the user's own open WTB bids.
///
/// The market banner counts these ("35 bid aktif"), so the Proposal page has
/// to be able to show them — web lists them alongside proposals in its
/// card-grouped feed. Without this the banner points at a page that
/// structurally cannot contain what it just counted.
class MyBidModel {
  const MyBidModel({
    required this.slug,
    required this.card,
    required this.price,
    required this.condition,
    required this.quantity,
    required this.qtyLocked,
    this.createdAt,
    this.expiresAt,
    this.pendingProposals = 0,
    this.totalProposals = 0,
    this.latestProposalAt,
  });

  factory MyBidModel.fromRow(
    Map<String, dynamic> row, {
    int pendingProposals = 0,
    int totalProposals = 0,
    DateTime? latestProposalAt,
  }) {
    return MyBidModel(
      slug: row['slug'] as String? ?? '',
      card: CardModel.fromRow(row['cards'] as Map<String, dynamic>),
      price: (row['price'] as num?)?.toInt() ?? 0,
      condition: CardConditionX.fromRaw(row['condition'] as String? ?? 'NM'),
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      qtyLocked: (row['qty_locked'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(
        row['created_at'] as String? ?? '',
      )?.toLocal(),
      expiresAt: DateTime.tryParse(
        row['expires_at'] as String? ?? '',
      )?.toLocal(),
      pendingProposals: pendingProposals,
      totalProposals: totalProposals,
      latestProposalAt: latestProposalAt,
    );
  }

  final String slug;
  final CardModel card;

  /// What the buyer is offering, per card.
  final int price;
  final CardCondition condition;
  final int quantity;

  /// Held by a seller's accepted proposal, so not still open to offers.
  final int qtyLocked;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  /// Proposals awaiting this buyer's answer — the reason to open the bid.
  final int pendingProposals;

  /// Every proposal ever made on this bid, settled ones included.
  final int totalProposals;

  /// When the most recent proposal landed. Orders the card feed, so a bid
  /// that just got an offer rises above an older one.
  final DateTime? latestProposalAt;

  int get available => (quantity - qtyLocked).clamp(0, quantity);
  int get totalValue => price * quantity;

  bool get isExpired {
    final expiresAt = this.expiresAt;
    return expiresAt != null && expiresAt.isBefore(DateTime.now());
  }
}
