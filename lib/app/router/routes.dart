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
  static const account = '/account';

  // Search (opened from AppTopBar, not a bottom-nav tab).
  static const search = '/advanced-search';

  // Auth.
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';

  // Commerce.
  static const cart = '/cart';
  static const checkout = '/cart/checkout';
  static const checkoutSuccess = '/cart/checkout/success';
  static const orders = '/orders';
  static const proposals = '/proposals';

  /// Ports web's `?tab=diterima`. The market banner sends you where the work
  /// is: incoming proposals need answering, so they outrank ones you're
  /// waiting on.
  static const proposalsReceived = '/proposals?tab=diterima';

  /// Offers made on ask listings. Not a web route: web surfaces these in
  /// the seller's offers list and inside chat, neither of which the app has.
  static const offers = '/proposals/offers';

  /// Everything happening on one card — web's `/proposals/card/[cardId]`.
  static String cardProposals(int cardId) => '/proposals/card/$cardId';

  /// Proposals this user sent as a seller. Web's `?tab=dikirim`.
  static const proposalsSent = '/proposals?tab=dikirim';

  /// The user's own WTB bids. Where "N bid aktif" points — those rows live
  /// on this tab and nowhere else.
  static const proposalsBids = '/proposals?tab=bid';
  static const wallet = '/wallet';
  static const lists = '/portfolio/list';

  // Seller.
  static const seller = '/seller';
  static const sellerProducts = '/seller/products';
  static const sellerOrders = '/seller/orders';

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
  static String orderDetail(String slug) => '/orders/$slug';

  /// View an existing dispute's detail/timeline.
  static String orderDispute(String slug) => '/orders/$slug/dispute';

  /// File a new dispute.
  static String orderOpenDispute(String slug) => '/orders/$slug/open-dispute';
  static String chatThread(String slug) => '/chat/$slug';

  /// A conversation with no room yet — the recipient rides along in
  /// `extra` as a [ChatTarget], and the room is created on the first send.
  static const chatNew = '/chat/new';
  static String userProfile(String username) => '/user/$username';
  static String deckDetail(String id) => '/portfolio/deck/$id';
  static String listDetail(String id) => '/portfolio/list/$id';
  static String terms(String slug) => '/terms/$slug';
}
