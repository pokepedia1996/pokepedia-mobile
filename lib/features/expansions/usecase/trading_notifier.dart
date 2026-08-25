import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/models/trading_models.dart';
import '../repository/trading_repository.dart';

final tradingRepositoryProvider = Provider((ref) {
  return TradingRepository(ref.read(supabaseClientProvider));
});

/// Whether the signed-in user may bid/ask at all. Re-read on auth change so
/// verifying a phone (which happens on the web) is picked up after a
/// refresh rather than staying stale for the session.
final tradeEligibilityProvider = FutureProvider<TradeEligibility>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return const TradeEligibility();
  return ref.read(tradingRepositoryProvider).fetchEligibility();
});
