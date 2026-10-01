import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../ads/usecase/ads_notifier.dart';

/// The banner slot on Beranda — 2:1, drawn for an 800×400 image.
///
/// Fixed at that ratio whatever the screen: artwork is made once, at one
/// size, and a slot that changed shape per device would crop somebody's
/// headline off.
///
/// Nothing booked means nothing drawn — no placeholder, no reserved gap.
/// Web fills an empty slot with a "Space Available" house ad, which belongs
/// on a page a media buyer might be reading; on a phone it is a hole in the
/// scroll between the portfolio and the market.
class HomeAdSlot extends ConsumerWidget {
  const HomeAdSlot({super.key, this.placement = AdPlacement.home});

  final String placement;

  Future<void> _open(BuildContext context, String href) async {
    if (href.isEmpty) return;
    // An in-app path stays in the app; anything else is a booking pointing
    // at the advertiser's own site.
    if (href.startsWith('/')) {
      context.push(href);
      return;
    }
    final uri = Uri.tryParse(href);
    if (uri == null || !uri.hasScheme) return;
    await launcher.launchUrl(
      uri,
      mode: launcher.LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads = ref.watch(adsProvider(placement)).valueOrNull;
    if (ads == null || ads.isEmpty) return const SizedBox.shrink();
    final ad = ads.first;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: AspectRatio(
        aspectRatio: 2,
        child: InkWell(
          onTap: () => _open(context, ad.href),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: context.appColors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: context.borderColor),
            ),
            child: Image.network(
              ad.imageUrl,
              fit: BoxFit.cover,
              semanticLabel: ad.companyName,
              // A creative that fails to load leaves the slot as it was
              // before it was booked: absent.
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
