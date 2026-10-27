import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../seller/usecase/seller_notifier.dart';
import '../../usecase/market_notifier.dart';
import 'store_poster.dart';
import 'store_share_sheet.dart';

/// Right after a listing goes up, opens the store's poster sheet — the
/// moment a seller most wants the listing seen. Straight to the sheet, with
/// no "share?" step before it: the sheet is itself the offer, and closing it
/// is the way to decline.
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

    await showStoreShareSheet(context, store: store, initialSide: side);
  } catch (e) {
    debugPrint('[share] store poster prompt skipped: $e');
  }
}
