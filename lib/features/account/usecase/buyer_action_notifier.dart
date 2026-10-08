import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../notifications/usecase/notifications_notifier.dart';
import '../repository/buyer_action_repository.dart';
import '../repository/models/buyer_action_counts.dart';

export '../repository/models/buyer_action_counts.dart';

final buyerActionRepositoryProvider = Provider(
  (ref) => BuyerActionRepository(ref.read(supabaseClientProvider)),
);

/// Ports web's `BuyerActionProvider`: the counts follow the session, and are
/// refetched whenever the notification list changes (web's
/// `subscribeToNotifications`) and when the app returns to the foreground
/// (web's `focus` / `visibilitychange` listeners).
class BuyerActionNotifier extends AsyncNotifier<BuyerActionCounts> {
  @override
  Future<BuyerActionCounts> build() {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return Future.value(BuyerActionCounts.zero);

    ref.listen(notificationsProvider, (previous, next) {
      // The first load is not news; only a change to a list already shown is.
      if (previous?.hasValue != true || !next.hasValue) return;
      if (identical(previous!.value, next.value)) return;
      refresh();
    });

    final lifecycle = AppLifecycleListener(onResume: refresh);
    ref.onDispose(lifecycle.dispose);

    return ref.read(buyerActionRepositoryProvider).fetchCounts();
  }

  /// Refetches in place. A failure keeps the previous counts — web's
  /// "a stale count is acceptable" — rather than dropping every badge.
  Future<void> refresh() async {
    if (ref.read(authProvider).valueOrNull == null) return;
    try {
      final counts = await ref
          .read(buyerActionRepositoryProvider)
          .fetchCounts();
      state = AsyncData(counts);
    } catch (error) {
      debugPrint('[buyer-actions] get_buyer_action_counts failed: $error');
    }
  }
}

final buyerActionNotifierProvider =
    AsyncNotifierProvider<BuyerActionNotifier, BuyerActionCounts>(
      BuyerActionNotifier.new,
    );

/// The counts for badges, zero until the first fetch lands.
final buyerActionCountsProvider = Provider<BuyerActionCounts>((ref) {
  return ref.watch(buyerActionNotifierProvider).valueOrNull ??
      BuyerActionCounts.zero;
});
