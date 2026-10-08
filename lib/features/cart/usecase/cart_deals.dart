import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../repository/checkout_gateway.dart';
import '../repository/models/checkout_deal.dart';

/// The buyer's accepted bid proposals still waiting to be paid, shown on the
/// cart page as their own seller groups — the `deals` of `useCartDeals`.
final cartDealsProvider = FutureProvider<List<CheckoutDeal>>((ref) {
  final userId = ref.watch(authProvider.select((a) => a.valueOrNull?.id));
  if (userId == null) return Future.value(const <CheckoutDeal>[]);
  return ref.read(checkoutGatewayProvider).fetchDeals();
});

/// Which of [cartDealsProvider] the buyer is paying with the cart — the
/// `selectedDeals` of `useCartDeals`, every deal ticked to start with.
///
/// Held as exclusions for the reason [CartSelectionNotifier] gives: the deal
/// list reloads after every accept and every checkout, and tracking what was
/// unticked survives that where tracking what was ticked would not.
class CartDealSelectionNotifier extends Notifier<Set<String>> {
  final Set<String> _excluded = {};

  @override
  Set<String> build() {
    final deals = ref.watch(cartDealsProvider).valueOrNull ?? const [];
    _excluded.removeWhere((id) => !deals.any((deal) => deal.externalId == id));
    return {
      for (final deal in deals)
        if (!_excluded.contains(deal.externalId)) deal.externalId,
    };
  }

  void toggle(String externalId) {
    if (_excluded.remove(externalId)) {
      state = {...state, externalId};
      return;
    }
    _excluded.add(externalId);
    state = {...state}..remove(externalId);
  }

  /// "Pilih Semua", which on web covers deals as well as lines.
  void setAll({required bool selected}) {
    final deals = ref.read(cartDealsProvider).valueOrNull ?? const [];
    final ids = {for (final deal in deals) deal.externalId};
    if (selected) {
      _excluded.removeAll(ids);
      state = {...state, ...ids};
    } else {
      _excluded.addAll(ids);
      state = {...state}..removeAll(ids);
    }
  }
}

final cartDealSelectionProvider =
    NotifierProvider<CartDealSelectionNotifier, Set<String>>(
      CartDealSelectionNotifier.new,
    );

/// The ticked deals themselves, newest first as [cartDealsProvider] reads
/// them.
final selectedCartDealsProvider = Provider<List<CheckoutDeal>>((ref) {
  final selected = ref.watch(cartDealSelectionProvider);
  final deals = ref.watch(cartDealsProvider).valueOrNull ?? const [];
  return [
    for (final deal in deals)
      if (selected.contains(deal.externalId)) deal,
  ];
});
