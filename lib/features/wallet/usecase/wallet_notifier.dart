import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/models/wallet_models.dart';
import '../repository/wallet_repository.dart';

final walletRepositoryProvider = Provider(
  (ref) => WalletRepository(ref.read(supabaseClientProvider)),
);

/// Both follow the session: a signed-out wallet is empty, and signing in
/// refetches rather than showing the previous account's figures.
final walletBalanceProvider = FutureProvider<int>((ref) {
  if (ref.watch(authProvider).valueOrNull == null) return Future.value(0);
  return ref.read(walletRepositoryProvider).fetchBalance();
});

final walletActivityProvider = FutureProvider<List<WalletActivity>>((ref) {
  if (ref.watch(authProvider).valueOrNull == null) {
    return Future.value(const <WalletActivity>[]);
  }
  return ref.read(walletRepositoryProvider).fetchActivity();
});
