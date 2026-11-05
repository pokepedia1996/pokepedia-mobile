import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/collection_page_notifier.dart';
import 'package:pokepedia_mobile/features/user/usecase/user_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// Adding a card to the portfolio refreshes the owner's profile shelf too —
/// it is kept alive per username, and went on showing the old collection.
void main() {
  test('collection writes refetch the profile portfolio', () async {
    var fetches = 0;
    final container = ProviderContainer(
      overrides: [
        userCollectionProvider.overrideWith((ref, username) async {
          fetches++;
          return const <CardModel>[];
        }),
      ],
    );
    addTearDown(container.dispose);

    container.listen(userCollectionProvider('pudyasta'), (_, __) {});
    await container.read(userCollectionProvider('pudyasta').future);
    expect(fetches, 1);

    invalidateCollectionViews(container.invalidate);
    await container.read(userCollectionProvider('pudyasta').future);
    expect(fetches, 2);
  });
}
