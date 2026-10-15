import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/pokepedia_api.dart';
import 'models/blocked_user.dart';
import 'models/report_reason.dart';

/// Data access for reporting and blocking other users. Ports
/// `features/moderation/api/moderation.client.ts` and the routes behind it.
///
/// Reports go through web's `/api/user-reports`, as the browser's do: the
/// route rate-limits them and emails the admins on a new one, neither of
/// which the RPC alone does. Blocking is a thin wrapper around RPCs granted
/// to `authenticated`, so those are called directly — the same split
/// `MarketRepository.reportListing` makes.
class ModerationRepository {
  ModerationRepository(this._client, this._api);

  final SupabaseClient _client;
  final PokepediaApi _api;

  Future<void> reportUser({
    required String userId,
    required String reason,
    required UserReportContext context,
    String? details,
    String? roomSlug,
  }) async {
    final trimmed = details?.trim();
    final hasDetails = trimmed != null && trimmed.isNotEmpty;
    try {
      await _api.post('/api/user-reports', {
        'userId': userId,
        'reason': reason,
        if (hasDetails) 'details': trimmed,
        'context': context.value,
        if (context == UserReportContext.chat && roomSlug != null)
          'roomSlug': roomSlug,
      });
    } on ApiException catch (e) {
      // A web deploy without the route yet: file it through the RPC, which
      // still alerts the admins in-app. Anything else is the route's answer.
      if (e.statusCode != 404) {
        throw ModerationException(
          e.message == ApiException.genericMessage
              ? 'Gagal mengirim laporan'
              : e.message,
        );
      }
      await _rpc('report_user', {
        'p_reported_user_id': userId,
        'p_reason': reason,
        'p_details': hasDetails ? trimmed : null,
        'p_context': context.value,
        'p_room_slug': context == UserReportContext.chat ? roomSlug : null,
      }, fallback: 'Gagal mengirim laporan');
    }
  }

  Future<void> blockUser(String userId) => _rpc('block_user', {
    'p_user_id': userId,
  }, fallback: 'Gagal memblokir pengguna');

  Future<void> unblockUser(String userId) => _rpc('unblock_user', {
    'p_user_id': userId,
  }, fallback: 'Gagal membuka blokir');

  Future<List<BlockedUser>> fetchBlockedUsers() async {
    final rows = await _client.rpc('get_blocked_users') as List;
    return [
      for (final row in rows.whereType<Map<String, dynamic>>())
        if (row['user_id'] is String) BlockedUser.fromRow(row),
    ];
  }

  /// Everyone on either side of a block with the caller — what web's
  /// `blocked-ids.ts` filters direct table reads by.
  Future<Set<String>> fetchBlockedPairIds() async {
    final ids = await _client.rpc('get_blocked_pair_ids');
    if (ids is! List) return const {};
    return ids.whereType<String>().toSet();
  }

  /// Whether the caller blocked whoever [handle] names — a username or a
  /// store slug, passed as both like web's store page does.
  Future<BlockStatus> blockStatus(String handle) async {
    try {
      final data = await _client.rpc(
        'get_block_status',
        params: {'p_username': handle, 'p_store_slug': handle},
      );
      return BlockStatus.fromJson(data);
    } catch (e) {
      // Signed out or unreachable: treat as not blocked, as web does.
      debugPrint('[moderation] get_block_status failed: $e');
      return const BlockStatus(blockedByMe: false);
    }
  }

  /// `chat_room_blocked_for_me` — true when either party of [roomId] has
  /// blocked the other. Errors read as not blocked, as web's block-state.
  Future<bool> isRoomBlocked(int roomId) async {
    try {
      final blocked = await _client.rpc(
        'chat_room_blocked_for_me',
        params: {'p_room_id': roomId},
      );
      return blocked == true;
    } catch (e) {
      debugPrint('[moderation] chat_room_blocked_for_me failed: $e');
      return false;
    }
  }

  Future<void> _rpc(
    String fn,
    Map<String, dynamic> params, {
    required String fallback,
  }) async {
    try {
      await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw ModerationException(moderationErrorMessage(e.message, fallback));
    }
  }
}

/// Ports `features/moderation/server/rpc-errors.ts`: the RPCs raise bare
/// tokens (some prefixed `forbidden:`), matched as substrings like web.
String moderationErrorMessage(String raw, String fallback) {
  if (raw.contains('self_report')) return 'Tidak bisa melaporkan diri sendiri.';
  if (raw.contains('self_block')) return 'Tidak bisa memblokir diri sendiri.';
  if (raw.contains('invalid_reason')) return 'Alasan laporan tidak valid.';
  if (raw.contains('invalid_context')) return 'Laporan tidak valid.';
  if (raw.contains('not_found')) return 'Pengguna tidak ditemukan.';
  if (raw.contains('no_session')) return 'Silakan login terlebih dahulu.';
  return fallback;
}

/// A refused report or block, already worded for the user. An
/// [ApiException] so `userFacingError` shows the sentence.
class ModerationException extends ApiException {
  const ModerationException(super.message);
}
