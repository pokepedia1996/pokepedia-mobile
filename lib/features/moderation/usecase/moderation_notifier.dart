import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/supabase_provider.dart';
import '../repository/models/blocked_user.dart';
import '../repository/moderation_repository.dart';

export '../repository/models/blocked_user.dart';
export '../repository/models/report_reason.dart';
export '../repository/moderation_repository.dart' show ModerationException;

final moderationRepositoryProvider = Provider(
  (ref) => ModerationRepository(
    ref.read(supabaseClientProvider),
    ref.read(pokepediaApiProvider),
  ),
);

/// The people the signed-in user blocked — Settings › Pengguna diblokir.
final blockedUsersProvider = FutureProvider.autoDispose<List<BlockedUser>>((
  ref,
) {
  final userId = ref.watch(authProvider.select((a) => a.valueOrNull?.id));
  if (userId == null) return Future.value(const []);
  return ref.read(moderationRepositoryProvider).fetchBlockedUsers();
});

/// Everyone on either side of a block with the signed-in user, for the
/// direct table reads that the server's RPC filtering doesn't cover.
/// Empty when signed out or when the lookup fails — a filter that can't load
/// shows the rows rather than hiding everything.
final blockedPairIdsProvider = FutureProvider<Set<String>>((ref) async {
  final userId = ref.watch(authProvider.select((a) => a.valueOrNull?.id));
  if (userId == null) return const {};
  try {
    return await ref.read(moderationRepositoryProvider).fetchBlockedPairIds();
  } catch (_) {
    return const {};
  }
});

/// Whether the signed-in user blocked the user behind a username or store
/// slug — what decides between "not found" and the unblock notice.
final blockStatusProvider = FutureProvider.autoDispose
    .family<BlockStatus, String>((ref, handle) {
      final userId = ref.watch(authProvider.select((a) => a.valueOrNull?.id));
      if (userId == null) {
        return Future.value(const BlockStatus(blockedByMe: false));
      }
      return ref.read(moderationRepositoryProvider).blockStatus(handle);
    });

/// Who, if anyone, has cut a chat off — web's `ChatBlockState`.
enum RoomBlockState { none, blockedByMe, blockedMe }

/// Ports `features/chat/api/block-state.ts`: `chat_room_blocked_for_me`
/// says whether either side blocked the other; the caller's own block list
/// says which side. Keyed by the room and the other party's id.
final roomBlockStateProvider = FutureProvider.autoDispose
    .family<RoomBlockState, ({int roomId, String otherUserId})>((
      ref,
      key,
    ) async {
      final repo = ref.read(moderationRepositoryProvider);
      if (!await repo.isRoomBlocked(key.roomId)) return RoomBlockState.none;
      try {
        final mine = await ref.watch(blockedUsersProvider.future);
        return mine.any((user) => user.userId == key.otherUserId)
            ? RoomBlockState.blockedByMe
            : RoomBlockState.blockedMe;
      } catch (_) {
        // The room is blocked either way; without the list, assume it was
        // the other side, which offers nothing the viewer can't do.
        return RoomBlockState.blockedMe;
      }
    });

/// Block or unblock [userId], then drop every cached view that depends on
/// it. Throws [ModerationException] with a sentence to show.
Future<void> setUserBlocked(WidgetRef ref, String userId, bool blocked) async {
  final repo = ref.read(moderationRepositoryProvider);
  if (blocked) {
    await repo.blockUser(userId);
  } else {
    await repo.unblockUser(userId);
  }
  ref
    ..invalidate(blockedUsersProvider)
    ..invalidate(blockedPairIdsProvider)
    ..invalidate(blockStatusProvider)
    ..invalidate(roomBlockStateProvider);
}
