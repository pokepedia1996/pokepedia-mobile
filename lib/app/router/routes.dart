/// Route path constants, ported from the `app/` route segments on the web.
class Routes {
  Routes._();

  // Bottom-nav tabs.
  static const home = '/';
  static const expansions = '/expansions';
  static const portfolio = '/portfolio/collection';
  static const decks = '/portfolio/deck';
  static const inventory = '/portfolio/inventory';
  static const market = '/market';

  /// The marketplace opened on a query — the "di Market" scope in quick
  /// search. Stock someone is selling right now, as opposed to the catalog.
  static String marketSearch(String query) =>
      '/market?q=${Uri.encodeQueryComponent(query)}';

  /// The marketplace's shop directory, filtered by name — "Cari toko".
  static String marketStoreSearch(String query) =>
      '/market?tab=stores&q=${Uri.encodeQueryComponent(query)}';
  static const account = '/account';

  // Search (opened from AppTopBar, not a bottom-nav tab).
  static const search = '/advanced-search';

  /// Advanced search opened on a query, carrying what was typed instead of
  /// dropping it.
  static String searchQuery(String query) =>
      '/advanced-search?q=${Uri.encodeQueryComponent(query)}';

  /// Everything matching one query — web's `/search?q=`, and where the search
  /// bar's "Cari semua" row goes.
  static String searchResults(String query) =>
      '/search?q=${Uri.encodeQueryComponent(query)}';

  /// Camera card scanner. Opened from [AppTopBar] alongside search, and
  /// full-screen above the shell — it takes over the whole viewport (camera
  /// preview plus its own controls), so the bottom nav would only be in the
  /// way. Web serves the same feature at `/scan`.
  static const scan = '/scan';

  // Auth.
  /// Where the emailed confirmation and recovery links land.
  ///
  /// The app claims this path as an App Link, so the OS hands the whole URL
  /// to the router as a location to open — which means the router has to
  /// know it, even though nothing is drawn here. [AuthLinkHandler] is what
  /// actually redeems the token; this route only decides where the user is
  /// standing while that happens.
  static const authConfirm = '/auth/confirm';

  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';

  // Commerce.
  static const cart = '/cart';
  static const checkout = '/cart/checkout';
  static const checkoutSuccess = '/cart/checkout/success';

  /// The saldo thank-you screen, carrying what it needs to state the outcome.
  /// Query params rather than `extra` so the destination survives the
  /// `go(home)` + `push` that `goHomeThen` performs.
  static String checkoutSuccessFor({required int cards, required int total}) =>
      '$checkoutSuccess?cards=$cards&total=$total';
  static const orders = '/orders';
  static const proposals = '/proposals';

  /// Where the work is: proposals somebody sent you need answering, so they
  /// outrank the ones you are waiting on. Web splits this feed by direction
  /// (`?tab=diterima`); the app's page filters by what a proposal is waiting
  /// on, and "perlu aksi" is exactly the received-and-pending ones.
  static const proposalsReceived = '/proposals?filter=perlu_aksi';

  /// Offers made on ask listings. Not a web route: web surfaces these in
  /// the seller's offers list and inside chat, neither of which the app has.
  static const offers = '/proposals/offers';

  /// "Penawaranku" — every bid this user answered with "Penuhi Bid", across
  /// all cards.
  static const myProposals = '/proposals/mine';

  /// Everything happening on one card — web's `/proposals/card/[cardId]`.
  static String cardProposals(int cardId) => '/proposals/card/$cardId';

  /// Proposals this user sent and is waiting on — web's `?tab=dikirim`.
  static const proposalsSent = '/proposals?filter=menunggu';

  /// The user's own WTB bids. Where "N bid aktif" points. The page has no
  /// bids-only filter — they are spread across the lifecycle ones — so this
  /// opens the whole feed rather than a filter that would hide half of them.
  static const proposalsBids = proposals;
  static const wallet = '/wallet';
  static const lists = '/portfolio/list';

  // Seller.
  static const seller = '/seller';
  static const sellerProducts = '/seller/products';
  static const sellerOrders = '/seller/orders';

  /// The numbers behind the dashboard's headline — opened from it.
  static const sellerPerformance = '/seller/performance';

  /// Kelola Listing opened on one tab.
  ///
  /// The tab is in the link rather than left to whatever the page was last
  /// showing: tapping "DRAFT" on the dashboard and landing on Aktif reads as
  /// the tap having gone somewhere else. Same reasoning as the orders
  /// counters below, and a deep link carries it too.
  static String sellerProductsTab(String bucketKey) =>
      '/seller/products?tab=$bucketKey';

  /// Kelola Listing with the offers filter already on — the dashboard's
  /// "Ada penawaran masuk" row counts exactly these.
  static String sellerProductsWithOffers() =>
      '/seller/products?tab=active&offers=1';

  /// The orders list opened on one tab — web's `?filter=` links, which the
  /// dashboard's counters carry so a number opens the list it counted.
  static String sellerOrdersFiltered(String filterKey) =>
      '/seller/orders?filter=$filterKey';

  /// Offers a buyer has made on one listing. Web keys this by
  /// `listings.slug`, and so does the app.
  static String sellerListingOffers(String listingSlug) =>
      '/seller/products/offers/$listingSlug';

  /// One order as its seller. Web calls the parameter `matchId`; the app
  /// passes `orders.slug`, which is the same value that route resolves.
  static String sellerOrderDetail(String orderSlug) =>
      '/seller/orders/$orderSlug';

  /// Web's "Toko" section and its three pages. `/seller/settings` is the
  /// path web uses for the profile; kept as `/seller/store/profile` here so
  /// the section reads as a hierarchy on a stack-based navigator.
  static const sellerStore = '/seller/store';
  static const sellerStoreProfile = '/seller/store/profile';
  static const sellerCouriers = '/seller/store/couriers';

  // Social / account.
  static const chat = '/chat';
  static const notifications = '/notifications';
  static const settings = '/settings';
  static const addresses = '/settings/addresses';
  static const users = '/users';
  static const accountFollowing = '/account/following';

  // Content.
  static const support = '/support';
  static const tutorial = '/tutorial';

  static String packDetail(String slug) => '/expansions/$slug';
  static String cardDetail(String packSlug, int cardId) =>
      '/expansions/$packSlug/$cardId';
  static String storeDetail(String handle) => '/market/$handle';
  static String storeCardDetail(String handle, int cardId) =>
      '/market/$handle/card/$cardId';

  /// One WTB bid, by its listing slug. Top-level rather than under
  /// `/market/:handle`: a bid belongs to a buyer, and a buyer who has never
  /// sold anything has no storefront handle to hang it off.
  static String bidListing(String slug) => '/bid/$slug';
  static String orderDetail(String slug) => '/orders/$slug';

  /// View an existing dispute's detail/timeline.
  static String orderDispute(String slug) => '/orders/$slug/dispute';

  /// File a new dispute.
  static String orderOpenDispute(String slug) => '/orders/$slug/open-dispute';

  /// A room, optionally naming the listing it was opened about.
  ///
  /// The listing rides in the query rather than in `extra`: that slot
  /// already carries the title hint here, and a query parameter survives a
  /// deep link and a process restart, which `extra` does not.
  static String chatThread(String slug, {int? listingId}) =>
      listingId == null ? '/chat/$slug' : '/chat/$slug?listing=$listingId';

  /// A conversation with no room yet — the recipient rides along in
  /// `extra` as a [ChatTarget], and the room is created on the first send.
  static const chatNew = '/chat/new';
  static String userProfile(String username) => '/user/$username';
  static String deckDetail(String id) => '/portfolio/deck/$id';
  static String listDetail(String id) => '/portfolio/list/$id';
  static String terms(String slug) => '/terms/$slug';
}
