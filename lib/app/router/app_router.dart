import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/account/presentation/account_page.dart';
import '../../features/account/presentation/addresses_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/cart/presentation/cart_page.dart';
import '../../features/cart/presentation/checkout_page.dart';
import '../../features/chat/presentation/chat_inbox_page.dart';
import '../../features/chat/presentation/chat_thread_page.dart';
import '../../features/chat/repository/models/chat_models.dart';
import '../../features/content/presentation/support_page.dart';
import '../../features/content/presentation/terms_page.dart';
import '../../features/content/presentation/tutorial_page.dart';
import '../../features/expansions/presentation/card_detail_page.dart';
import '../../features/expansions/presentation/expansions_page.dart';
import '../../features/expansions/presentation/pack_detail_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/market/presentation/market_page.dart';
import '../../features/market/presentation/bid_listing_page.dart';
import '../../features/market/presentation/store_card_listing_page.dart';
import '../../features/market/presentation/store_detail_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/orders/presentation/dispute_detail_page.dart';
import '../../features/orders/presentation/order_detail_page.dart';
import '../../features/orders/presentation/order_dispute_page.dart';
import '../../features/orders/presentation/orders_page.dart';
import '../../features/portfolio/presentation/deck_detail_page.dart';
import '../../features/portfolio/presentation/deck_page.dart';
import '../../features/portfolio/presentation/inventory_page.dart';
import '../../features/portfolio/presentation/list_detail_page.dart';
import '../../features/portfolio/presentation/lists_page.dart';
import '../../features/portfolio/presentation/portfolio_page.dart';
import '../../features/proposals/presentation/card_proposals_page.dart';
import '../../features/proposals/presentation/offers_page.dart';
import '../../features/proposals/presentation/proposals_page.dart';
import '../../features/proposals/repository/models/proposal_card_group.dart';
import '../../features/scanner/presentation/scanner_page.dart';
import '../../features/search/presentation/advanced_search_page.dart';
import '../../features/search/presentation/search_results_page.dart';
import '../../features/seller/presentation/seller_dashboard_page.dart';
import '../../features/seller/presentation/seller_listing_offers_page.dart';
import '../../features/seller/presentation/seller_order_detail_page.dart';
import '../../features/seller/presentation/seller_orders_page.dart';
import '../../features/seller/presentation/seller_couriers_page.dart';
import '../../features/seller/presentation/seller_products_page.dart';
import '../../features/seller/presentation/seller_store_page.dart';
import '../../features/seller/presentation/seller_store_profile_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/user/presentation/following_page.dart';
import '../../features/user/presentation/user_profile_page.dart';
import '../../features/user/presentation/users_search_page.dart';
import '../../features/wallet/presentation/wallet_page.dart';
import '../app_shell.dart';
import 'go_router_refresh_stream.dart';
import 'routes.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Five-branch shell route mirroring `MobileBottomNav`'s buyer tabs
/// (Beranda/Ekspansi/Koleksi/Market/Akun), plus the rest of the
/// buyer-facing surface (search, auth, cart, orders, chat, proposals,
/// wallet, notifications, settings, users, decks/lists, static content) as
/// full-screen routes pushed above the shell — mirroring how these routes
/// hide `MobileBottomNav` on the web (`HIDDEN_PREFIXES` / `/orders/*`).
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.home,
  refreshListenable: GoRouterRefreshStream(
    Supabase.instance.client.auth.onAuthStateChange,
  ),
  redirect: (context, state) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final loggingIn =
        state.matchedLocation == Routes.login ||
        state.matchedLocation == Routes.signup;
    if (loggedIn && loggingIn) return Routes.account;
    return null;
  },
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) =>
          AppShell(navigationShell: shell, state: state),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: Routes.home, builder: (_, __) => const HomePage()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.expansions,
              builder: (_, __) => const ExpansionsPage(),
              routes: [
                // On the root navigator, not the branch's: these are leaf
                // pages the whole app links to — a notification, an order,
                // a chat event card — and pushing a branch route from a
                // route that sits *above* the shell duplicates a page key,
                // which trips Navigator's `!keyReservation.contains(key)`
                // assertion and takes the screen down. They already hide
                // the bottom nav, so nothing changes visually.
                GoRoute(
                  path: ':packSlug',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, state) => PackDetailPage(
                    packSlug: state.pathParameters['packSlug']!,
                  ),
                  routes: [
                    GoRoute(
                      path: ':cardId',
                      parentNavigatorKey: rootNavigatorKey,
                      builder: (_, state) => CardDetailPage(
                        packSlug: state.pathParameters['packSlug']!,
                        cardId: int.parse(state.pathParameters['cardId']!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.search,
              // `?q=` arrives from the results page's filter button, which
              // hands the form the query already typed.
              builder: (_, state) => AdvancedSearchPage(
                initialQuery: state.uri.queryParameters['q'],
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.portfolio,
              builder: (_, __) => const PortfolioPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.market,
              builder: (_, __) => const MarketPage(),
              routes: [
                GoRoute(
                  path: ':handle',
                  // Defaulted rather than asserted: a caller that builds
                  // `/market/` from an empty handle would otherwise take the
                  // app down with a null check. An empty handle resolves to
                  // no store, which the page already renders as "Toko tidak
                  // ditemukan".
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, state) => StoreDetailPage(
                    handle: state.pathParameters['handle'] ?? '',
                  ),
                  routes: [
                    GoRoute(
                      path: 'card/:cardId',
                      parentNavigatorKey: rootNavigatorKey,
                      builder: (_, state) => StoreCardListingPage(
                        storeSlug: state.pathParameters['handle'] ?? '',
                        cardId:
                            int.tryParse(
                              state.pathParameters['cardId'] ?? '',
                            ) ??
                            0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.account,
              builder: (_, __) => const AccountPage(),
            ),
          ],
        ),
      ],
    ),

    // Full results for one query, from the search bar's "Cari semua" row.
    GoRoute(
      path: '/search',
      builder: (_, state) =>
          SearchResultsPage(query: state.uri.queryParameters['q'] ?? ''),
    ),

    // Card scanner (opened from AppTopBar's scan button).
    GoRoute(path: Routes.scan, builder: (_, __) => const ScannerPage()),

    // Auth.
    GoRoute(path: Routes.login, builder: (_, __) => const LoginPage()),
    GoRoute(path: Routes.signup, builder: (_, __) => const SignupPage()),
    GoRoute(
      path: Routes.forgotPassword,
      builder: (_, __) => const ForgotPasswordPage(),
    ),
    GoRoute(
      path: Routes.resetPassword,
      builder: (_, __) => const ResetPasswordPage(),
    ),

    // Commerce.
    GoRoute(
      path: '/bid/:slug',
      builder: (_, state) =>
          BidListingPage(slug: state.pathParameters['slug'] ?? ''),
    ),
    GoRoute(path: Routes.cart, builder: (_, __) => const CartPage()),
    // Review, delivery address and promo code are native; the page itself
    // pushes the WebView for courier choice and payment, which need the
    // Biteship and Xendit secrets plus `service_role` RPCs. The web app's
    // own `/cart/checkout/success` redirect happens inside that WebView, so
    // there's no separate native success route to register.
    GoRoute(path: Routes.checkout, builder: (_, __) => const CheckoutPage()),
    GoRoute(
      path: Routes.orders,
      builder: (_, __) => const OrdersPage(),
      routes: [
        GoRoute(
          path: ':slug',
          builder: (_, state) =>
              OrderDetailPage(slug: state.pathParameters['slug']!),
          routes: [
            GoRoute(
              path: 'dispute',
              builder: (_, state) =>
                  DisputeDetailPage(orderSlug: state.pathParameters['slug']!),
            ),
            GoRoute(
              path: 'open-dispute',
              builder: (_, state) =>
                  OrderDisputePage(slug: state.pathParameters['slug']!),
            ),
          ],
        ),
      ],
    ),
    GoRoute(path: Routes.offers, builder: (_, __) => const OffersPage()),
    GoRoute(
      path: '/proposals/card/:cardId',
      builder: (_, state) => CardProposalsPage(
        cardId: int.tryParse(state.pathParameters['cardId'] ?? '') ?? 0,
      ),
    ),
    GoRoute(
      path: Routes.proposals,
      builder: (_, state) => ProposalsPage(
        initialFilter: switch (state.uri.queryParameters['filter']) {
          'perlu_aksi' => ProposalFeedFilter.needsAction,
          'menunggu' => ProposalFeedFilter.waiting,
          'diterima' => ProposalFeedFilter.accepted,
          'selesai' => ProposalFeedFilter.done,
          _ => ProposalFeedFilter.all,
        },
      ),
    ),
    GoRoute(path: Routes.wallet, builder: (_, __) => const WalletPage()),

    // Seller.
    GoRoute(
      path: Routes.seller,
      builder: (_, __) => const SellerDashboardPage(),
    ),
    GoRoute(
      path: Routes.sellerProducts,
      builder: (_, __) => const SellerProductsPage(),
      routes: [
        GoRoute(
          path: 'offers/:slug',
          builder: (_, state) => SellerListingOffersPage(
            listingSlug: state.pathParameters['slug'] ?? '',
          ),
        ),
      ],
    ),
    GoRoute(
      path: Routes.sellerOrders,
      builder: (_, state) =>
          SellerOrdersPage(initialFilter: state.uri.queryParameters['filter']),
      routes: [
        GoRoute(
          path: ':slug',
          builder: (_, state) => SellerOrderDetailPage(
            orderSlug: state.pathParameters['slug'] ?? '',
          ),
        ),
      ],
    ),
    GoRoute(
      path: Routes.sellerStore,
      builder: (_, __) => const SellerStorePage(),
    ),
    GoRoute(
      path: Routes.sellerStoreProfile,
      builder: (_, __) => const SellerStoreProfilePage(),
    ),
    GoRoute(
      path: Routes.sellerCouriers,
      builder: (_, __) => const SellerCouriersPage(),
    ),

    // Social / account.
    GoRoute(
      path: Routes.chat,
      builder: (_, __) => const ChatInboxPage(),
      routes: [
        // Declared before `:slug` so it isn't matched as a room slug.
        GoRoute(
          path: 'new',
          builder: (_, state) =>
              ChatThreadPage(target: state.extra as ChatTarget?),
        ),
        GoRoute(
          path: ':slug',
          builder: (_, state) => ChatThreadPage(
            slug: state.pathParameters['slug']!,
            titleHint: state.extra as String?,
          ),
        ),
      ],
    ),
    GoRoute(
      path: Routes.notifications,
      builder: (_, __) => const NotificationsPage(),
    ),
    GoRoute(path: Routes.settings, builder: (_, __) => const SettingsPage()),
    GoRoute(path: Routes.addresses, builder: (_, __) => const AddressesPage()),
    GoRoute(
      path: Routes.accountFollowing,
      builder: (_, __) => const FollowingPage(),
    ),
    GoRoute(path: Routes.users, builder: (_, __) => const UsersSearchPage()),
    GoRoute(
      path: '/user/:username',
      builder: (_, state) =>
          UserProfilePage(username: state.pathParameters['username']!),
    ),
    GoRoute(path: Routes.decks, builder: (_, __) => const DeckPage()),
    GoRoute(path: Routes.inventory, builder: (_, __) => const InventoryPage()),
    GoRoute(
      path: '/portfolio/deck/:id',
      builder: (_, state) =>
          DeckDetailPage(deckId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: Routes.lists,
      builder: (_, __) => const ListsPage(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (_, state) =>
              ListDetailPage(listId: state.pathParameters['id']!),
        ),
      ],
    ),

    // Content.
    GoRoute(path: Routes.support, builder: (_, __) => const SupportPage()),
    GoRoute(path: Routes.tutorial, builder: (_, __) => const TutorialPage()),
    GoRoute(
      path: '/terms/:slug',
      builder: (_, state) => TermsPage(slug: state.pathParameters['slug']!),
    ),
  ],
);
