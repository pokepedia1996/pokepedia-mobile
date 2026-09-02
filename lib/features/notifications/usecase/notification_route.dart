import '../../../app/router/routes.dart';

/// Where tapping a notification should land, given the `action_url` the
/// server wrote.
///
/// Those URLs are written for the website — the triggers in
/// `supabase/migrations` emit `/orders/<slug>`, `/seller/orders/<slug>`,
/// `/seller/disputes/<slug>`, `/seller/products?filter=penawaran`,
/// `/seller/proposals`, `/proposals?tab=dikirim|diterima`, `/chat`,
/// `/market/<slug>`. Some of those paths exist in the app under the same
/// name, some exist under a different one, and a few have no screen here at
/// all. Pushing one verbatim without checking lands on the router's error
/// page, so anything unrecognised returns null and the row just marks read.
String? appRouteForActionUrl(String? actionUrl) {
  if (actionUrl == null || !actionUrl.startsWith('/')) return null;

  final uri = Uri.tryParse(actionUrl);
  if (uri == null) return null;
  final path = uri.path;
  final segments = uri.pathSegments;

  // Seller paths first: `/seller/orders` also starts with a prefix the buyer
  // list would otherwise claim.
  if (path.startsWith('/seller')) return _sellerRoute(segments, uri);

  switch (segments.firstOrNull) {
    case 'orders':
      // `/orders` and `/orders/<slug>` are the app's own paths already.
      return segments.length > 1
          ? Routes.orderDetail(segments[1])
          : Routes.orders;
    case 'proposals':
      return _proposalsRoute(uri);
    case 'chat':
      return segments.length > 1 ? Routes.chatThread(segments[1]) : Routes.chat;
    case 'market':
      return segments.length > 1
          ? Routes.storeDetail(segments[1])
          : Routes.market;
    case 'user':
      return segments.length > 1 ? Routes.userProfile(segments[1]) : null;
    case 'wallet':
      return Routes.wallet;
    case 'notifications':
      return Routes.notifications;
    case 'expansions':
      return segments.length > 1
          ? Routes.packDetail(segments[1])
          : Routes.expansions;
    case 'portfolio':
      return path;
    default:
      return null;
  }
}

String? _sellerRoute(List<String> segments, Uri uri) {
  // segments[0] is 'seller'.
  switch (segments.length > 1 ? segments[1] : null) {
    case null:
      return Routes.seller;
    case 'orders':
      return segments.length > 2
          ? Routes.sellerOrderDetail(segments[2])
          : _sellerOrdersList(uri);
    case 'disputes':
      // The app has no seller dispute screen yet. The disputed orders list is
      // the nearest place the complaint can actually be worked on, and it is
      // reachable — dropping the tap would leave the loudest notification
      // there is doing nothing.
      return Routes.sellerOrdersFiltered('disputed');
    case 'products':
      // Web's `?filter=penawaran` bucket has no counterpart here; offers are
      // per-listing (`/seller/products/offers/<slug>`) and the notification
      // names no listing, so the list itself is as close as this gets.
      return Routes.sellerProducts;
    case 'proposals':
      // Proposals made on this seller's listings — the ones waiting on them.
      return '${Routes.proposals}?filter=perlu_aksi';
    case 'settings':
      return Routes.sellerStoreProfile;
    case 'couriers':
      return Routes.sellerCouriers;
    case 'chat':
      return Routes.chat;
    default:
      return null;
  }
}

/// Web's orders list carries `?filter=`, and so does the app's — but only
/// for the keys it knows.
String _sellerOrdersList(Uri uri) {
  final filter = uri.queryParameters['filter'];
  const known = {
    'all',
    'awaiting_payment',
    'urgent',
    'in_transit',
    'arrived',
    'success',
    'cancel_requested',
    'failed',
    'disputed',
  };
  return known.contains(filter)
      ? Routes.sellerOrdersFiltered(filter!)
      : Routes.sellerOrders;
}

/// Web splits proposals by direction (`?tab=dikirim|diterima`); the app
/// splits the same feed by what it is waiting on. "Diterima" — proposals
/// somebody sent *you* — is the app's "Perlu aksi"; "dikirim" — the ones you
/// sent — is "Menunggu".
String _proposalsRoute(Uri uri) {
  return switch (uri.queryParameters['tab']) {
    'diterima' => '${Routes.proposals}?filter=perlu_aksi',
    'dikirim' => '${Routes.proposals}?filter=menunggu',
    _ => Routes.proposals,
  };
}
