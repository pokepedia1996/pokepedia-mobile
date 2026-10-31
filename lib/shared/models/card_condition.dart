/// Full grading/condition vocabulary from `listings_condition_check` /
/// `price_history_condition_check` in
/// `supabase/migrations/00000000000000_baseline.sql`.
enum CardCondition {
  nm,
  lp,
  mp,
  hp,

  /// Damaged: collection-only. Listings and drafts take no DMG grade
  /// (`listings_condition_check`), so it is never offered when selling;
  /// price_history carries it for imported sales.
  dmg,
  psa10,
  psa9,
  psa8,
  psa7,
  psa6,
  psa5,
  psa4,
  psa3,
  psa2,
  psa1,

  /// The old "PSA ≤8" bucket, from before exact grades below 9. No longer
  /// offered anywhere; kept so a row still carrying it reads as itself
  /// rather than falling back to NM.
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

/// What a collection row can be filed under — `collection_cards_condition_check`:
/// the raw grades plus [CardCondition.dmg].
const collectionConditions = [...rawConditions, CardCondition.dmg];

/// Company headings in `CONDITION_COMPANIES` order (`lib/orders/conditions.ts`),
/// used to group condition pills. [CardCondition]'s declaration order matches
/// each company's grade order, so sorting by `values.indexOf` reproduces the
/// web's pill order within a group.
const conditionCompanies = ['Raw', 'PSA', 'BGS', 'CGC', 'EGS'];

/// `GRADED_PHOTO_REQUIRED_MESSAGE` in `lib/seller/listing-drafts.ts`.
const gradedPhotoRequiredMessage = 'Foto wajib untuk kartu graded (slab).';

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
      case CardCondition.dmg:
        return 'DMG';
      case CardCondition.psa10:
        return 'PSA10';
      case CardCondition.psa9:
        return 'PSA9';
      case CardCondition.psa8:
        return 'PSA8';
      case CardCondition.psa7:
        return 'PSA7';
      case CardCondition.psa6:
        return 'PSA6';
      case CardCondition.psa5:
        return 'PSA5';
      case CardCondition.psa4:
        return 'PSA4';
      case CardCondition.psa3:
        return 'PSA3';
      case CardCondition.psa2:
        return 'PSA2';
      case CardCondition.psa1:
        return 'PSA1';
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

  /// A grade kept only so existing rows still read — never offered in a
  /// picker or filter.
  bool get isLegacy => this == CardCondition.psaLow;

  /// A grade a collection holds but a listing never does — kept out of every
  /// selling picker.
  bool get isCollectionOnly => this == CardCondition.dmg;

  /// Mirrors `isGradedCondition` in `lib/orders/conditions.ts` (SQL twin
  /// `is_graded_condition`): anything outside NM/LP/MP/HP is a slab.
  bool get isGraded => !isRaw;

  /// Mirrors `listingRequiresPhoto` in `lib/seller/listing-drafts.ts` — only
  /// graded slabs need a photo, whatever the price.
  bool get requiresListingPhoto => isGraded;

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
      case CardCondition.dmg:
        return 'DMG';
      case CardCondition.psa10:
        return 'PSA 10';
      case CardCondition.psa9:
        return 'PSA 9';
      case CardCondition.psa8:
        return 'PSA 8';
      case CardCondition.psa7:
        return 'PSA 7';
      case CardCondition.psa6:
        return 'PSA 6';
      case CardCondition.psa5:
        return 'PSA 5';
      case CardCondition.psa4:
        return 'PSA 4';
      case CardCondition.psa3:
        return 'PSA 3';
      case CardCondition.psa2:
        return 'PSA 2';
      case CardCondition.psa1:
        return 'PSA 1';
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
      case CardCondition.dmg:
        return 'Damaged';
      default:
        return short;
    }
  }

  /// The grade on its own, as shown under a company heading in the condition
  /// picker — mirrors `gradeLabel` in `lib/orders/conditions.ts`, where "PSA 10"
  /// renders as just "10" beneath the "PSA" column.
  String get gradeLabel {
    switch (this) {
      case CardCondition.nm:
      case CardCondition.lp:
      case CardCondition.mp:
      case CardCondition.hp:
      case CardCondition.dmg:
        return short;
      case CardCondition.psa10:
      case CardCondition.cgc10:
      case CardCondition.egs10:
        return '10';
      case CardCondition.psa9:
      case CardCondition.bgs9:
      case CardCondition.cgc9:
      case CardCondition.egs9:
        return '9';
      case CardCondition.psa8:
        return '8';
      case CardCondition.psa7:
        return '7';
      case CardCondition.psa6:
        return '6';
      case CardCondition.psa5:
        return '5';
      case CardCondition.psa4:
        return '4';
      case CardCondition.psa3:
        return '3';
      case CardCondition.psa2:
        return '2';
      case CardCondition.psa1:
        return '1';
      case CardCondition.psaLow:
      case CardCondition.bgsLow:
      case CardCondition.cgcLow:
      case CardCondition.egsLow:
        return '≤8';
      case CardCondition.bgsBl10:
        return 'Black 10';
      case CardCondition.bgsGd10:
        return 'Gold 10';
      case CardCondition.bgs95:
      case CardCondition.cgc95:
      case CardCondition.egs95:
        return '9.5';
      case CardCondition.cgcPr10:
        return 'Pristine 10';
    }
  }

  /// Company heading this condition groups under — [gradingCompany] with raw
  /// conditions folded into "Raw", matching `CONDITION_COMPANIES`' labels.
  String get companyLabel => gradingCompany ?? 'Raw';

  /// Grading company for graded conditions, null for raw.
  String? get gradingCompany {
    final r = raw;
    if (r.startsWith('PSA')) return 'PSA';
    if (r.startsWith('BGS')) return 'BGS';
    if (r.startsWith('CGC')) return 'CGC';
    if (r.startsWith('EGS')) return 'EGS';
    return null;
  }

  static CardCondition fromRaw(String raw) => CardCondition.values.firstWhere(
    (c) => c.raw == raw,
    orElse: () => CardCondition.nm,
  );
}
