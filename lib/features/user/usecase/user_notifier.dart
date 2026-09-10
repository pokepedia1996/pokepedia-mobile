import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/models/store_model.dart';
import '../../market/usecase/market_notifier.dart';
import '../repository/models/profile_models.dart';
import '../repository/user_repository.dart';

final userRepositoryProvider = Provider((ref) {
  return UserRepository(ref.read(supabaseClientProvider));
});

final usersSearchQueryProvider = StateProvider<String>((ref) => '');

/// Debounced by 300ms like web's `useEffect` timer, so typing doesn't fire
/// a query per keystroke.
final usersSearchProvider = FutureProvider<List<UserSearchResult>>((ref) async {
  final query = ref.watch(usersSearchQueryProvider);
  if (query.trim().length < 2) return const [];

  final debounce = Completer<void>();
  final timer = Timer(
    const Duration(milliseconds: 300),
    () => debounce.complete(),
  );
  // Left hanging rather than completed on dispose: resuming after the
  // provider is gone would read from a disposed ref and throw.
  ref.onDispose(timer.cancel);
  await debounce.future;

  return ref.read(userRepositoryProvider).searchUsers(query);
});

/// The profile behind `/user/{username}`, re-fetched when the viewer signs
/// in or out (the WhatsApp contact and owner-only views depend on it).
final userProfileProvider = FutureProvider.family<PublicProfile?, String>((
  ref,
  username,
) async {
  final viewer = ref.watch(authProvider).valueOrNull;
  final repository = ref.read(userRepositoryProvider);
  final profile = await repository.fetchPublicProfile(username);
  if (profile == null) return null;
  if (viewer == null) return profile;

  final whatsapp = await repository.fetchSellerContact(profile.userId);
  return whatsapp == null
      ? profile
      : profile.copyWith(socialWhatsapp: () => whatsapp);
});

/// The profile owner's collection. Guests and non-owners only get it when
/// the profile is public, matching `canView` on the web.
final userCollectionProvider = FutureProvider.family<List<CardModel>, String>((
  ref,
  username,
) async {
  final profile = await ref.watch(userProfileProvider(username).future);
  if (profile == null) return const [];
  final viewer = ref.watch(authProvider).valueOrNull;
  final isOwner = viewer?.id == profile.userId;
  return ref
      .read(userRepositoryProvider)
      .fetchPublicCollection(
        profile.userId,
        canView: isOwner || profile.isCollectionPublic,
      );
});

final userContributionsProvider =
    FutureProvider.family<List<ContributionCardEntry>, String>((
      ref,
      username,
    ) async {
      final profile = await ref.watch(userProfileProvider(username).future);
      if (profile == null || profile.contributionCount == 0) return const [];
      return ref
          .read(userRepositoryProvider)
          .fetchContributions(profile.userId);
    });

/// Shops the signed-in user follows — the `/account/following` list.
/// Whether the signed-in user follows a shop, and the two writes that
/// change it.
///
/// Keyed by the shop's `user_id` rather than its handle: that's what
/// `shop_follows` stores and what the RPCs take.
class FollowController {
  const FollowController(this._ref);

  final Ref _ref;

  Future<String?> setFollowing({
    required String shopUserId,
    required bool following,
  }) async {
    final repository = _ref.read(userRepositoryProvider);
    final error = following
        ? await repository.followShop(shopUserId)
        : await repository.unfollowShop(shopUserId);
    if (error == null) {
      // The Akun → "Toko yang Diikuti" list and the storefront's own
      // follower count both read from the server.
      _ref.invalidate(followedShopsProvider);
      _ref.invalidate(isFollowingShopProvider(shopUserId));
    }
    return error;
  }
}

final followControllerProvider = Provider(FollowController.new);

/// The server's answer for one shop. The storefront seeds its button from
/// the storefront row's `is_following`, and falls back to this after a
/// write so a reopened page doesn't disagree with the database.
final isFollowingShopProvider = FutureProvider.family<bool, String>((
  ref,
  shopUserId,
) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return false;
  final result = await ref
      .read(supabaseClientProvider)
      .rpc('is_following_shop', params: {'p_shop_user_id': shopUserId});
  return result == true;
});

/// The shop behind a profile, when the user runs one.
///
/// Where the follower count comes from: it is kept on
/// `seller_profiles.followers_count` by a trigger, and only a shop can be
/// followed at all — `follow_shop` inserts nothing for a user without an
/// active seller profile. So a profile with no shop has no followers and no
/// follow button, which is the database's answer rather than a UI choice.
final profileShopProvider = FutureProvider.family<StoreModel?, String>((
  ref,
  username,
) async {
  // The storefront RPC pair takes a slug first and a username second, which
  // is exactly the lookup this has: a profile is addressed by username.
  return ref.read(marketRepositoryProvider).fetchStore(username);
});

/// Follower and following counts for a profile, from
/// `get_profile_follow_stats`.
///
/// Null while it loads, and null for good on a project where the function
/// hasn't been applied — the page falls back to the shop row's follower
/// count there, which is all a client can otherwise see.
final profileFollowStatsProvider =
    FutureProvider.family<
      ({String userId, int followers, int following})?,
      String
    >((ref, username) async {
      return ref.read(userRepositoryProvider).fetchFollowStats(username);
    });

/// How many shops the signed-in user follows.
///
/// Only ever their own number: `shop_follows` is select-own under RLS, so
/// nobody can count what someone else follows without a definer function.
final followingCountProvider = Provider<int>((ref) {
  return ref.watch(followedShopsProvider).valueOrNull?.length ?? 0;
});

final followedShopsProvider = FutureProvider<List<FollowedShop>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return const [];
  return ref.read(userRepositoryProvider).fetchFollowedShops();
});

/// The signed-in user's own private contact row, behind the settings screen's
/// phone section.
final privateProfileProvider = FutureProvider<PrivateProfile>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return const PrivateProfile();
  return ref.read(userRepositoryProvider).fetchPrivateProfile(user.id);
});

/// The signed-in user's own profile row, so settings can seed its fields
/// (bio, socials, privacy toggles) from live data.
final myProfileProvider = FutureProvider<PublicProfile?>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  final username = user?.username;
  if (user == null || username == null) return null;
  return ref.read(userRepositoryProvider).fetchPublicProfile(username);
});
