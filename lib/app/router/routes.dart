/// Route path constants, ported from the `app/` route segments on the web.
class Routes {
  Routes._();

  // Bottom-nav tabs.
  static const home = '/';
  static const expansions = '/expansions';
  static const portfolio = '/portfolio/collection';
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
  static const wallet = '/wallet';
  static const lists = '/portfolio/list';

  // Social / account.
  static const chat = '/chat';
  static const notifications = '/notifications';
  static const settings = '/settings';
  static const users = '/users';
  static const accountFollowing = '/account/following';

  // Content.
  static const support = '/support';
  static const tutorial = '/tutorial';

  static String packDetail(String slug) => '/expansions/$slug';
  static String cardDetail(String packSlug, int cardId) =>
      '/expansions/$packSlug/$cardId';
  static String storeDetail(String handle) => '/market/$handle';
  static String storeCardDetail(String handle, int cardId) => '/market/$handle/card/$cardId';
  static String orderDetail(String slug) => '/orders/$slug';

  /// View an existing dispute's detail/timeline.
  static String orderDispute(String slug) => '/orders/$slug/dispute';

  /// File a new dispute.
  static String orderOpenDispute(String slug) => '/orders/$slug/open-dispute';
  static String chatThread(String slug) => '/chat/$slug';
  static String userProfile(String username) => '/user/$username';
  static String deckDetail(String id) => '/portfolio/deck/$id';
  static String listDetail(int id) => '/portfolio/list/$id';
  static String terms(String slug) => '/terms/$slug';
}
