import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/my_bid.dart';
import 'package:pokepedia_mobile/features/proposals/repository/models/sent_proposal.dart';
import 'package:pokepedia_mobile/features/proposals/repository/proposals_repository.dart';
import 'package:pokepedia_mobile/features/proposals/usecase/proposals_notifier.dart';
import 'package:pokepedia_mobile/shared/models/card_condition.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Proposal feed reads a batch at a time instead of every bid and
/// proposal the account has ever had.

CardModel _card(int id) => CardModel(
  id: id,
  category: CardCategory.pokemon,
  nameId: 'Card $id',
  expansionCode: 'SV8',
  packSlug: 'sv8',
  collectorNumber: '$id/191',
  rarity: 'Rare',
);

/// A server holding [bids] open bids, one card each, and no sent proposals.
/// Records every slice asked for.
class _PagedRepository extends ProposalsRepository {
  _PagedRepository(this.bids)
    : super(SupabaseClient('http://localhost', 'anon-key'));

  final int bids;
  final bidRequests = <(int, int)>[];
  var fullWalks = 0;

  @override
  Future<({List<MyBidModel> rows, bool hasMore})> fetchMyBidsPage({
    required int offset,
    required int limit,
  }) async {
    bidRequests.add((offset, limit));
    final end = (offset + limit).clamp(0, bids);
    return (
      rows: [
        for (var i = offset; i < end; i++)
          MyBidModel(
            slug: 'bid-$i',
            card: _card(i),
            price: 1000,
            condition: CardCondition.nm,
            quantity: 1,
            qtyLocked: 0,
            // Newest first, as the server orders them.
            createdAt: DateTime(2026, 10, 28).subtract(Duration(minutes: i)),
          ),
      ],
      hasMore: end < bids,
    );
  }

  @override
  Future<({List<SentProposalModel> rows, bool hasMore})>
  fetchSentProposalsPage({required int offset, required int limit}) async =>
      (rows: const <SentProposalModel>[], hasMore: false);

  @override
  Future<List<MyBidModel>> fetchMyBids() async {
    fullWalks++;
    return const [];
  }
}

/// Synchronous, as the real one is once the session is restored.
class _SignedIn extends AuthNotifier {
  @override
  FutureOr<AppUser?> build() =>
      const AppUser(id: 'buyer-1', email: 'buyer@pokepedia.id');
}

ProviderContainer _container(_PagedRepository repo) {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_SignedIn.new),
      proposalsRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('opens on the first two pages, not the whole history', () async {
    final repo = _PagedRepository(450);
    final container = _container(repo);

    final feed = await container.read(proposalCardFeedProvider.future);

    expect(repo.bidRequests, [(0, 100)]);
    expect(repo.fullWalks, 0);
    expect(feed.groups, hasLength(100));
    expect(feed.hasMore, isTrue);
  });

  test('loading more fetches the next batch and keeps the first', () async {
    final repo = _PagedRepository(150);
    final container = _container(repo);
    await container.read(proposalCardFeedProvider.future);

    await container.read(proposalCardFeedProvider.notifier).loadMore();
    final feed = container.read(proposalCardFeedProvider).requireValue;

    expect(repo.bidRequests, [(0, 100), (100, 100)]);
    expect(feed.groups, hasLength(150));
    expect(feed.groups.first.card.id, 0, reason: 'newest stays on top');
    expect(feed.hasMore, isFalse);
  });

  test('with nothing more, loading more asks for nothing', () async {
    final repo = _PagedRepository(30);
    final container = _container(repo);
    final feed = await container.read(proposalCardFeedProvider.future);
    expect(feed.hasMore, isFalse);

    await container.read(proposalCardFeedProvider.notifier).loadMore();
    expect(repo.bidRequests, [(0, 100)]);
  });
}
