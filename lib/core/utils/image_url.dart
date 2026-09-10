/// Ports `proxyImageUrl` from `pokepedia-web/lib/utils/index.tsx` — swaps
/// the raw R2 dev-domain hosts for their friendly CDN hostnames. Other
/// origins (e.g. Supabase storage) pass through unchanged.
const _r2Domains = <(String origin, String prefix)>[
  (
    'https://pub-61ccf1b9e1ab4037b28e968ea11d9d1f.r2.dev',
    'https://cdn.pokepedia.id',
  ),
  (
    'https://pub-823786ff78eb4cc8944cdb3f627a1b6a.r2.dev',
    'https://cdn2.pokepedia.id',
  ),
];

String? proxyImageUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  for (final (origin, prefix) in _r2Domains) {
    if (url.startsWith(origin)) {
      return url.replaceFirst(origin, prefix);
    }
  }
  return url;
}
