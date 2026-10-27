import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/presentation/widgets/onboarding_shortcuts_section.dart';
import 'package:pokepedia_mobile/features/market/presentation/market_page.dart';
import 'package:pokepedia_mobile/features/market/repository/market_repository.dart';
import 'package:pokepedia_mobile/features/market/repository/models/market_page.dart';
import 'package:pokepedia_mobile/features/market/usecase/market_notifier.dart';
import 'package:pokepedia_mobile/features/onboarding/usecase/onboarding_intents.dart';
import 'package:pokepedia_mobile/shared/models/store_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What onboarding's "Mau ngapain?" leaves behind: the picks kept on this
/// device, the "Lanjutkan" cards on Beranda, and Market's note on WTBs.
class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.user);

  final AppUser? user;

  @override
  Future<AppUser?> build() async => user;
}

const _me = AppUser(id: 'me', email: 'me@example.com', onboarded: true);

void _stored(List<String> intents, {List<String> dismissed = const []}) {
  SharedPreferences.setMockInitialValues({
    'onboarding_intents:me': intents,
    'onboarding_shortcuts_dismissed:me': dismissed,
  });
}

class _FakeMarket implements MarketRepository {
  @override
  Future<MarketListingsPage> fetchListings({
    required MarketBucket bucket,
    String query = '',
    MarketSort sort = MarketSort.createdDesc,
    MarketFilters filters = const MarketFilters(),
    MarketCursor? cursor,
    int limit = 40,
  }) async => const MarketListingsPage.empty();

  @override
  Future<ListingFacets> fetchListingFacets(MarketBucket bucket) async =>
      const ListingFacets(categories: [], rarities: [], cities: []);

  @override
  Future<List<StoreModel>> fetchStores({String query = ''}) async => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('the stored picks', () {
    test('every pick but the landing, less the closed ones', () {
      const intents = OnboardingIntents(
        intents: [
          OnboardingIntent.collect,
          OnboardingIntent.buy,
          OnboardingIntent.bid,
        ],
        dismissed: {OnboardingIntent.bid},
      );
      expect(intents.shortcuts, [OnboardingIntent.buy]);
    });

    test('kept per account, and closing one is kept too', () async {
      _stored(['buy', 'collect', 'sell']);
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _FakeAuth(_me))],
      );
      addTearDown(container.dispose);

      container.listen(onboardingIntentsProvider, (_, __) {});
      await container.read(authProvider.future);
      await Future<void>.delayed(Duration.zero);

      // List order, whatever order they were stored in.
      final state = container.read(onboardingIntentsProvider);
      expect(state.intents, [
        OnboardingIntent.collect,
        OnboardingIntent.buy,
        OnboardingIntent.sell,
      ]);

      await container
          .read(onboardingIntentsProvider.notifier)
          .dismiss(OnboardingIntent.buy);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('onboarding_shortcuts_dismissed:me'), ['buy']);
      expect(container.read(onboardingIntentsProvider).shortcuts, [
        OnboardingIntent.sell,
      ]);
    });

    test('a guest has none', () async {
      _stored(['buy', 'sell']);
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _FakeAuth(null))],
      );
      addTearDown(container.dispose);
      container.listen(onboardingIntentsProvider, (_, __) {});
      await container.read(authProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(onboardingIntentsProvider).intents, isEmpty);
    });
  });

  group('Beranda\'s Lanjutkan', () {
    Future<ProviderContainer> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
              body: SingleChildScrollView(child: OnboardingShortcutsSection()),
            ),
          ),
          for (final path in [Routes.market, Routes.portfolio, Routes.seller])
            GoRoute(path: path, builder: (_, __) => Text('page $path')),
        ],
      );
      addTearDown(router.dispose);
      final container = ProviderContainer(
        overrides: [authProvider.overrideWith(() => _FakeAuth(_me))],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('a card for each pick after the first', (tester) async {
      _stored(['collect', 'buy', 'bid']);
      await open(tester);

      expect(find.text('Lanjutkan'), findsOneWidget);
      expect(find.text(OnboardingIntent.collect.title), findsNothing);
      expect(find.text(OnboardingIntent.buy.title), findsOneWidget);
      expect(find.text(OnboardingIntent.bid.title), findsOneWidget);
    });

    testWidgets('nothing at all after Lewati dulu, or one pick', (
      tester,
    ) async {
      _stored([]);
      await open(tester);
      expect(find.text('Lanjutkan'), findsNothing);
    });

    testWidgets('a card goes where its pick lands', (tester) async {
      _stored(['collect', 'sell']);
      await open(tester);
      await tester.tap(find.text(OnboardingIntent.sell.title));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.seller}'), findsOneWidget);
    });

    testWidgets('Tawar brings Market\'s WTB note with it', (tester) async {
      _stored(['collect', 'bid']);
      final container = await open(tester);
      await tester.tap(find.text(OnboardingIntent.bid.title));
      await tester.pumpAndSettle();
      expect(find.text('page ${Routes.market}'), findsOneWidget);
      expect(container.read(marketWtbTipProvider), isTrue);
    });

    testWidgets('closing a card hides it for good', (tester) async {
      _stored(['collect', 'buy', 'sell']);
      await open(tester);
      await tester.tap(find.byTooltip('Sembunyikan').first);
      await tester.pumpAndSettle();

      expect(find.text(OnboardingIntent.buy.title), findsNothing);
      expect(find.text(OnboardingIntent.sell.title), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('onboarding_shortcuts_dismissed:me'), ['buy']);
    });
  });

  group('Market\'s WTB note', () {
    Future<ProviderContainer> open(
      WidgetTester tester, {
      bool tip = true,
    }) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [marketRepositoryProvider.overrideWithValue(_FakeMarket())],
      );
      addTearDown(container.dispose);
      container.read(marketWtbTipProvider.notifier).state = tip;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light, home: const MarketPage()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('opens on Buying, with the note', (tester) async {
      final container = await open(tester);
      expect(find.text('WTB = Want To Buy'), findsOneWidget);
      expect(container.read(bucketProvider), MarketBucket.buylist);
    });

    testWidgets('closing it clears it', (tester) async {
      final container = await open(tester);
      await tester.tap(find.byTooltip('Tutup'));
      await tester.pumpAndSettle();
      expect(find.text('WTB = Want To Buy'), findsNothing);
      expect(container.read(marketWtbTipProvider), isFalse);
    });

    testWidgets('asked for after Market is open, it still moves', (
      tester,
    ) async {
      final container = await open(tester, tip: false);
      expect(find.text('WTB = Want To Buy'), findsNothing);
      expect(container.read(bucketProvider), MarketBucket.all);

      container.read(marketWtbTipProvider.notifier).state = true;
      await tester.pumpAndSettle();
      expect(find.text('WTB = Want To Buy'), findsOneWidget);
      expect(container.read(bucketProvider), MarketBucket.buylist);
    });
  });
}
