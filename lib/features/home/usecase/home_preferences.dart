import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether Beranda hides the portfolio's rupiah figures: the eye beside the
/// portfolio's name, for a phone shown to someone across a table.
///
/// Kept on the device, like the theme, so hiding them once keeps them
/// hidden. Read when Beranda first asks rather than in `main`: the card
/// draws its figures a moment later than the first frame anyway, while the
/// summary loads.
class HidePortfolioValuesNotifier extends Notifier<bool> {
  static const _key = 'pokepedia.home.hide-values.v1';

  /// Set once the reader taps the eye, so a slow read of the saved choice
  /// can't undo a tap that came before it landed.
  bool _touched = false;

  @override
  bool build() {
    unawaited(_restore());
    return false;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_key) ?? false;
      if (!_touched && saved != state) state = saved;
    } catch (_) {
      // Storage unreadable: show the figures.
    }
  }

  void toggle() {
    _touched = true;
    state = !state;
    unawaited(_persist(state));
  }

  Future<void> _persist(bool hidden) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, hidden);
    } catch (_) {
      // Not saved, but the figures are already hidden or shown.
    }
  }
}

final hidePortfolioValuesProvider =
    NotifierProvider<HidePortfolioValuesNotifier, bool>(
      HidePortfolioValuesNotifier.new,
    );

/// Whether the portfolio card is open on its chart and top holdings. Shut by
/// default, so Beranda opens on the figure and what's below it; a session
/// keeps it however it was left.
final portfolioCardExpandedProvider = StateProvider<bool>((ref) => false);
