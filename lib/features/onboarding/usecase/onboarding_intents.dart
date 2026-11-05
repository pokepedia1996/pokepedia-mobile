import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';

/// What a new user said they came to do, on onboarding's "Mau ngapain di
/// pokepedia?" step.
///
/// It unlocks and locks nothing. It only decides where "Mulai jelajah"
/// lands and which shortcuts Beranda offers. In list order, which is also
/// the order of the step's options: the first one picked is the landing.
enum OnboardingIntent {
  collect(
    'collect',
    'Catat & pantau koleksi',
    'Scan kartu, lihat nilai binder naik-turun',
    LucideIcons.archive,
  ),
  buy(
    'buy',
    'Cari & beli kartu',
    'Bandingkan harga dari ratusan penjual',
    LucideIcons.shoppingBag,
  ),
  sell(
    'sell',
    'Jual kartu',
    'Buka toko gratis, siap dalam 3 menit',
    LucideIcons.tag,
  ),
  bid(
    'bid',
    'Tawar kartu incaran',
    'Pasang bid (WTB), biar penjual yang datang',
    LucideIcons.handCoins,
  );

  const OnboardingIntent(this.raw, this.title, this.description, this.icon);

  /// The stored form — `onboarding_intents: ["collect","buy","sell","bid"]`.
  final String raw;
  final String title;
  final String description;
  final IconData icon;

  /// Where it lands. Tawar shares Market with Cari & beli; what sets it
  /// apart is the WTB tip it asks Market to show (see `marketWtbTipProvider`).
  String get route => switch (this) {
    OnboardingIntent.collect => Routes.portfolio,
    OnboardingIntent.buy || OnboardingIntent.bid => Routes.market,
    OnboardingIntent.sell => Routes.seller,
  };

  static OnboardingIntent? fromRaw(String raw) {
    for (final intent in values) {
      if (intent.raw == raw) return intent;
    }
    return null;
  }

  /// [picked] in the list's own order, whatever order they were tapped in.
  static List<OnboardingIntent> ordered(Iterable<OnboardingIntent> picked) => [
    for (final intent in values)
      if (picked.contains(intent)) intent,
  ];
}

/// The signed-in user's intents, and the Beranda shortcuts left from them.
@immutable
class OnboardingIntents {
  const OnboardingIntents({this.intents = const [], this.dismissed = const {}});

  /// Everything picked, in list order. Empty after "Lewati dulu".
  final List<OnboardingIntent> intents;

  /// Shortcuts closed from Beranda.
  final Set<OnboardingIntent> dismissed;

  /// The "Lanjutkan" cards: every pick but the first, which is where the
  /// user already landed, less the ones they closed.
  List<OnboardingIntent> get shortcuts => [
    for (final intent in intents.skip(1))
      if (!dismissed.contains(intent)) intent,
  ];
}

/// Kept on this device, per account, as a user preference: a shortcut, not
/// account data, and a shared phone must not show one person's picks to the
/// next.
class OnboardingIntentsNotifier extends Notifier<OnboardingIntents> {
  String? _userId;

  static String _intentsKey(String userId) => 'onboarding_intents:$userId';
  static String _dismissedKey(String userId) =>
      'onboarding_shortcuts_dismissed:$userId';

  @override
  OnboardingIntents build() {
    _userId = ref.watch(authProvider).valueOrNull?.id;
    final userId = _userId;
    if (userId != null) _load(userId);
    return const OnboardingIntents();
  }

  Future<void> _load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    // Signed out, or into another account, while this was reading.
    if (_userId != userId) return;
    List<OnboardingIntent> read(String key) => [
      for (final raw in prefs.getStringList(key) ?? const <String>[])
        ?OnboardingIntent.fromRaw(raw),
    ];
    state = OnboardingIntents(
      intents: OnboardingIntent.ordered(read(_intentsKey(userId))),
      dismissed: read(_dismissedKey(userId)).toSet(),
    );
  }

  /// Records what onboarding's second step picked — empty for "Lewati dulu".
  Future<void> save(Iterable<OnboardingIntent> picked) async {
    final userId = _userId;
    if (userId == null) return;
    state = OnboardingIntents(intents: OnboardingIntent.ordered(picked));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_intentsKey(userId), [
      for (final intent in state.intents) intent.raw,
    ]);
    await prefs.remove(_dismissedKey(userId));
  }

  /// Closes one "Lanjutkan" card on Beranda.
  Future<void> dismiss(OnboardingIntent intent) async {
    final userId = _userId;
    if (userId == null) return;
    state = OnboardingIntents(
      intents: state.intents,
      dismissed: {...state.dismissed, intent},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedKey(userId), [
      for (final intent in state.dismissed) intent.raw,
    ]);
  }
}

final onboardingIntentsProvider =
    NotifierProvider<OnboardingIntentsNotifier, OnboardingIntents>(
      OnboardingIntentsNotifier.new,
    );
