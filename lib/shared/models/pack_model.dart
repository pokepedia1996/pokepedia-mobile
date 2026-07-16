/// A Pokemon TCG expansion/set, mirroring `public.expansions` in
/// `supabase/migrations/00000000000000_baseline.sql`.
class PackModel {
  const PackModel({
    required this.slug,
    required this.name,
    required this.mark,
    required this.series,
    required this.releaseDate,
    required this.cardCount,
    this.productType = 'Expansion',
    this.language = 'id',
    this.collectedCount = 0,
  });

  final String slug;
  final String name;
  final String mark;
  final String series;
  final String releaseDate;
  final int cardCount;

  /// `expansions.product_type` — e.g. "Expansion", "Promo", "Special Set".
  final String productType;
  final String language;
  final int collectedCount;

  double get progress => cardCount > 0 ? collectedCount / cardCount : 0;
}

class SeriesGroup {
  const SeriesGroup({required this.series, required this.packs});

  final String series;
  final List<PackModel> packs;

  int get totalPacks => packs.length;
  int get totalCards => packs.fold(0, (sum, p) => sum + p.cardCount);
}
