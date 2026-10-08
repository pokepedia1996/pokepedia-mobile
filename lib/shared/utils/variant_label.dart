/// WOTC-era printings name the print run rather than a holo pattern —
/// `PRINTING_VARIANTS` in `pokepedia-web/lib/cards/card-name.ts`.
const _printingVariants = {
  '1st-edition': '1st Edition',
  'shadowless': 'Shadowless',
  'unlimited': 'Unlimited',
};

/// Ports `formatVariantLabel` for the caption `VariantLabel` draws under a
/// card name: null for a normal print, which shows no caption.
///
/// Web appends "Holo" to a printing only when `details.holo` is set; the
/// deck surfaces that use this pass no such flag, so neither does this.
String? formatCardVariant(String? variant) {
  final key = variant?.trim().toLowerCase() ?? '';
  if (key.isEmpty || key == 'normal') return null;
  final printing = _printingVariants[key];
  if (printing != null) return printing;
  final titleCased = variant!
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
  return 'Holo $titleCased';
}
