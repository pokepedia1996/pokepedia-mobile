import '../../core/utils/image_url.dart';

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
    this.image,
    this.setSymbolUrl,
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

  /// CDN-resolved `expansions.pack_image_url` / `set_symbol_url`. Null for
  /// dummy data, in which case UI falls back to a placeholder.
  final String? image;
  final String? setSymbolUrl;

  double get progress => cardCount > 0 ? collectedCount / cardCount : 0;

  /// Normalizes a Supabase embed that may come back as a single object or
  /// a 1-item array, depending on the join shape (`SeriesNestedFlexible`
  /// in `pokepedia-web/lib/schemas/card-data.ts`).
  static Map<String, dynamic>? _flattenEmbed(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) return raw.isEmpty ? null : raw.first as Map<String, dynamic>;
    return raw as Map<String, dynamic>;
  }

  /// Maps an `expansions` row (with an embedded `series` join) as returned
  /// by Supabase, mirroring `mapExpansionToPack` in
  /// `pokepedia-web/lib/data/client.ts`.
  factory PackModel.fromRow(Map<String, dynamic> row) {
    final code = row['code'] as String? ?? '';
    final seriesData = _flattenEmbed(row['series']);
    return PackModel(
      slug: code.toLowerCase(),
      name: row['name_id'] as String? ?? '',
      mark: code,
      series: seriesData?['name_id'] as String? ?? 'Lainnya',
      releaseDate: row['released_at'] as String? ?? '',
      cardCount: row['total_cards'] as int? ?? 0,
      productType: row['product_type'] as String? ?? 'Expansion',
      language: row['language'] as String? ?? 'id',
      image: proxyImageUrl(row['pack_image_url'] as String?),
      setSymbolUrl: proxyImageUrl(row['set_symbol_url'] as String?),
    );
  }
}

class SeriesGroup {
  const SeriesGroup({required this.series, required this.packs});

  final String series;
  final List<PackModel> packs;

  int get totalPacks => packs.length;
  int get totalCards => packs.fold(0, (sum, p) => sum + p.cardCount);
}
