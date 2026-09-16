import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_provider.dart';
import '../repository/ads_repository.dart';

/// The placement keys the `ads` table is filled against. Web books
/// `card_detail`, `expansion`, `pack_detail` and `search`; this is the app's
/// own slot.
abstract final class AdPlacement {
  static const home = 'home';
}

final adsRepositoryProvider = Provider(
  (ref) => AdsRepository(ref.read(supabaseClientProvider)),
);

/// What is booked for a placement today, in slot order. Empty is the normal
/// case, and means the slot draws nothing at all.
final adsProvider = FutureProvider.family<List<AdModel>, String>((
  ref,
  placement,
) {
  return ref.read(adsRepositoryProvider).fetchByPlacement(placement);
});
