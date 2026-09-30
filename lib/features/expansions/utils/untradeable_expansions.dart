/// Ports `features/card-detail/utils/untradeable-expansions.ts`. Keep in
/// sync with the SQL function `is_card_trading_blocked`, which is the real
/// gate — this list only hides trade controls the server would refuse.
///
/// Empty, and a pre-release expansion is the only thing that ever belongs in
/// it. MA6 ("30th Celebration") sat here after the server had already
/// released it — `20260915131913_release_ma6_unlock_trading` emptied the SQL
/// gate and web's list, and this copy was missed. The app went on hiding
/// every buy, sell and bid control for a set the marketplace was trading,
/// which is the failure mode of keeping a list in three places.
const untradeableExpansionCodes = <String>{};

bool isUntradeableExpansion(String? code) {
  if (code == null || code.isEmpty) return false;
  return untradeableExpansionCodes.contains(code.toLowerCase());
}
