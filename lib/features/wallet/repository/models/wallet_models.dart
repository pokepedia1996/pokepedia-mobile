import '../../../../core/utils/formatters.dart';
import '../../utils/activity_label.dart';

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
    this.counterpartyUsername,
    this.counterpartyCount,
    this.itemNames,
    this.itemCount,
  });

  /// One row of `get_wallet_activity`.
  factory WalletActivity.fromRow(Map<String, dynamic> row) {
    final rawItems = row['item_names'];
    return WalletActivity(
      id: (row['id'] as num).toInt(),
      reason: row['reason'] as String? ?? '',
      amount: (row['amount'] as num?)?.toInt() ?? 0,
      balanceAfter: (row['balance_after'] as num?)?.toInt() ?? 0,
      notes: row['notes'] as String?,
      createdAt: DateTime.tryParse(
        row['created_at'] as String? ?? '',
      )?.toLocal(),
      counterpartyUsername: row['counterparty_username'] as String?,
      counterpartyCount: (row['counterparty_count'] as num?)?.toInt(),
      itemNames: rawItems is List
          ? [
              for (final name in rawItems)
                if (name is String) name,
            ]
          : null,
      itemCount: (row['item_count'] as num?)?.toInt(),
    );
  }

  final int id;

  /// `wallet_ledger.reason`, raw: a reason added server-side after this
  /// build still renders, as web's "Transaksi saldo".
  final String reason;

  /// Signed, as the ledger stores it: the sign is what makes a row money in
  /// or money out, not the reason it carries.
  final int amount;

  /// `wallet_ledger.balance_after`.
  final int balanceAfter;

  /// The ledger's own note; only shown for rows with no counterparty story.
  final String? notes;
  final DateTime? createdAt;

  /// The other side of the money — the seller paid, the seller refunding,
  /// or the buyer whose order released.
  final String? counterpartyUsername;

  /// Sellers in a multi-seller checkout, the named one included.
  final int? counterpartyCount;

  /// The first few card names; [itemCount] is the full count.
  final List<String>? itemNames;
  final int? itemCount;

  bool get isCredit => amount > 0;

  ActivityDescription get description => describeActivity((
    reason: reason,
    notes: notes,
    counterpartyUsername: counterpartyUsername,
    counterpartyCount: counterpartyCount,
    itemNames: itemNames,
    itemCount: itemCount,
  ));

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
