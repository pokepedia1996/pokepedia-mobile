import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/app/tab_reselect.dart';

/// A reader who has scrolled a long way down a feed reaches for the tab they
/// are already on rather than flicking back up by hand. The signal is what
/// lets the page hear that tap, which navigation alone cannot deliver: the
/// branch pops to its root either way, and a page already at its root would
/// be handed nothing.
void main() {
  test('starts on nothing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(tabReselectProvider).index, -1);
  });

  test('a tap names the tab', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(tabReselectProvider.notifier).tapped(3);
    expect(container.read(tabReselectProvider).index, 3);
  });

  test('the same tab twice reads as two taps', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final seen = <int>[];
    container.listen(
      tabReselectProvider,
      (_, next) => seen.add(next.nonce),
      fireImmediately: false,
    );

    final notifier = container.read(tabReselectProvider.notifier);
    notifier.tapped(3);
    notifier.tapped(3);

    // Without the nonce the second would be equal to the first and nothing
    // would rebuild — the second tap would do nothing at all.
    expect(seen, hasLength(2));
    expect(seen.first, isNot(seen.last));
  });
}
