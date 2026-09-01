import '../../../../core/utils/image_url.dart';
import '../../../../shared/models/card_model.dart';

/// Ports `features/scanner/schemas/scanner-requests.ts`.
///
/// The recognition pipeline itself lives entirely on the server — a fine-tuned
/// CLIP tower plus a vector index, behind `/api/scan` (`features/scanner/
/// server/scan.server.ts` → the Python embedder in `services/scanner`). The
/// app's job is to hand that endpoint a tight, correctly-shaped card crop and
/// render what comes back, so what's ported here is the *contract*: the row
/// shape, the calibrated confidence thresholds, and the two derived predicates
/// the web recomputes client-side rather than trusting the server's own flag.

/// Pokemon card aspect (63mm x 88mm, width/height).
///
/// The single most important constant in the capture path: the embedder
/// compares against catalog renders at this exact shape, so a crop that
/// doesn't match it hands CLIP a stretched card and quietly costs accuracy.
/// Mirrors `CARD_ASPECT` on the web, which in turn mirrors the Python
/// `build_corner_dataset.py` / `strip_crop.py` scripts.
const cardAspect = 0.7159;

/// Distance is `1 - cosine_similarity` from the fine-tuned CLIP tower, so 0 is
/// an exact match. Per the web's own calibration note this is a loose floor
/// that rejects "doesn't look like any known card" rather than the main
/// decision — [scanConfidentMargin] is what actually discriminates.
///
/// Mirrored in `services/scanner/embedder/embedder.py` — change all three.
const scanMaxDistance = 0.35;

/// Gap between the leader and the runner-up needed to call a match confident.
///
/// Calibrated on the web against real percentiles: correct top-1 margin
/// p50=0.007/p75=0.028, wrong top-1 margin p50=0.003/p90=0.016. 0.02 sits in
/// the gap, deliberately biased toward *not* claiming confidence when unsure,
/// since a confidently wrong answer is the worse failure.
const scanConfidentMargin = 0.02;

/// A candidate within this much of the leader is a real alternate rather than
/// noise that cleared [scanMaxDistance] by chance — what the variant strip
/// offers the user to cycle through.
const scanAlternateMaxGap = 0.05;

/// Laplacian-variance floor below which a capture is treated as too blurry to
/// trust an *unconfident* match from. Never overrides a confident one: that
/// already cleared the server's calibrated gate, which is a far stronger
/// signal than this uncalibrated per-device heuristic.
const captureMinSharpness = 2000.0;

/// A catalog row as the scanner needs it — the `SCAN_CARD_COLUMNS` select
/// list, not the full `cards` row [CardModel] decodes.
///
/// Deliberately its own model rather than a reuse of [CardModel]: `/api/scan`
/// returns only these nine columns, so decoding into [CardModel] would mean
/// inventing defaults for `category`, `rarity` and `details` that the scanner
/// never has and never displays.
class ScanCard {
  const ScanCard({
    required this.id,
    this.nameId,
    this.imageUrl,
    this.expansionCode,
    this.collectorNumber,
    this.language,
    this.variant = 'normal',
    this.baseNameId,
    this.artworkGroupId,
  });

  final int id;
  final String? nameId;

  /// CDN-resolved, same as every other card image in the app.
  final String? imageUrl;
  final String? expansionCode;
  final String? collectorNumber;
  final CardLanguage? language;
  final String variant;

  /// Name with the `[...]` bracket suffix stripped.
  final String? baseNameId;

  /// Precomputed same-artwork cluster id (`build_artwork_groups.py`). Cards
  /// sharing this show the same illustration across sets/finishes, which is
  /// what makes an ambiguous top-2 an acceptable reprint tie rather than a
  /// real miss — see [isConfidentMatch].
  final int? artworkGroupId;

  /// Display name, falling back to an em dash the way the web's sheets do.
  String get displayName =>
      (nameId == null || nameId!.isEmpty) ? '—' : nameId!;

  /// `SVK 4/102`-style printing label — web's `printingLabel`.
  String get printingLabel {
    final parts = [
      if (expansionCode != null && expansionCode!.isNotEmpty) expansionCode!,
      if (collectorNumber != null && collectorNumber!.isNotEmpty)
        collectorNumber!,
    ];
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  /// Human label for a non-`normal` finish, or null when there's nothing worth
  /// showing — web's `variantLabel`.
  String? get variantLabel {
    if (variant.isEmpty || variant == 'normal') return null;
    return variant
        .split(RegExp(r'[_\s]+'))
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  /// A physical printing — the catalog's natural key minus `variant`. Every
  /// finish of one printing shares this, so it's what tells "a different card"
  /// apart from "the same card in a different finish". Ports `printingKey`.
  String get printingKey =>
      '${expansionCode ?? ''}|${collectorNumber ?? ''}|${language?.raw ?? ''}';

  factory ScanCard.fromJson(Map<String, dynamic> json) {
    final rawLanguage = json['language'] as String?;
    return ScanCard(
      id: (json['id'] as num).toInt(),
      nameId: json['name_id'] as String?,
      imageUrl: proxyImageUrl(json['image_url'] as String?),
      expansionCode: json['expansion_code'] as String?,
      collectorNumber: json['collector_number'] as String?,
      // Null rather than defaulted to `id`: an unknown language here would
      // silently mislabel the print, and the badge is better off absent.
      language: rawLanguage == null
          ? null
          : CardLanguageX.fromRaw(rawLanguage),
      variant: json['variant'] as String? ?? 'normal',
      baseNameId: json['base_name_id'] as String?,
      artworkGroupId: (json['artwork_group_id'] as num?)?.toInt(),
    );
  }

  /// Round-trips through [fromJson] — used to persist a scan session across
  /// app restarts. Keys match the wire format so the two stay in step.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name_id': nameId,
    'image_url': imageUrl,
    'expansion_code': expansionCode,
    'collector_number': collectorNumber,
    'language': language?.raw,
    'variant': variant,
    'base_name_id': baseNameId,
    'artwork_group_id': artworkGroupId,
  };
}

/// One ranked candidate — a catalog row plus its embedding distance.
class ScanMatch {
  const ScanMatch({required this.card, required this.distance});

  final ScanCard card;

  /// `1 - cosine_similarity`; ascending, so `matches.first` is the leader.
  final double distance;

  factory ScanMatch.fromJson(Map<String, dynamic> json) => ScanMatch(
    card: ScanCard.fromJson(json['card'] as Map<String, dynamic>),
    distance: (json['distance'] as num).toDouble(),
  );
}

/// A successful `/api/scan` response.
class ScanResponse {
  const ScanResponse({
    required this.matches,
    required this.variants,
    required this.confident,
    this.logId,
  });

  /// Ranked best-first, already deduped per printing and gap-filtered server
  /// side. Empty means nothing cleared [scanMaxDistance] — a genuine "not
  /// recognized", not an error.
  final List<ScanMatch> matches;

  /// Every printing sharing `matches.first`'s artwork, holo-ranked — the pool
  /// the variant strip cycles through.
  final List<ScanCard> variants;

  /// The server's own verdict. Kept for logging, but the UI reads
  /// [isConfidentMatch] over `matches` instead, matching how the web never
  /// trusts a server-computed confidence value directly.
  final bool confident;

  /// This scan's `recognition_logs` row, so a later correction can be
  /// attributed to it via `/api/scan/confirm`.
  final int? logId;

  factory ScanResponse.fromJson(Map<String, dynamic> json) {
    final matches = (json['matches'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ScanMatch.fromJson)
        .toList();
    final variants = (json['variants'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ScanCard.fromJson)
        .toList();
    return ScanResponse(
      matches: matches,
      variants: variants,
      confident: json['confident'] as bool? ?? false,
      logId: (json['logId'] as num?)?.toInt(),
    );
  }
}

/// Whether the top match can be shown without asking the user to confirm.
///
/// Ports `isConfidentMatch`. Recomputed here from the returned distances
/// rather than reading [ScanResponse.confident], mirroring the web.
///
/// The `artworkGroupId` clause is the subtle half: the fine-tune reliably
/// tells different *illustrations* apart, but a same-artwork reprint can
/// legitimately tie on distance, since the only difference between those rows
/// is printed text a coarse image embedding was never going to resolve.
/// Showing any one of that group is still correct at the artwork level, and
/// the variant strip lets the user pick the exact printing from there. This
/// relaxes nothing when close candidates span *different* artwork groups —
/// that's a real miss (wrong card entirely), not an ambiguous reprint.
bool isConfidentMatch(List<ScanMatch> matches) {
  if (matches.isEmpty) return false;
  final top = matches.first;
  if (top.distance > scanMaxDistance) return false;
  if (matches.length < 2) return true;
  if (matches[1].distance - top.distance >= scanConfidentMargin) return true;

  final topGroup = top.card.artworkGroupId;
  if (topGroup == null) return false;
  final closeRivals = matches
      .skip(1)
      .where((m) => m.distance - top.distance <= scanAlternateMaxGap)
      .toList();
  return closeRivals.isNotEmpty &&
      closeRivals.every((m) => m.card.artworkGroupId == topGroup);
}
