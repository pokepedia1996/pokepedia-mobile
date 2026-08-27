import '../../../../core/utils/formatters.dart';

/// `wallet_ledger.reason` check constraint in
/// `supabase/migrations/00000000000000_baseline.sql`.
enum WalletReason {
  escrowRelease,
  disputeRefundBuyer,
  disputeReleaseSeller,
  disputePartialRefund,
  disputePartialRelease,
  buyerCancelRefund,
  courierCancelRefund,
  withdrawalDebit,
  withdrawalReverse,
  checkoutPayment,
  sellerPartialRefund,
}

extension WalletReasonX on WalletReason {
  /// Credit (money in) vs debit (money out) of the wallet balance.
  bool get isCredit {
    switch (this) {
      case WalletReason.escrowRelease:
      case WalletReason.disputeReleaseSeller:
      case WalletReason.disputePartialRelease:
      case WalletReason.buyerCancelRefund:
      case WalletReason.courierCancelRefund:
      case WalletReason.withdrawalReverse:
      case WalletReason.disputeRefundBuyer:
        return true;
      case WalletReason.disputePartialRefund:
      case WalletReason.withdrawalDebit:
      case WalletReason.checkoutPayment:
      case WalletReason.sellerPartialRefund:
        return false;
    }
  }

  String get label {
    switch (this) {
      case WalletReason.escrowRelease:
        return 'Dana escrow dicairkan';
      case WalletReason.disputeRefundBuyer:
        return 'Refund sengketa';
      case WalletReason.disputeReleaseSeller:
        return 'Dana dicairkan (sengketa selesai)';
      case WalletReason.disputePartialRefund:
        return 'Refund sebagian (sengketa)';
      case WalletReason.disputePartialRelease:
        return 'Pencairan sebagian (sengketa)';
      case WalletReason.buyerCancelRefund:
        return 'Refund pembatalan pembeli';
      case WalletReason.courierCancelRefund:
        return 'Refund pembatalan kurir';
      case WalletReason.withdrawalDebit:
        return 'Penarikan saldo';
      case WalletReason.withdrawalReverse:
        return 'Penarikan dibatalkan';
      case WalletReason.checkoutPayment:
        return 'Pembayaran checkout';
      case WalletReason.sellerPartialRefund:
        return 'Refund sebagian ke pembeli';
    }
  }

  static WalletReason fromRaw(String? raw) => switch (raw) {
    'escrow_release' => WalletReason.escrowRelease,
    'dispute_refund_buyer' => WalletReason.disputeRefundBuyer,
    'dispute_release_seller' => WalletReason.disputeReleaseSeller,
    'dispute_partial_refund' => WalletReason.disputePartialRefund,
    'dispute_partial_release' => WalletReason.disputePartialRelease,
    'buyer_cancel_refund' => WalletReason.buyerCancelRefund,
    'courier_cancel_refund' => WalletReason.courierCancelRefund,
    'withdrawal_debit' => WalletReason.withdrawalDebit,
    'withdrawal_reverse' => WalletReason.withdrawalReverse,
    'seller_partial_refund' => WalletReason.sellerPartialRefund,
    _ => WalletReason.checkoutPayment,
  };
}

class WalletActivity {
  const WalletActivity({
    required this.id,
    required this.reason,
    required this.description,
    required this.amount,
    required this.balanceAfter,
    required this.date,
  });

  /// One row of `get_wallet_activity`.
  factory WalletActivity.fromRow(Map<String, dynamic> row) {
    final reason = WalletReasonX.fromRaw(row['reason'] as String?);
    final occurred = DateTime.tryParse(
      row['created_at'] as String? ?? '',
    )?.toLocal();
    final notes = row['notes'] as String?;
    return WalletActivity(
      id: (row['id'] as num).toInt(),
      reason: reason,
      // The ledger's own note when it has one; the reason reads well enough
      // on its own when it doesn't.
      description: notes != null && notes.isNotEmpty ? notes : reason.label,
      amount: (row['amount'] as num?)?.toInt().abs() ?? 0,
      balanceAfter: (row['balance_after'] as num?)?.toInt() ?? 0,
      date: occurred == null
          ? ''
          : formatRelativeId(occurred, now: DateTime.now()),
    );
  }

  final int id;
  final WalletReason reason;
  final String description;
  final int amount;

  /// `wallet_ledger.balance_after`.
  final int balanceAfter;
  final String date;

  bool get isCredit => reason.isCredit;
}
