import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/image_url.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/utils/card_pricing.dart';
import 'models/profile_models.dart';

/// The `user_cards` → `cards` → `expansions` embed web's
/// `fetchPublicCollection` selects, plus the pack image (the web reads that
/// from its client-side pack cache, which the app doesn't have here).
const _collectionColumns = '''
card_id,
quantity,
variant_key,
cards!inner (
  name_id,
  image_url,
  collector_number,
  rarity,
  category,
  expansion_code,
  language,
  expansions!inner ( name_id, total_cards, released_at, pack_image_url )
)
''';

const _contributionColumns = '''
card_id,
created_at,
cards!inner ( name_id, image_url, collector_number, expansion_code )
''';

/// Data access for the profile/account screens, backed by Supabase. Ports
/// `pokepedia-web/lib/user/profile.ts` plus the profile mutations
/// `app/settings/page.tsx` performs inline.
class UserRepository {
  UserRepository(this._client);

  final SupabaseClient _client;

  /// Ports `fetchPublicProfile` — the `get_public_profile` RPC, which
  /// exposes only what a visitor is allowed to see.
  Future<PublicProfile?> fetchPublicProfile(String username) async {
    final rows = await _client.rpc(
      'get_public_profile',
      params: {'p_username': username},
    );
    final list = rows as List?;
    if (list == null || list.isEmpty) return null;
    return PublicProfile.fromRow(list.first as Map<String, dynamic>);
  }

  /// The seller's WhatsApp number, readable only by signed-in viewers
  /// (`get_seller_contact`). Returns null when unset or not permitted.
  Future<String?> fetchSellerContact(String userId) async {
    try {
      final value = await _client.rpc(
        'get_seller_contact',
        params: {'p_seller_id': userId},
      );
      final phone = value as String?;
      return (phone == null || phone.isEmpty) ? null : phone;
    } catch (_) {
      return null;
    }
  }

  /// Ports `fetchPublicCollection` — every card the user owns, priced, most
  /// valuable first. [canView] mirrors the web's guard: the owner always
  /// sees their own collection, everyone else only a public one.
  ///
  /// Flat rather than grouped by expansion: the profile shows a portfolio
  /// now, the same grid the Koleksi page draws, and a portfolio is a pile of
  /// cards with a value rather than a shelf per set.
  Future<List<CardModel>> fetchPublicCollection(
    String userId, {
    required bool canView,
  }) async {
    if (!canView) return const [];

    final rows = await _client
        .from('user_cards')
        .select(_collectionColumns)
        .eq('user_id', userId)
        .gt('quantity', 0)
        .order('card_id', ascending: true);

    final cards = <CardModel>[];
    for (final row in rows) {
      final joined = row['cards'] as Map<String, dynamic>?;
      if (joined == null) continue;
      // `user_cards` carries the id; the join carries everything else the
      // catalog model reads, and defaults cover what it doesn't select.
      cards.add(
        CardModel.fromRow({
          ...joined,
          'id': (row['card_id'] as num).toInt(),
        }).copyWith(owned: (row['quantity'] as num?)?.toInt() ?? 0),
      );
    }

    return sortCards(
      await priceCards(_client, cards),
      CardSortOption.priceDesc,
    );
  }

  /// Ports `fetchPublicContributionsAsList` — approved image submissions,
  /// newest first, one row per card.
  Future<List<ContributionCardEntry>> fetchContributions(String userId) async {
    final rows = await _client
        .from('card_image_submissions')
        .select(_contributionColumns)
        .eq('user_id', userId)
        .eq('status', 'approved')
        .order('created_at', ascending: false);

    final seen = <int>{};
    final out = <ContributionCardEntry>[];
    for (final row in rows) {
      final card = row['cards'] as Map<String, dynamic>?;
      if (card == null) continue;
      final cardId = (row['card_id'] as num).toInt();
      if (!seen.add(cardId)) continue;
      out.add(
        ContributionCardEntry(
          cardId: cardId,
          name: card['name_id'] as String? ?? '',
          number: card['collector_number'] as String? ?? '',
          expansionCode: card['expansion_code'] as String? ?? '',
          imageUrl: proxyImageUrl(card['image_url'] as String?),
        ),
      );
    }
    return out;
  }

  /// Ports `searchUsers` — an `ilike` over usernames, then the batched
  /// `get_contribution_counts` RPC for each result's contributor badge.
  Future<List<UserSearchResult>> searchUsers(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final profiles = await _client
        .from('profiles')
        .select('id, username, avatar_url')
        .ilike('username', '%${_escapeLike(trimmed)}%')
        .not('username', 'is', null)
        .order('username')
        .limit(20);

    if (profiles.isEmpty) return const [];

    final ids = profiles.map((p) => p['id'] as String).toList();
    var countById = <String, int>{};
    try {
      final counts = await _client.rpc(
        'get_contribution_counts',
        params: {'p_user_ids': ids},
      );
      countById = {
        for (final row in (counts as List).whereType<Map<String, dynamic>>())
          row['user_id'] as String:
              (row['contribution_count'] as num?)?.toInt() ?? 0,
      };
    } catch (_) {
      // Contribution counts are decorative — a failure here shouldn't drop
      // the whole result list.
    }

    return profiles
        .map(
          (p) => UserSearchResult(
            username: p['username'] as String? ?? '',
            avatarUrl: proxyImageUrl(p['avatar_url'] as String?),
            contributionCount: countById[p['id'] as String] ?? 0,
          ),
        )
        .toList();
  }

  /// Both follow counts for one profile — `get_profile_follow_stats`.
  ///
  /// Null when the function isn't deployed yet (PostgREST answers PGRST202)
  /// or the username matches nobody, which the caller reads as "fall back to
  /// what can be counted client-side".
  Future<({String userId, int followers, int following})?> fetchFollowStats(
    String username,
  ) async {
    try {
      final rows = await _client.rpc(
        'get_profile_follow_stats',
        params: {'p_username': username},
      );
      final list = rows as List?;
      if (list == null || list.isEmpty) return null;
      final row = list.first as Map<String, dynamic>;
      final id = row['user_id'] as String?;
      if (id == null) return null;
      return (
        userId: id,
        followers: (row['followers_count'] as num?)?.toInt() ?? 0,
        following: (row['following_count'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Follows a shop. `follow_shop` is idempotent server-side and refuses a
  /// self-follow, so this doesn't have to check either.
  Future<String?> followShop(String shopUserId) async {
    try {
      await _client.rpc('follow_shop', params: {'p_shop_user_id': shopUserId});
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  Future<String?> unfollowShop(String shopUserId) async {
    try {
      await _client.rpc(
        'unfollow_shop',
        params: {'p_shop_user_id': shopUserId},
      );
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Ports `app/account/following/page.tsx`' `get_followed_shops` call.
  Future<List<FollowedShop>> fetchFollowedShops() async {
    final rows = await _client.rpc(
      'get_followed_shops',
      params: {'p_offset': 0, 'p_limit': 100},
    );
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(FollowedShop.fromRow)
        .whereType<FollowedShop>()
        .toList();
  }

  /// The signed-in user's own contact row, for the settings screen.
  Future<PrivateProfile> fetchPrivateProfile(String userId) async {
    try {
      final row = await _client
          .from('profiles_private')
          .select('phone, phone_verified_at, social_whatsapp')
          .eq('id', userId)
          .maybeSingle();
      return PrivateProfile.fromRow(row);
    } catch (_) {
      return const PrivateProfile();
    }
  }

  /// `is_username_available` — the same RPC the web's settings form debounces.
  Future<bool?> isUsernameAvailable(String username) async {
    try {
      final value = await _client.rpc(
        'is_username_available',
        params: {'requested_username': username},
      );
      return value as bool?;
    } catch (_) {
      return null;
    }
  }

  /// Updates public `profiles` columns, returning an error message on
  /// failure and null on success (the convention the app's controllers use).
  Future<String?> updateProfile(
    String userId,
    Map<String, dynamic> values,
  ) async {
    try {
      await _client.from('profiles').update(values).eq('id', userId);
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }

  /// Writes the WhatsApp number onto `profiles_private` through the same
  /// self-service RPC the web uses (the table itself isn't writable by RLS).
  Future<String?> updateWhatsapp(String whatsapp) async {
    try {
      final result = await _client.rpc(
        'update_profile_private_self',
        params: {'p_social_whatsapp': whatsapp},
      );
      if (result is Map<String, dynamic>) {
        return result['error'] as String?;
      }
      return null;
    } on PostgrestException catch (e) {
      return e.message;
    }
  }
}

String _escapeLike(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
