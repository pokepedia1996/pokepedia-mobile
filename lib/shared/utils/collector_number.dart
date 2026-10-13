import '../../features/expansions/repository/expansions_repository.dart'
    show compareNatural;

/// Ports `compareCollectorNumber` from web's `lib/cards/collector-number.ts`.
const _numericGroup = 0;
const _rgbGroup = 1;
const _letterGroup = 2;

// MA6 prints the RGB Mews as R/RGB, G/RGB, B/RGB — they belong with the cards,
// ahead of the energies.
const _rgbPrefixOrder = {'R': 0, 'G': 1, 'B': 2};
final _rgbPattern = RegExp(r'^([RGB])/RGB$', caseSensitive: false);
final _leadingDigit = RegExp(r'^\d');

int? _rgbRank(String collectorNumber) {
  final match = _rgbPattern.firstMatch(collectorNumber.trim());
  return match == null ? null : _rgbPrefixOrder[match.group(1)!.toUpperCase()];
}

int _group(String collectorNumber) {
  if (_leadingDigit.hasMatch(collectorNumber.trim())) return _numericGroup;
  return _rgbRank(collectorNumber) == null ? _letterGroup : _rgbGroup;
}

/// Numbered cards, then the RGB prints in R-G-B order, then lettered energies.
int compareCollectorNumber(String a, String b) {
  final groupA = _group(a);
  final groupB = _group(b);
  if (groupA != groupB) return groupA - groupB;
  if (groupA == _rgbGroup) return _rgbRank(a)! - _rgbRank(b)!;
  return compareNatural(a, b);
}
