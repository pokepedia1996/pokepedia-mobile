/// Ports `features/card-detail/utils/untradeable-expansions.ts`. Keep in
/// sync with the SQL function `is_card_trading_blocked`, which is the real
/// gate — this list only hides trade controls the server would refuse.
const untradeableExpansionCodes = <String>{'ma6'};

bool isUntradeableExpansion(String? code) {
  if (code == null || code.isEmpty) return false;
  return untradeableExpansionCodes.contains(code.toLowerCase());
}
