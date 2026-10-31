import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/expansions/usecase/expansions_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';
import 'package:pokepedia_mobile/features/user/presentation/user_profile_page.dart';
import 'package:pokepedia_mobile/features/user/repository/models/profile_models.dart';
import 'package:pokepedia_mobile/features/user/usecase/user_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:pokepedia_mobile/shared/widgets/pikachu_loader.dart';

/// Pull-to-refresh keeps the profile and its shelf on screen while the new
/// data loads, then swaps it in — no loader in between.
const _owner = AppUser(id: 'owner', email: 'owner@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _owner;
}

CardModel _card(int id, String name) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: name,
  expansionCode: 'BS',
  packSlug: 'bs',
  collectorNumber: '00$id/102',
  rarity: 'Holo Rare',
  marketPrice: 100000,
  owned: 1,
);

void main() {
  testWidgets('a refresh shows the old shelf until the new one lands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final responses = <Future<List<CardModel>>>[
      Future.value([_card(1, 'Charizard')]),
    ];
    final second = Completer<List<CardModel>>();
    responses.add(second.future);
    var calls = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          userProfileProvider('figaro89').overrideWith(
            (ref) async => const PublicProfile(
              userId: 'owner',
              username: 'figaro89',
              contributionCount: 0,
            ),
          ),
          collectionVisibilityProvider(
            'figaro89',
          ).overrideWith((ref) async => true),
          userCollectionProvider(
            'figaro89',
          ).overrideWith((ref) => responses[calls++ < 1 ? 0 : 1]),
          userContributionsProvider('figaro89').overrideWith((ref) async => []),
          profileShopProvider('figaro89').overrideWith((ref) async => null),
          profileFollowStatsProvider(
            'figaro89',
          ).overrideWith((ref) async => null),
          followedShopsProvider.overrideWith((ref) async => const []),
          seriesGroupsProvider.overrideWith((ref) async => []),
          wishlistedIdsProvider.overrideWith((ref) async => <int>{}),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const UserProfilePage(username: 'figaro89'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Charizard'), findsOneWidget);

    await tester.fling(find.text('Portofolio'), const Offset(0, 600), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The refetch is in flight.
    expect(calls, 2);
    // Still loading: the old shelf stays, no loader replaces it.
    expect(find.text('Charizard'), findsOneWidget);
    expect(find.byType(PikachuLoader), findsNothing);

    second.complete([_card(2, 'Blastoise')]);
    await tester.pumpAndSettle();
    expect(find.text('Blastoise'), findsOneWidget);
    expect(find.text('Charizard'), findsNothing);
  });
}
