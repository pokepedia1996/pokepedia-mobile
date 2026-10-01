import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:pokepedia_mobile/features/search/usecase/recent_searches.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The same card gets looked up repeatedly — a set number, a print someone is
/// hunting across sellers — so the field remembers what was searched rather
/// than making it be retyped.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> container() async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(recentSearchesProvider);
    // The first read kicks off the load from disk.
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test('newest first', () async {
    final c = await container();
    final recents = c.read(recentSearchesProvider.notifier);

    await recents.record('pikachu 130');
    await recents.record('jirachi ex');

    expect(c.read(recentSearchesProvider), ['jirachi ex', 'pikachu 130']);
  });

  test(
    'searching the same thing again moves it, it does not repeat it',
    () async {
      final c = await container();
      final recents = c.read(recentSearchesProvider.notifier);

      await recents.record('pikachu 130');
      await recents.record('jirachi ex');
      await recents.record('PIKACHU 130');

      // Matched without regard to case: it is the same search.
      expect(c.read(recentSearchesProvider), ['PIKACHU 130', 'jirachi ex']);
    },
  );

  test('the list stays short enough to glance at', () async {
    final c = await container();
    final recents = c.read(recentSearchesProvider.notifier);

    for (var i = 0; i < RecentSearches.maxEntries + 4; i++) {
      await recents.record('search $i');
    }

    expect(
      c.read(recentSearchesProvider),
      hasLength(RecentSearches.maxEntries),
    );
    // The oldest fell off, not the newest.
    expect(c.read(recentSearchesProvider).first, 'search 11');
  });

  test('blank searches are not remembered', () async {
    final c = await container();
    await c.read(recentSearchesProvider.notifier).record('   ');
    expect(c.read(recentSearchesProvider), isEmpty);
  });

  test('one can be removed, or all of them', () async {
    final c = await container();
    final recents = c.read(recentSearchesProvider.notifier);

    await recents.record('a');
    await recents.record('b');
    await recents.remove('a');
    expect(c.read(recentSearchesProvider), ['b']);

    await recents.clear();
    expect(c.read(recentSearchesProvider), isEmpty);
  });

  test('they survive the app being closed', () async {
    final first = await container();
    await first.read(recentSearchesProvider.notifier).record('dragonite ex');

    // A fresh container reads the same store a relaunch would.
    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.read(recentSearchesProvider);
    await Future<void>.delayed(Duration.zero);

    expect(second.read(recentSearchesProvider), ['dragonite ex']);
  });

  group('the scopes', () {
    test('each one goes somewhere different', () {
      expect(Routes.marketSearch('pika'), '/market?q=pika');
      expect(Routes.marketStoreSearch('pika'), '/market?tab=stores&q=pika');
      expect(Routes.searchResults('pika'), '/search?q=pika');
    });

    test('a query with spaces survives the trip', () {
      // `+` for a space, which is what a query component takes — and what
      // `searchResults` has always emitted.
      expect(Routes.marketSearch('pikachu 130'), '/market?q=pikachu+130');
      // And it comes back out the other side intact.
      expect(
        Uri.parse(Routes.marketSearch('pikachu 130')).queryParameters['q'],
        'pikachu 130',
      );
    });
  });
}
