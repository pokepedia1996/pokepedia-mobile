/// Full grading/condition vocabulary from `listings_condition_check` /
/// `price_history_condition_check` in
/// `supabase/migrations/00000000000000_baseline.sql`.
enum CardCondition {
  nm,
  lp,
  mp,
  hp,
  psa10,
  psa9,
  psaLow,
  bgsBl10,
  bgsGd10,
  bgs95,
  bgs9,
  bgsLow,
  cgcPr10,
  cgc10,
  cgc95,
  cgc9,
  cgcLow,
  egs10,
  egs95,
  egs9,
  egsLow,
}

/// The four raw (ungraded) conditions — sellers pick one of these unless
/// the card has been slabbed by a grading company.
const rawConditions = [
  CardCondition.nm,
  CardCondition.lp,
  CardCondition.mp,
  CardCondition.hp,
];

extension CardConditionX on CardCondition {
  /// The exact value stored in `listings.condition` / `price_history.condition`.
  String get raw {
    switch (this) {
      case CardCondition.nm:
        return 'NM';
      case CardCondition.lp:
        return 'LP';
      case CardCondition.mp:
        return 'MP';
      case CardCondition.hp:
        return 'HP';
      case CardCondition.psa10:
        return 'PSA10';
      case CardCondition.psa9:
        return 'PSA9';
      case CardCondition.psaLow:
        return 'PSALOW';
      case CardCondition.bgsBl10:
        return 'BGS_BL10';
      case CardCondition.bgsGd10:
        return 'BGS_GD10';
      case CardCondition.bgs95:
        return 'BGS95';
      case CardCondition.bgs9:
        return 'BGS9';
      case CardCondition.bgsLow:
        return 'BGS_LOW';
      case CardCondition.cgcPr10:
        return 'CGC_PR10';
      case CardCondition.cgc10:
        return 'CGC10';
      case CardCondition.cgc95:
        return 'CGC95';
      case CardCondition.cgc9:
        return 'CGC9';
      case CardCondition.cgcLow:
        return 'CGC_LOW';
      case CardCondition.egs10:
        return 'EGS10';
      case CardCondition.egs95:
        return 'EGS95';
      case CardCondition.egs9:
        return 'EGS9';
      case CardCondition.egsLow:
        return 'EGS_LOW';
    }
  }

  bool get isRaw => rawConditions.contains(this);
  bool get isGraded => !isRaw;

  /// Short badge text, mirrors `conditionShort()` in `lib/orders.ts`.
  String get short {
    switch (this) {
      case CardCondition.nm:
        return 'NM';
      case CardCondition.lp:
        return 'LP';
      case CardCondition.mp:
        return 'MP';
      case CardCondition.hp:
        return 'HP';
      case CardCondition.psa10:
        return 'PSA 10';
      case CardCondition.psa9:
        return 'PSA 9';
      case CardCondition.psaLow:
        return 'PSA ≤8';
      case CardCondition.bgsBl10:
        return 'BGS Black';
      case CardCondition.bgsGd10:
        return 'BGS 10';
      case CardCondition.bgs95:
        return 'BGS 9.5';
      case CardCondition.bgs9:
        return 'BGS 9';
      case CardCondition.bgsLow:
        return 'BGS ≤8.5';
      case CardCondition.cgcPr10:
        return 'CGC Pristine';
      case CardCondition.cgc10:
        return 'CGC 10';
      case CardCondition.cgc95:
        return 'CGC 9.5';
      case CardCondition.cgc9:
        return 'CGC 9';
      case CardCondition.cgcLow:
        return 'CGC ≤8.5';
      case CardCondition.egs10:
        return 'EGS 10';
      case CardCondition.egs95:
        return 'EGS 9.5';
      case CardCondition.egs9:
        return 'EGS 9';
      case CardCondition.egsLow:
        return 'EGS ≤8.5';
    }
  }

  String get label {
    switch (this) {
      case CardCondition.nm:
        return 'Near Mint';
      case CardCondition.lp:
        return 'Lightly Played';
      case CardCondition.mp:
        return 'Moderately Played';
      case CardCondition.hp:
        return 'Heavily Played';
      default:
        return short;
    }
  }

  /// Grading company for graded conditions, null for raw.
  String? get gradingCompany {
    final r = raw;
    if (r.startsWith('PSA')) return 'PSA';
    if (r.startsWith('BGS')) return 'BGS';
    if (r.startsWith('CGC')) return 'CGC';
    if (r.startsWith('EGS')) return 'EGS';
    return null;
  }

  static CardCondition fromRaw(String raw) =>
      CardCondition.values.firstWhere((c) => c.raw == raw, orElse: () => CardCondition.nm);
}
