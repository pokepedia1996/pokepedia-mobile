import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../notifications/repository/models/notification_model.dart';
import '../../notifications/usecase/notifications_notifier.dart';
import '../repository/models/referral_models.dart';
import '../repository/referral_repository.dart';

export '../repository/models/referral_models.dart';

final referralRepositoryProvider = Provider(
  (ref) => ReferralRepository(ref.read(supabaseClientProvider)),
);

/// First page of the dashboard for one filter. Later friend pages are
/// appended by the list itself, like the wallet feed.
///
/// The Akun nav dot keeps this alive for the whole session, so it refetches
/// on its own when the app returns to the foreground and when a referral
/// notification arrives (a friend joined, a pack is ready) — otherwise the
/// "N pack" pill and the dot lag until a manual refresh.
final referralDashboardProvider = FutureProvider.autoDispose
    .family<ReferralDashboard, ReferralFilter>((ref, filter) {
      if (ref.watch(authProvider).valueOrNull == null) {
        return Future.value(ReferralDashboard.empty);
      }
      final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
      ref.onDispose(lifecycle.dispose);
      ref.listen(notificationsProvider, (previous, next) {
        final before = previous?.valueOrNull;
        final after = next.valueOrNull;
        if (before == null || after == null) return;
        final seen = {for (final n in before) n.id};
        if (after.any((n) => !seen.contains(n.id) && _isReferral(n.type))) {
          ref.invalidateSelf();
        }
      });
      return ref
          .read(referralRepositoryProvider)
          .fetchDashboard(filter: filter);
    });

/// Spendable Koin. autoDispose for the same reason as `walletBalanceProvider`:
/// checkout and pack opening move it.
final koinBalanceProvider = FutureProvider.autoDispose<KoinBalance>((ref) {
  if (ref.watch(authProvider).valueOrNull == null) {
    return Future.value(KoinBalance.zero);
  }
  return ref.read(referralRepositoryProvider).fetchKoinBalance();
});

/// Ready packs for the Akun pill and nav dot; 0 until known or on failure,
/// and 0 while the program is paused.
final referralReadyPackCountProvider = Provider.autoDispose<int>((ref) {
  final dashboard = ref
      .watch(referralDashboardProvider(ReferralFilter.all))
      .valueOrNull;
  if (dashboard == null || !dashboard.enabled) return 0;
  return dashboard.readyPacks.length;
});

final referralOddsProvider = FutureProvider.autoDispose<List<ReferralTier>>(
  (ref) => ref.read(referralRepositoryProvider).fetchOdds(),
);

/// First page of the Koin ledger; later pages are appended by the card.
final koinHistoryProvider = FutureProvider.autoDispose<KoinHistoryPage>((ref) {
  if (ref.watch(authProvider).valueOrNull == null) {
    return Future.value(const KoinHistoryPage());
  }
  return ref.read(referralRepositoryProvider).fetchKoinHistory();
});

bool _isReferral(NotificationType type) =>
    type == NotificationType.referralJoined ||
    type == NotificationType.referralPackReady;
