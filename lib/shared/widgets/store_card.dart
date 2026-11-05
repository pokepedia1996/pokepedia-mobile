import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../models/store_model.dart';
import 'reputation_star.dart';
import 'seller_avatar.dart';

/// A directory tile for a seller storefront on the "Toko" tab: logo, then
/// the name with its verified mark, Top Seller ribbon and reputation star,
/// then listings, positive share and city on one line beneath.
class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.store, required this.onTap});

  final StoreModel store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = context.mutedForeground;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SellerAvatar(
                  imageUrl: store.imageUrl,
                  name: store.storeName,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          store.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySemibold(
                            colors.onSurface,
                          ).copyWith(fontSize: 17),
                        ),
                      ),
                      if (store.isVerified) ...[
                        const SizedBox(width: 6),
                        const VerifiedBadge(),
                      ],
                      // Admin-granted (`seller_profiles.top_rated`), so only
                      // the stores picked as top sellers ever carry it.
                      if (store.topRated) ...[
                        const SizedBox(width: 6),
                        const TopSellerBadge(),
                      ],
                      if (store.feedbackScore != null) ...[
                        const SizedBox(width: 6),
                        ReputationStar(score: store.feedbackScore!, size: 13),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Stat(
                  icon: LucideIcons.shoppingBag,
                  label: '${store.activeListingCount} listing',
                ),
                if (store.positivePct != null) ...[
                  const SizedBox(width: 12),
                  _Stat(
                    icon: LucideIcons.thumbsUp,
                    // Web's `toFixed(pct % 1 === 0 ? 0 : 1)`.
                    label:
                        '${store.positivePct! % 1 == 0 ? store.positivePct!.toStringAsFixed(0) : store.positivePct!.toStringAsFixed(1)}%',
                  ),
                ],
                const SizedBox(width: 12),
                // Takes what's left and sits at the right edge; a city like
                // "Kota Administrasi Jakarta Selatan" ellipsizes rather than
                // pushing the row past a narrow phone.
                Expanded(
                  child: store.cityName.isEmpty
                      ? const SizedBox.shrink()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Icon(LucideIcons.mapPin, size: 13, color: muted),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                store.cityName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption(muted),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedForeground;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: muted),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.caption(muted)),
      ],
    );
  }
}

/// The verified-seller check. Blue on every surface, not the brand red:
/// red is the app's action colour, and a red mark beside a name reads as a
/// warning rather than a credential.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 16});

  final double size;

  static const color = Color(0xFF3B82F6);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Terverifikasi',
      child: Icon(
        LucideIcons.badgeCheck,
        size: size,
        color: color,
        semanticLabel: 'Terverifikasi',
      ),
    );
  }
}

/// The Top Seller mark: an amber bookmark ribbon with a white star cut into
/// it. Phosphor's `bookmark-simple-fill` and `star-fill`, which Lucide has
/// no filled equivalent of, so they're drawn from their paths.
class TopSellerBadge extends StatelessWidget {
  const TopSellerBadge({super.key, this.size = 18});

  final double size;

  // The star sits 8/18 of the ribbon's size, 5/18 in and 4/18 down.
  static const _svg = '''
<svg viewBox="0 0 14 14" xmlns="http://www.w3.org/2000/svg">
<path fill="#C27C0E" d="M10.9375 2.625l0 9.625q0 0.27344-0.21875 0.38281-0.21875 0.10938-0.4375 0l-3.28125-2.07812-3.28125 2.07812q-0.10938 0.05469-0.21875 0.05469-0.10938 0-0.21875-0.05469-0.21875-0.10937-0.21875-0.38281l0-9.625q0-0.38281 0.24609-0.62891 0.24609-0.24609 0.62891-0.24609l6.125 0q0.38281 0 0.62891 0.24609 0.24609 0.24609 0.24609 0.62891z"/>
<g transform="translate(3.8889 3.1111) scale(0.4444)">
<path fill="#FFFFFF" d="M12.79688 6.28906l-2.46094 2.07813 0.76562 3.17187q0.10938 0.4375-0.16406 0.79297-0.27344 0.35547-0.71094 0.35547-0.21875 0-0.4375-0.16406l-2.78906-1.75-2.57031 1.64062q-0.27344 0.16406-0.57422 0.16406-0.30078 0-0.54688-0.1914-0.24609-0.19141-0.35546-0.46485-0.10938-0.27344 0-0.60156l0.71093-2.89844-2.46094-2.13281q-0.21875-0.16406-0.30078-0.4375-0.08203-0.27344 0-0.51953 0.08203-0.24609 0.30078-0.4375 0.21875-0.19141 0.49219-0.19141l3.22656-0.21875 1.25782-3.0625q0.10938-0.21875 0.32812-0.38281 0.21875-0.16406 0.49219-0.16406 0.27344 0 0.49219 0.16406 0.21875 0.16406 0.32812 0.38281l1.20313 3.0625 3.28125 0.21875q0.27344 0 0.49219 0.19141 0.21875 0.19141 0.30078 0.4375 0.08203 0.24609 0 0.51953-0.08203 0.27344-0.30078 0.4375z"/>
</g>
</svg>''';

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Top Seller',
      child: SvgPicture.string(
        _svg,
        width: size,
        height: size,
        semanticsLabel: 'Top Seller',
      ),
    );
  }
}
