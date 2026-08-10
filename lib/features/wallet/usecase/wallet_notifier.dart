import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_provider.dart';
import '../repository/models/wallet_models.dart';
import '../repository/wallet_repository.dart';

final walletRepositoryProvider = Provider(
  (ref) => WalletRepository(ref.read(supabaseClientProvider)),
);

final walletBalanceProvider = FutureProvider<int>((ref) {
  return ref.read(walletRepositoryProvider).fetchBalance();
});

final walletActivityProvider = FutureProvider<List<WalletActivity>>((ref) {
  return ref.read(walletRepositoryProvider).fetchActivity();
});
