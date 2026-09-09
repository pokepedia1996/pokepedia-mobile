import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/listing_model.dart';
import '../../../../shared/widgets/seller_avatar.dart';

/// Asks which seller an offer should go to.
///
/// An order-book row is a price level, not a listing, so a tapped ask can
/// cover several sellers at the same price and condition. The bid side has
/// no equivalent — a proposal there is broadcast to everyone at the level at
/// once — but an offer negotiates one listing, so one has to be chosen.
Future<ListingModel?> showAskSellerPicker(
  BuildContext context, {
  required List<ListingModel> listings,
}) {
  return showModalBottomSheet<ListingModel>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              'Pilih penjual',
              style: AppTypography.h3(sheetContext.appColors.onSurface),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '${listings.length} penjual di harga ini menerima penawaran.',
              style: AppTypography.bodySm(sheetContext.mutedForeground),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: listings.length,
              itemBuilder: (context, i) => _SellerRow(listing: listings[i]),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SellerRow extends StatelessWidget {
  const _SellerRow({required this.listing});

  final ListingModel listing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: () => Navigator.of(context).pop(listing),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            SellerAvatar(
              name: listing.storeName,
              imageUrl: listing.storeLogoUrl ?? listing.sellerAvatarUrl,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          listing.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                      ),
                      if (listing.isVerified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          LucideIcons.badgeCheck,
                          size: 14,
                          color: colors.primary,
                        ),
                      ],
                    ],
                  ),
                  Text(
                    [
                      'Stok ${listing.quantity}',
                      if (listing.cityName.isNotEmpty) listing.cityName,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatRupiah(listing.price),
              style: AppTypography.bodySmSemibold(colors.error),
            ),
          ],
        ),
      ),
    );
  }
}
