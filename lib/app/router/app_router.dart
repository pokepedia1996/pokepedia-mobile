import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/account_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/reset_password_page.dart';
import '../../features/auth/presentation/signup_page.dart';
import '../../features/cart/presentation/cart_page.dart';
import '../../features/cart/presentation/checkout_page.dart';
import '../../features/cart/presentation/checkout_success_page.dart';
import '../../features/chat/presentation/chat_inbox_page.dart';
import '../../features/chat/presentation/chat_thread_page.dart';
import '../../features/content/presentation/support_page.dart';
import '../../features/content/presentation/terms_page.dart';
import '../../features/content/presentation/tutorial_page.dart';
import '../../features/expansions/presentation/card_detail_page.dart';
import '../../features/expansions/presentation/expansions_page.dart';
import '../../features/expansions/presentation/pack_detail_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/market/presentation/market_page.dart';
import '../../features/market/presentation/store_detail_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/orders/presentation/dispute_detail_page.dart';
import '../../features/orders/presentation/order_detail_page.dart';
import '../../features/orders/presentation/order_dispute_page.dart';
import '../../features/orders/presentation/orders_page.dart';
import '../../features/portfolio/presentation/deck_detail_page.dart';
import '../../features/portfolio/presentation/list_detail_page.dart';
import '../../features/portfolio/presentation/lists_page.dart';
import '../../features/portfolio/presentation/portfolio_page.dart';
import '../../features/proposals/presentation/proposals_page.dart';
import '../../features/search/presentation/advanced_search_page.dart';
import '../../features/settings/presentation/settings_page.dart';
import '../../features/user/presentation/user_profile_page.dart';
import '../../features/user/presentation/users_search_page.dart';
import '../../features/wallet/presentation/wallet_page.dart';
import '../app_shell.dart';
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
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(navigationShell: shell),
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
                GoRoute(
                  path: ':packSlug',
                  builder: (_, state) => PackDetailPage(
                    packSlug: state.pathParameters['packSlug']!,
                  ),
                  routes: [
                    GoRoute(
                      path: ':cardId',
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
                  builder: (_, state) => StoreDetailPage(
                    handle: state.pathParameters['handle']!,
                  ),
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

    // Search (opened from AppTopBar's tap-to-search field).
    GoRoute(
      path: Routes.search,
      builder: (_, __) => const AdvancedSearchPage(),
    ),

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
    GoRoute(path: Routes.cart, builder: (_, __) => const CartPage()),
    GoRoute(path: Routes.checkout, builder: (_, __) => const CheckoutPage()),
    GoRoute(
      path: Routes.checkoutSuccess,
      builder: (_, __) => const CheckoutSuccessPage(),
    ),
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
    GoRoute(
      path: Routes.proposals,
      builder: (_, __) => const ProposalsPage(),
    ),
    GoRoute(path: Routes.wallet, builder: (_, __) => const WalletPage()),

    // Social / account.
    GoRoute(
      path: Routes.chat,
      builder: (_, __) => const ChatInboxPage(),
      routes: [
        GoRoute(
          path: ':slug',
          builder: (_, state) =>
              ChatThreadPage(slug: state.pathParameters['slug']!),
        ),
      ],
    ),
    GoRoute(
      path: Routes.notifications,
      builder: (_, __) => const NotificationsPage(),
    ),
    GoRoute(path: Routes.settings, builder: (_, __) => const SettingsPage()),
    GoRoute(
      path: Routes.users,
      builder: (_, __) => const UsersSearchPage(),
    ),
    GoRoute(
      path: '/user/:username',
      builder: (_, state) =>
          UserProfilePage(username: state.pathParameters['username']!),
    ),
    GoRoute(
      path: '/portfolio/deck/:id',
      builder: (_, state) =>
          DeckDetailPage(deckId: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: Routes.lists,
      builder: (_, __) => const ListsPage(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (_, state) =>
              ListDetailPage(listId: int.parse(state.pathParameters['id']!)),
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
