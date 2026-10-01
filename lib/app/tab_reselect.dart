import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A tap on the nav tab that is already open.
///
/// Every other app with a feed does the same thing with that tap — back to
/// the top, and fetch what has appeared since — and a reader who has scrolled
/// a long way down reaches for it rather than flicking back up by hand.
///
/// Carries [nonce] because the interesting part is that it happened, not what
/// it says: tapping Market twice has to read as two separate events, and a
/// value equal to the last one would not rebuild anything.
class TabReselectSignal {
  const TabReselectSignal({required this.index, required this.nonce});

  /// The tab, as [AppBottomNav.tabPaths] orders them.
  final int index;

  final int nonce;

  static const none = TabReselectSignal(index: -1, nonce: 0);
}

class TabReselect extends Notifier<TabReselectSignal> {
  @override
  TabReselectSignal build() => TabReselectSignal.none;

  void tapped(int index) =>
      state = TabReselectSignal(index: index, nonce: state.nonce + 1);
}

final tabReselectProvider = NotifierProvider<TabReselect, TabReselectSignal>(
  TabReselect.new,
);
