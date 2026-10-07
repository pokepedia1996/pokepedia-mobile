import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/image_url.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/utils/card_pricing.dart';
import '../../../shared/utils/paged_rows.dart';
import '../../../shared/utils/primary_collection.dart';
import '../utils/delete_account_errors.dart';
import 'models/profile_models.dart';
import '../../../core/errors/user_message.dart';

/// The owner's own `collection_cards` → `cards` embed.
///
/// Mirrors the `cards` object `get_public_collection_cards` builds for
/// visitors, so both paths hand [CardModel.fromRow] the same shape. The
/// `expansions` join the old `user_cards` select carried is gone: the mapper
/// never read it, so it was a wasted join on every profile open.
const _collectionColumns = '''
card_id,
quantity,
variant_key,
cards!inner (
  id,
  name_id,
  image_url,
  collector_number,
  rarity,
  category,
  expansion_code,
  language,
  illustrator,
  regulation_mark,
  variant,
  details
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
  /// The owner reads their own primary collection straight off the table —
  /// RLS already scopes it to them, and it stays visible even while private.
  /// Everyone else goes through `get_public_collection_cards`, which gates on
  /// `collections.is_public` server-side and honours `show_quantity`; that
  /// replaces the account-wide `profiles.is_collection_public` flag the
  /// unification dropped, so visibility is now per collection.
  Future<List<CardModel>> fetchPublicCollection(
    String username, {
    required String userId,
    required bool isOwner,
  }) async {
    final rows = isOwner
        ? await _ownCollectionRows(userId)
        : await _publicCollectionRows(username);

    final cards = <CardModel>[];
    for (final row in rows) {
      final joined = row['cards'] as Map<String, dynamic>?;
      if (joined == null) continue;
      // The row carries the id; the join carries everything else the catalog
      // model reads, and defaults cover what it doesn't select.
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

  Future<List<Map<String, dynamic>>> _ownCollectionRows(String userId) async {
    final collectionId = await primaryCollectionId(_client, userId);
    if (collectionId == null) return const [];
    return pagedRows(
      (from, to) => _client
          .from('collection_cards')
          .select(_collectionColumns)
          .eq('collection_id', collectionId)
          .gt('quantity', 0)
          .order('card_id', ascending: true)
          .order('id', ascending: true)
          .range(from, to),
    );
  }

  /// `p_slug` null means "whichever collection is primary" — the same
  /// default the web's `/u/<username>` route uses.
  Future<List<Map<String, dynamic>>> _publicCollectionRows(
    String username,
  ) async {
    final rows = await _client.rpc(
      'get_public_collection_cards',
      params: {'p_username': username, 'p_slug': null},
    );
    if (rows is! List) return const [];
    return rows.cast<Map<String, dynamic>>();
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
      return userFacingError(e);
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
      return userFacingError(e);
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
  ///
  /// Null means the question could not be asked, which is not the same answer
  /// as "taken" and callers must not render it as one. Bounded because an
  /// unanswered request otherwise leaves the caller's spinner turning
  /// forever: the onboarding modal cannot be dismissed, so a stalled check
  /// there locks the whole app.
  Future<bool?> isUsernameAvailable(String username) async {
    try {
      final value = await _client
          .rpc(
            'is_username_available',
            params: {'requested_username': username},
          )
          .timeout(const Duration(seconds: 10));
      return value as bool?;
    } catch (error, stack) {
      // Swallowed for the caller, but not silently: this used to discard the
      // reason entirely, which made a failing check indistinguishable from a
      // taken name.
      debugPrint('is_username_available failed for "$username": $error');
      debugPrintStack(stackTrace: stack, maxFrames: 6);
      return null;
    }
  }

  /// Web's `MAX_FILE_SIZE` for an avatar.
  static const maxAvatarBytes = 2 * 1024 * 1024;

  /// Replaces the signed-in user's avatar, porting `handleAvatarUpload`.
  ///
  /// Written straight to Storage from the client, as web does: the `avatars`
  /// bucket's insert/update policies are keyed on
  /// `(storage.foldername(name))[1] = auth.uid()`, which is exactly the path
  /// built here, so no server route is involved.
  ///
  /// Returns an error message, or null on success.
  Future<String?> uploadAvatar({
    required Uint8List bytes,
    required String extension,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 'Sesi berakhir. Masuk lagi untuk mengubah foto.';
    if (bytes.lengthInBytes > maxAvatarBytes) {
      return 'Ukuran file maksimal 2MB';
    }

    final bucket = _client.storage.from('avatars');
    final path = '$userId/avatar.$extension';
    try {
      // Clear the folder first, as web does: the name carries the old
      // extension, so a .png would otherwise outlive the .jpg replacing it
      // and keep being served.
      final existing = await bucket.list(path: userId);
      if (existing.isNotEmpty) {
        await bucket.remove([for (final f in existing) '$userId/${f.name}']);
      }

      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          upsert: true,
          contentType: extension == 'png' ? 'image/png' : 'image/jpeg',
        ),
      );

      // The cache-buster is web's too — the path never changes, so without it
      // the CDN keeps handing back the previous face.
      final url =
          '${bucket.getPublicUrl(path)}'
          '?t=${DateTime.now().millisecondsSinceEpoch}';

      await _client
          .from('profiles')
          .update({'avatar_url': url})
          .eq('id', userId);
      return null;
    } on StorageException catch (e) {
      return userFacingError(e);
    } on PostgrestException catch (e) {
      return userFacingError(e);
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
      return userFacingError(e);
    }
  }

  /// The owner's primary-collection visibility settings — what the two
  /// privacy switches read. Own-row under RLS, so no server route.
  Future<CollectionVisibility?> fetchCollectionVisibility(String userId) async {
    final collectionId = await primaryCollectionId(_client, userId);
    if (collectionId == null) return null;
    final row = await _client
        .from('collections')
        .select('id, is_public, show_quantity')
        .eq('id', collectionId)
        .maybeSingle();
    return row == null ? null : CollectionVisibility.fromRow(row);
  }

  /// Writes one of those switches. Takes the same `{column: value}` shape as
  /// [updateProfile] did when these lived on `profiles`, so the screens that
  /// call it only had to change which method they name — the columns are
  /// `is_public` and `show_quantity` now.
  Future<String?> updateCollectionVisibility(
    String userId,
    Map<String, dynamic> values,
  ) async {
    final collectionId = await primaryCollectionId(_client, userId);
    if (collectionId == null) return 'Koleksi utama tidak ditemukan';
    try {
      await _client.from('collections').update(values).eq('id', collectionId);
      return null;
    } on PostgrestException catch (e) {
      return userFacingError(e);
    }
  }

  /// Whether a stranger can see this user's primary collection.
  ///
  /// `get_public_collection` returns the row only when it is public, so a
  /// null answer is the "this collection is private" signal the profile page
  /// used to get from `profiles.is_collection_public`.
  Future<bool> isCollectionPublic(String username) async {
    final row = await _client.rpc(
      'get_public_collection',
      params: {'p_username': username, 'p_slug': null},
    );
    return row is Map && row['id'] != null;
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
      return userFacingError(e);
    }
  }

  /// Deletes (anonymises) the caller's account through `delete_my_account`,
  /// the RPC behind web's `DeleteAccountSection`. Returns null on success, or
  /// the Indonesian reason it was refused.
  Future<String?> deleteMyAccount() async {
    try {
      await _client.rpc('delete_my_account');
      return null;
    } on PostgrestException catch (e) {
      if (!isDeleteAccountRefusal(e.message)) {
        debugPrint('[delete-account] delete_my_account failed: ${e.message}');
      }
      return translateDeleteAccountError(e.message);
    } catch (e) {
      debugPrint('[delete-account] delete_my_account failed: $e');
      return translateDeleteAccountError('');
    }
  }
}

String _escapeLike(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
