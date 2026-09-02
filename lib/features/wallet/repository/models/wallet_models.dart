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
  /// The row's title in the feed — web's `REASON_LABEL` in
  /// `features/wallet/components/activity-feed.tsx`.
  String get label {
    switch (this) {
      case WalletReason.escrowRelease:
        return 'Pencairan saldo pesanan';
      case WalletReason.disputeReleaseSeller:
        return 'Dana dirilis dari laporan';
      case WalletReason.disputePartialRelease:
        return 'Dana parsial dari laporan';
      case WalletReason.buyerCancelRefund:
        return 'Refund pembatalan pesanan';
      case WalletReason.courierCancelRefund:
        return 'Refund kurir membatalkan pengiriman';
      case WalletReason.disputeRefundBuyer:
        return 'Refund hasil laporan';
      case WalletReason.disputePartialRefund:
        return 'Refund parsial hasil laporan';
      case WalletReason.withdrawalDebit:
        return 'Penarikan ke rekening';
      case WalletReason.withdrawalReverse:
        return 'Penarikan dibatalkan';
      // Not in web's map, which would print the raw reason for these two.
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

/// The activity feed's tabs, and `get_wallet_activity`'s `p_bucket` — the
/// RPC does the bucketing, so both clients agree on which rows are earnings,
/// which are refunds and which are withdrawals.
enum WalletBucket { all, penghasilan, refund, penarikan }

extension WalletBucketX on WalletBucket {
  String get raw => name;

  String get labelId {
    switch (this) {
      case WalletBucket.all:
        return 'Semua';
      case WalletBucket.penghasilan:
        return 'Penghasilan';
      case WalletBucket.refund:
        return 'Refund';
      case WalletBucket.penarikan:
        return 'Penarikan';
    }
  }
}

class WalletActivity {
  const WalletActivity({
    required this.id,
    required this.reason,
    required this.amount,
    required this.balanceAfter,
    required this.notes,
    required this.createdAt,
  });

  /// One row of `get_wallet_activity`.
  factory WalletActivity.fromRow(Map<String, dynamic> row) {
    return WalletActivity(
      id: (row['id'] as num).toInt(),
      reason: WalletReasonX.fromRaw(row['reason'] as String?),
      amount: (row['amount'] as num?)?.toInt() ?? 0,
      balanceAfter: (row['balance_after'] as num?)?.toInt() ?? 0,
      notes: row['notes'] as String?,
      createdAt: DateTime.tryParse(
        row['created_at'] as String? ?? '',
      )?.toLocal(),
    );
  }

  final int id;
  final WalletReason reason;

  /// Signed, as the ledger stores it: the sign is what makes a row money in
  /// or money out, not the reason it carries.
  final int amount;

  /// `wallet_ledger.balance_after`.
  final int balanceAfter;

  /// The ledger's own note, shown under the reason when there is one.
  final String? notes;
  final DateTime? createdAt;

  bool get isCredit => amount > 0;

  String get title => reason.label;

  /// "5 Agu 2026, 14:32" — web prints `formatDate`, the same stamp down to
  /// the seconds it adds and a phone has no room for.
  String get dateLabel => createdAt == null
      ? ''
      : '${formatSaleDate(createdAt!)}, ${formatClockId(createdAt!)}';
}

/// A saved payout account — one row of `list_withdrawal_destinations`.
class WithdrawalDestination {
  const WithdrawalDestination({
    required this.id,
    required this.bankCode,
    required this.accountNumber,
    required this.accountHolderName,
    required this.nickname,
    required this.isDefault,
  });

  factory WithdrawalDestination.fromRow(Map<String, dynamic> row) {
    return WithdrawalDestination(
      id: (row['id'] as num).toInt(),
      bankCode: row['bank_code'] as String? ?? '',
      accountNumber: row['account_number'] as String? ?? '',
      accountHolderName: row['account_holder_name'] as String? ?? '',
      nickname: row['nickname'] as String?,
      isDefault: row['is_default'] as bool? ?? false,
    );
  }

  final int id;
  final String bankCode;
  final String accountNumber;
  final String accountHolderName;
  final String? nickname;
  final bool isDefault;

  /// What the row leads with: the nickname the seller gave it, else the bank.
  String get title => (nickname != null && nickname!.isNotEmpty)
      ? nickname!
      : bankLabel(bankCode);

  String get bankName => bankLabel(bankCode);

  String get maskedAccount => maskAccount(accountNumber);
}

/// The payout channels Xendit is wired for — `INDONESIAN_BANKS` in
/// `lib/payments/wallet.ts`. The codes are Xendit's own, and the withdraw
/// route rejects anything outside this list.
const indonesianBanks = <({String code, String name})>[
  (code: 'ID_BCA', name: 'BCA'),
  (code: 'ID_BNI', name: 'BNI'),
  (code: 'ID_BRI', name: 'BRI'),
  (code: 'ID_MANDIRI', name: 'Mandiri'),
  (code: 'ID_PERMATA', name: 'Permata'),
  (code: 'ID_CIMB', name: 'CIMB Niaga'),
  (code: 'ID_BSI', name: 'BSI'),
  (code: 'ID_DANAMON', name: 'Danamon'),
  (code: 'ID_BTPN', name: 'Jenius/BTPN'),
  (code: 'ID_OVO', name: 'OVO'),
  (code: 'ID_DANA', name: 'DANA'),
  (code: 'ID_SHOPEEPAY', name: 'ShopeePay'),
];

String bankLabel(String code) {
  for (final bank in indonesianBanks) {
    if (bank.code == code) return bank.name;
  }
  return code.replaceFirst(RegExp(r'^ID_'), '');
}

/// "•••1234" — enough of the account to recognise, not enough to reuse.
String maskAccount(String number) {
  if (number.length <= 4) return number;
  return '•••${number.substring(number.length - 4)}';
}
