import 'package:supabase_flutter/supabase_flutter.dart';

/// The id of a user's primary collection — the row that replaced `user_cards`
/// when the web unified owned cards and lists into one `collections` model.
///
/// Every write that used to name a user now names a collection, so this sits
/// in front of the calls that only have a user id to go on. It's memoised
/// because the answer cannot change for the life of an account:
/// `collections.is_primary` is immutable, and `trg_freeze_collection_identity`
/// raises `is_primary_immutable` on any attempt to move it.
final _primaryIds = <String, String>{};

/// Resolves (and caches) the user's primary collection id.
///
/// Null means the account has no primary row at all — possible only for a
/// profile created before `handle_new_user` started minting one. Callers
/// surface it as an error rather than silently writing nowhere.
Future<String?> primaryCollectionId(
  SupabaseClient client,
  String userId,
) async {
  final cached = _primaryIds[userId];
  if (cached != null) return cached;
  final id =
      await client.rpc(
            'primary_collection_id',
            params: {'p_user_id': userId},
          )
          as String?;
  if (id != null && id.isNotEmpty) {
    _primaryIds[userId] = id;
    return id;
  }
  return null;
}

/// Forgets every memoised id. Called on sign-out so the next account resolves
/// its own rather than inheriting the previous session's.
void clearPrimaryCollectionCache() => _primaryIds.clear();
