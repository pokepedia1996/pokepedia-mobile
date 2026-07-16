import 'models/wallet_models.dart';

/// Data access for the Wallet feature. Stands in for
/// `public.wallets` / `public.wallet_ledger` in
/// `supabase/migrations/00000000000000_baseline.sql` while this pass only
/// ports the UI with dummy data.
class WalletRepository {
  Future<int> fetchBalance() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return 1250000;
  }

  Future<List<WalletActivity>> fetchActivity() async {
    await Future.delayed(const Duration(milliseconds: 200));
    var balance = 1250000;
    final entries = const [
      (WalletReason.escrowRelease, 'Penjualan Charizard ex #199', 480000),
      (WalletReason.withdrawalDebit, 'Penarikan ke BCA ****1234', 300000),
      (WalletReason.escrowRelease, 'Penjualan Pikachu VMAX #044', 220000),
      (WalletReason.disputePartialRefund, 'Refund sebagian ke pembeli', 15000),
      (WalletReason.buyerCancelRefund, 'Refund pembatalan pembeli', 25000),
    ];
    // wallet_ledger.balance_after walks backwards from the current
    // balance since these entries are listed newest-first.
    final result = <WalletActivity>[];
    for (var i = 0; i < entries.length; i++) {
      final (reason, description, amount) = entries[i];
      result.add(
        WalletActivity(
          id: i + 1,
          reason: reason,
          description: description,
          amount: amount,
          balanceAfter: balance,
          date: switch (i) {
            0 => 'Hari ini, 09:12',
            1 => 'Kemarin, 18:40',
            _ => '$i hari lalu',
          },
        ),
      );
      balance = reason.isCredit ? balance - amount : balance + amount;
    }
    return result;
  }
}
