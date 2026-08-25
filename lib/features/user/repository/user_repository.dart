import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/image_url.dart';
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

  /// Ports `fetchPublicCollection` — every owned card grouped by expansion,
  /// newest expansion first. [canView] mirrors the web's guard: the owner
  /// always sees their own collection, everyone else only a public one.
  Future<List<CollectionExpansionGroup>> fetchPublicCollection(
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

    final groups = <String, CollectionExpansionGroup>{};
    final cardsByKey = <String, List<CollectionCardEntry>>{};

    for (final row in rows) {
      final card = row['cards'] as Map<String, dynamic>?;
      if (card == null) continue;
      final expansion = card['expansions'] as Map<String, dynamic>?;
      final code = card['expansion_code'] as String? ?? '';
      final language = card['language'] as String? ?? 'id';
      final key = '$code-$language';

      groups.putIfAbsent(
        key,
        () => CollectionExpansionGroup(
          expansionCode: code,
          expansionName: expansion?['name_id'] as String? ?? code,
          language: language,
          totalCards: (expansion?['total_cards'] as num?)?.toInt() ?? 0,
          packImage: proxyImageUrl(expansion?['pack_image_url'] as String?),
          releasedAt: expansion?['released_at'] as String? ?? '',
          cards: const [],
        ),
      );

      cardsByKey.putIfAbsent(key, () => []).add(
        CollectionCardEntry(
          cardId: (row['card_id'] as num).toInt(),
          name: card['name_id'] as String? ?? '',
          number: card['collector_number'] as String? ?? '',
          quantity: (row['quantity'] as num?)?.toInt() ?? 0,
          imageUrl: proxyImageUrl(card['image_url'] as String?),
          rarity: card['rarity'] as String?,
          variantKey: row['variant_key'] as String?,
        ),
      );
    }

    final result = <CollectionExpansionGroup>[];
    for (final entry in groups.entries) {
      final cards = cardsByKey[entry.key] ?? const <CollectionCardEntry>[];
      cards.sort(_compareCollectionCards);
      result.add(entry.value.withCards(cards));
    }
    result.sort((a, b) => b.releasedAt.compareTo(a.releasedAt));
    return result;
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

/// Collector number order, with the base print ahead of its variants —
/// mirrors the comparator in `fetchPublicCollection`.
int _compareCollectionCards(CollectionCardEntry a, CollectionCardEntry b) {
  final numCmp = _compareNumeric(a.number, b.number);
  if (numCmp != 0) return numCmp;
  if (a.variantKey == null && b.variantKey != null) return -1;
  if (a.variantKey != null && b.variantKey == null) return 1;
  return (a.variantKey ?? '').compareTo(b.variantKey ?? '');
}

/// `localeCompare(..., { numeric: true })` — "9" before "10".
int _compareNumeric(String a, String b) {
  final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
  final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), ''));
  if (numA != null && numB != null && numA != numB) return numA.compareTo(numB);
  return a.compareTo(b);
}
