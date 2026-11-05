import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/catalog_language_provider.dart';
import 'package:pokepedia_mobile/features/search/usecase/quick_search_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// Records the language each suggestion lookup was scoped to.
class _FakeQuick implements QuickSearchRepository {
  final languages = <CardLanguage>[];

  @override
  Future<QuickSearchResults> search(
    String query, {
    required CardLanguage language,
  }) async {
    languages.add(language);
    return QuickSearchResults.empty;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  test('suggestions follow the catalog language, as web navbar does', () async {
    final fake = _FakeQuick();
    final container = ProviderContainer(
      overrides: [quickSearchRepositoryProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(quickSearchProvider('pikachu'), (_, __) {});
    addTearDown(sub.close);

    await container.read(quickSearchProvider('pikachu').future);
    container.read(catalogLanguageProvider.notifier).set(CardLanguage.en);
    await container.read(quickSearchProvider('pikachu').future);

    expect(fake.languages, [CardLanguage.id, CardLanguage.en]);
  });
}
