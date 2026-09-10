import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../repository/models/seller_dashboard.dart';
import '../repository/seller_repository.dart';

/// The window the dashboard is showing. Ports the page's `DEFAULT_WINDOW`
/// of 30 days and the switcher above the metric cards.
final sellerWindowProvider = StateProvider<SellerWindow>(
  (ref) => SellerWindow.month,
);

final sellerIdentityProvider = FutureProvider<SellerIdentity>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return const SellerIdentity();
  return ref.read(sellerRepositoryProvider).fetchIdentity();
});

final hasStoreProvider = FutureProvider<bool>((ref) {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return false;
  return ref.read(sellerRepositoryProvider).hasStore();
});

/// The dashboard payload for the selected window.
///
/// The web fetches the 30-day window server-side and refetches through
/// `/api/seller/dashboard?window=N` when the switcher changes; the app calls
/// the same RPC directly with `p_days`, which is both fewer moving parts and
/// the only option available — that route sits behind the edge challenge.
///
/// The rolling summary rows underneath always describe 90 days regardless of
/// the selected window, so they come from a second call, exactly as the page
/// does with its `perf90Res`.
final sellerDashboardProvider = FutureProvider<DashboardPayload?>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return null;

  final window = ref.watch(sellerWindowProvider);
  final repository = ref.read(sellerRepositoryProvider);

  final results = await Future.wait([
    repository.fetchPerformance(window.days),
    repository.fetchPerformance(SellerWindow.quarter.days),
  ]);

  final payload = results[0];
  if (payload == null) return null;

  final quarter = results[1];
  if (quarter == null) return payload;
  return payload.copyWith(
    summary: computeSummary(quarter.performance.dailyGmv),
  );
});
