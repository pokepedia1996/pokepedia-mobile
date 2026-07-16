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

  final int id;
  final WalletReason reason;
  final String description;
  final int amount;

  /// `wallet_ledger.balance_after`.
  final int balanceAfter;
  final String date;

  bool get isCredit => reason.isCredit;
}
