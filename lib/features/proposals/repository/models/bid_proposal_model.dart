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
}
