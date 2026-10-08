import '../../../../core/utils/image_url.dart';

/// Who a campaign is aimed at — `promo_popups.audience`.
enum PromoAudience { all, anon, authed }

/// Image hosts a creative may come from — web's `ALLOWED_IMAGE_ORIGINS` in
/// `lib/utils/index.ts`, minus the project's own Supabase origin, which the
/// repository adds from config so a local stack works too.
const promoImageOrigins = {
  'https://cdn.pokepedia.id',
  'https://cdn2.pokepedia.id',
  'https://tlauakxyrxpwnwgdywum.supabase.co',
  'https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev',
  'https://pub-823786ff78eb4cc8944cdb3f627a1b6a.r2.dev',
  'https://raw.githubusercontent.com',
};

const _relativeBase = 'https://relative.invalid';

/// Ports web's `sanitizeCtaUrl` (`features/promos/api/promos.client.ts`): a
/// same-origin path or an absolute `https` URL, else null.
///
/// A path is resolved against a sentinel origin first, because `//evil.com`
/// and `/\evil.com` both start with `/` yet resolve off-origin.
String? sanitizeCtaUrl(String url) {
  try {
    if (url.startsWith('/')) {
      // Dart keeps a backslash literal where WHATWG parsing reads it as `/`.
      final resolved = Uri.parse(
        _relativeBase,
      ).resolve(url.replaceAll(r'\', '/'));
      if (!_isWebUri(resolved) || resolved.origin != _relativeBase) return null;
      final query = resolved.hasQuery ? '?${resolved.query}' : '';
      final fragment = resolved.hasFragment ? '#${resolved.fragment}' : '';
      return '${resolved.path}$query$fragment';
    }
    final parsed = Uri.parse(url);
    if (parsed.scheme != 'https' || parsed.host.isEmpty) return null;
    return parsed.toString();
  } on FormatException {
    return null;
  }
}

/// `Uri.origin` throws for anything but http(s) with a host.
bool _isWebUri(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;

bool _isAllowedImageUrl(String url, Set<String> allowedOrigins) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || !_isWebUri(parsed)) return false;
  return allowedOrigins.contains(parsed.origin);
}

/// One live campaign — web's `PromoPopup`.
class PromoPopup {
  const PromoPopup({
    required this.id,
    required this.slug,
    required this.title,
    required this.imageUrl,
    required this.imageAlt,
    required this.ctaLabel,
    required this.ctaUrl,
    required this.audience,
    required this.priority,
    required this.cooldownHours,
    required this.maxImpressions,
    required this.maxDismissals,
    required this.startsAt,
    required this.endsAt,
  });

  /// Web's `PromoPopupRowSchema` + `mapRow`: a row that fails validation, has
  /// an unsafe CTA or an image off the allow-list is dropped, not shown.
  static PromoPopup? fromRow(
    Map<String, dynamic> row, {
    Set<String> allowedImageOrigins = promoImageOrigins,
  }) {
    final id = row['id'];
    final slug = row['slug'];
    final title = row['title'];
    final imageUrl = row['image_url'];
    final imageAlt = row['image_alt'];
    final ctaLabel = row['cta_label'];
    final ctaUrl = row['cta_url'];
    final priority = row['priority'];
    final cooldownHours = row['cooldown_hours'];
    final maxImpressions = row['max_impressions'];
    final maxDismissals = row['max_dismissals'];
    if (id is! int || id <= 0) return null;
    if (slug is! String || slug.isEmpty || slug.length > 200) return null;
    if (title is! String || imageUrl is! String || imageAlt is! String) {
      return null;
    }
    if (ctaLabel is! String || ctaUrl is! String) return null;
    if (priority is! num) return null;
    if (cooldownHours is! int || cooldownHours <= 0) return null;
    if (maxImpressions != null &&
        (maxImpressions is! int || maxImpressions <= 0)) {
      return null;
    }
    if (maxDismissals is! int || maxDismissals <= 0) return null;

    final audience = switch (row['audience']) {
      'all' => PromoAudience.all,
      'anon' => PromoAudience.anon,
      'authed' => PromoAudience.authed,
      _ => null,
    };
    if (audience == null) return null;

    final safeCta = sanitizeCtaUrl(ctaUrl);
    if (safeCta == null) return null;

    final proxied = proxyImageUrl(imageUrl) ?? imageUrl;
    if (!_isAllowedImageUrl(proxied, allowedImageOrigins)) return null;

    final startsAt = DateTime.tryParse(row['starts_at'] as String? ?? '');
    final endsAt = DateTime.tryParse(row['ends_at'] as String? ?? '');
    if (startsAt == null || endsAt == null) return null;

    return PromoPopup(
      id: id,
      slug: slug,
      title: title,
      imageUrl: proxied,
      imageAlt: imageAlt,
      ctaLabel: ctaLabel,
      ctaUrl: safeCta,
      audience: audience,
      priority: priority,
      cooldownHours: cooldownHours,
      maxImpressions: maxImpressions as int?,
      maxDismissals: maxDismissals,
      startsAt: startsAt.millisecondsSinceEpoch,
      endsAt: endsAt.millisecondsSinceEpoch,
    );
  }

  final int id;
  final String slug;
  final String title;
  final String imageUrl;
  final String imageAlt;
  final String ctaLabel;

  /// Already sanitized: a `/path` for an in-app target, else an `https` URL.
  final String ctaUrl;
  final PromoAudience audience;
  final num priority;
  final int cooldownHours;
  final int? maxImpressions;
  final int maxDismissals;

  /// Epoch milliseconds, like web's `Date.parse`.
  final int startsAt;
  final int endsAt;

  bool get isInternalTarget => ctaUrl.startsWith('/');
}
