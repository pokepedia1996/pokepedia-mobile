import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../seller/usecase/seller_notifier.dart';
import '../../usecase/market_notifier.dart';
import 'store_poster.dart';
import 'store_share_sheet.dart';

/// Right after a listing goes up, offers to share the store's poster — the
/// moment a seller most wants the listing seen.
///
/// Opens on [side], the side just listed. Says nothing when the user has no
/// storefront to put on a poster, or when it can't be loaded: the listing
/// itself already succeeded, and that is what the user asked for.
///
/// Reads through [context]'s provider scope rather than a `WidgetRef`, so
/// a sheet that has already closed can hand over its caller's context.
Future<void> promptShareStorePoster(
  BuildContext context, {
  required PosterSide side,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    final identity = await container.read(sellerIdentityProvider.future);
    final handle = identity.storeHandle;
    if (handle == null) return;

    // The poster reads the store's listings through these, which may still
    // hold the book from before this listing went up.
    container
      ..invalidate(storeDetailProvider(handle))
      ..invalidate(storeListingsProvider(handle));
    final store = await container.read(storeDetailProvider(handle).future);
    if (store == null || !context.mounted) return;

    final share = await showDialog<bool>(
      context: context,
      builder: (_) => _SharePrompt(side: side),
    );
    if (share != true || !context.mounted) return;
    await showStoreShareSheet(context, store: store, initialSide: side);
  } catch (e) {
    debugPrint('[share] store poster prompt skipped: $e');
  }
}

class _SharePrompt extends StatelessWidget {
  const _SharePrompt({required this.side});

  final PosterSide side;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (title, body) = switch (side) {
      PosterSide.wts => (
        'Listing sudah tayang!',
        'Bagikan poster tokomu supaya lebih banyak pembeli melihat kartu '
            'yang kamu jual.',
      ),
      PosterSide.wtb => (
        'Bid sudah tayang!',
        'Bagikan poster tokomu supaya lebih banyak penjual tahu kartu yang '
            'kamu cari.',
      ),
    };

    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      icon: Icon(LucideIcons.share2, color: colors.primary),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(
        body,
        textAlign: TextAlign.center,
        style: AppTypography.bodySm(context.mutedForeground),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Nanti'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Bagikan Poster'),
        ),
      ],
    );
  }
}
