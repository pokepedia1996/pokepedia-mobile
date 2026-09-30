import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/expansions/utils/untradeable_expansions.dart';

/// This list only hides controls the server would refuse anyway, so it is
/// wrong in a way nothing else catches: leave a released expansion in it and
/// the app quietly refuses trades the marketplace is already making.
void main() {
  test('nothing is blocked, matching the server gate', () {
    // `is_card_trading_blocked` checks against an empty array, so any code
    // here would be the app refusing a trade the database would allow.
    expect(untradeableExpansionCodes, isEmpty);
  });

  test('MA6 — 30th Celebration — trades', () {
    expect(isUntradeableExpansion('MA6'), isFalse);
    expect(isUntradeableExpansion('ma6'), isFalse);
  });

  test('an unknown or missing code is not a block', () {
    expect(isUntradeableExpansion(null), isFalse);
    expect(isUntradeableExpansion(''), isFalse);
    expect(isUntradeableExpansion('sv3'), isFalse);
  });
}
