import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/models/wallet_models.dart';
import '../repository/wallet_repository.dart';

export '../repository/models/wallet_models.dart';

final walletRepositoryProvider = Provider(
  (ref) => WalletRepository(
    ref.read(supabaseClientProvider),
    ref.read(pokepediaApiProvider),
  ),
);

/// All three follow the session: a signed-out wallet is empty, and signing in
/// refetches rather than showing the previous account's figures.
///
/// `autoDispose` on the balance specifically: it is the one figure that money
/// moves out from under, and a cached copy outliving the spend is how the
/// wallet came to read Rp5.000.000 on a wallet that had just paid for an
/// order. Dropping it when nothing is watching means every screen that asks
/// gets the real number instead of relying on each mutation to remember to
/// invalidate. Callers must handle the loading gap that comes with it —
/// `CheckoutState.walletBalance` is nullable for exactly that reason, since
/// treating "not known yet" as zero is what greyed saldo out as insufficient.
final walletBalanceProvider = FutureProvider.autoDispose<int>((ref) {
  if (ref.watch(authProvider).valueOrNull == null) return Future.value(0);
  return ref.read(walletRepositoryProvider).fetchBalance();
});

final walletDestinationsProvider = FutureProvider<List<WithdrawalDestination>>((
  ref,
) {
  if (ref.watch(authProvider).valueOrNull == null) {
    return Future.value(const <WithdrawalDestination>[]);
  }
  return ref.read(walletRepositoryProvider).fetchDestinations();
});

/// The first page of the ledger for one tab. Later pages are appended by the
/// feed itself, which keeps its own list — paging through a provider would
/// refetch every page each time one more arrives.
final walletActivityProvider =
    FutureProvider.family<List<WalletActivity>, WalletBucket>((ref, bucket) {
      if (ref.watch(authProvider).valueOrNull == null) {
        return Future.value(const <WalletActivity>[]);
      }
      return ref
          .read(walletRepositoryProvider)
          .fetchActivity(bucket: bucket, limit: walletActivityPageSize);
    });

/// Web's `ActivityFeed` `pageSize`.
const walletActivityPageSize = 20;

/// The account a withdrawal defaults to — the one marked default, else the
/// first saved. Mirrors how web picks `defaultDest`.
WithdrawalDestination? defaultDestinationOf(
  List<WithdrawalDestination> destinations,
) {
  if (destinations.isEmpty) return null;
  for (final destination in destinations) {
    if (destination.isDefault) return destination;
  }
  return destinations.first;
}
