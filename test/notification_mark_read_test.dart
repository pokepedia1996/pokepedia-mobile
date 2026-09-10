import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/notifications/repository/models/notification_model.dart';
import 'package:pokepedia_mobile/features/notifications/repository/notifications_repository.dart';
import 'package:pokepedia_mobile/features/notifications/usecase/notifications_notifier.dart';

/// `notify_chat_message` writes one notification row per message, so a
/// conversation with four unread messages is four identical "Pesan baru"
/// rows all pointing at the same `/chat/<slug>`. Marking only the tapped one
/// left the other three behind, and since they read the same, the tap looked
/// like it had done nothing at all.
const _user = AppUser(id: 'me', email: 'me@example.com');

NotificationModel _n({
  required int id,
  NotificationType type = NotificationType.chatMessage,
  String? actionUrl = '/chat/room-a',
  bool isRead = false,
}) => NotificationModel(
  id: id,
  slug: 'slug-$id',
  type: type,
  category: NotificationCategory.social,
  title: 'Pesan baru',
  body: 'Halo',
  createdAt: DateTime(2026, 9, 7),
  isRead: isRead,
  actionUrl: actionUrl,
);

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _user;
}

class _FakeRepository implements NotificationsRepository {
  _FakeRepository(this.rows);

  final List<NotificationModel> rows;

  /// Ids, resolved back from the slugs the repository is actually called
  /// with — the assertions read better in ids, and the mapping is exactly
  /// what regressed.
  final marked = <int>[];

  /// What actually went over the wire.
  final markedSlugs = <String>[];
  Object? failWith;

  @override
  Future<List<NotificationModel>> fetchNotifications({int limit = 50}) async =>
      rows;

  @override
  Future<void> markRead(String slug) async {
    if (failWith != null) throw failWith!;
    markedSlugs.add(slug);
    marked.add(int.parse(slug.split('-').last));
  }

  @override
  Future<void> markAllRead() async {
    for (final row in rows) {
      marked.add(row.id);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

Future<({ProviderContainer container, _FakeRepository repository})> _open(
  List<NotificationModel> rows,
) async {
  final repository = _FakeRepository(rows);
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      notificationsRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  // Listened rather than awaited: `notificationsProvider` rebuilds when the
  // faked sign-in resolves, and awaiting its future across that rebuild
  // never settles in a bare container.
  container.listen(notificationsProvider, (_, __) {}, fireImmediately: true);
  for (var i = 0; i < 8; i++) {
    await container.pump();
    await Future<void>.delayed(Duration.zero);
  }
  return (container: container, repository: repository);
}

void main() {
  test('a chat tap reads the whole conversation, not just the row', () async {
    final open = await _open([
      _n(id: 1),
      _n(id: 2),
      _n(id: 3),
      // Another room: untouched, it is a different conversation.
      _n(id: 4, actionUrl: '/chat/room-b'),
    ]);

    await open.container.read(notificationsProvider.notifier).markRead(2);

    expect(open.repository.marked..sort(), [1, 2, 3]);
    expect(open.container.read(unreadNotificationCountProvider), 1);
  });

  test('the row is marked by slug, which is what the RPC takes', () async {
    // `mark_notification_read` declares `p_slug`, and PostgREST resolves an
    // overload by argument name: called with the row's `id` it matched
    // nothing, answered PGRST202, and every tap rolled straight back.
    final open = await _open([
      _n(id: 7, actionUrl: '/orders/x', type: NotificationType.orderCancelled),
    ]);

    await open.container.read(notificationsProvider.notifier).markRead(7);

    expect(open.repository.markedSlugs, ['slug-7']);
    expect(open.container.read(unreadNotificationCountProvider), 0);
  });

  test('an order tap reads only what was tapped', () async {
    // Two events about one order — "dibayar", then "dikirim". Reading one
    // says nothing about the other, so they are not grouped.
    final open = await _open([
      _n(id: 1, type: NotificationType.paymentReceived, actionUrl: '/orders/x'),
      _n(
        id: 2,
        type: NotificationType.shipmentDelivered,
        actionUrl: '/orders/x',
      ),
    ]);

    await open.container.read(notificationsProvider.notifier).markRead(1);

    expect(open.repository.marked, [1]);
    expect(open.container.read(unreadNotificationCountProvider), 1);
  });

  test('a failed write puts every dot back', () async {
    final open = await _open([_n(id: 1), _n(id: 2)]);
    open.repository.failWith = Exception('offline');

    await open.container.read(notificationsProvider.notifier).markRead(1);

    expect(open.container.read(unreadNotificationCountProvider), 2);
  });

  test('a row already read asks the server for nothing', () async {
    final open = await _open([_n(id: 1, isRead: true)]);

    await open.container.read(notificationsProvider.notifier).markRead(1);

    expect(open.repository.marked, isEmpty);
  });

  test('opening a thread reads that room, whatever the route in', () async {
    // The inbox route: no notification was tapped, but the messages those
    // rows are about have just been read.
    final open = await _open([
      _n(id: 1),
      _n(id: 2),
      _n(id: 3, actionUrl: '/chat/room-b'),
      _n(
        id: 4,
        type: NotificationType.offerReceived,
        actionUrl: '/chat/room-a',
      ),
    ]);

    await open.container
        .read(notificationsProvider.notifier)
        .markChatRoomRead('room-a');

    // Room A's chat rows, and nothing else — not the other room, and not a
    // non-chat row that happens to point the same way.
    expect(open.repository.marked..sort(), [1, 2]);
    expect(open.container.read(unreadNotificationCountProvider), 2);
  });

  test('opening a room with nothing unread writes nothing', () async {
    final open = await _open([_n(id: 1, isRead: true)]);

    await open.container
        .read(notificationsProvider.notifier)
        .markChatRoomRead('room-a');

    expect(open.repository.marked, isEmpty);
  });

  test(
    'a thread opened before the list was ever fetched still clears',
    () async {
      // The cold path: nothing has read `notificationsProvider` this session,
      // so the rows that need clearing are exactly the ones nobody has looked
      // at. The method waits for the first fetch rather than no-opping.
      final repository = _FakeRepository([_n(id: 1), _n(id: 2)]);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_FakeAuth.new),
          notificationsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      // Signed in, but the notification list itself never read — the state a
      // session is in until the bell is opened.
      container.listen(authProvider, (_, __) {}, fireImmediately: true);
      for (var i = 0; i < 8; i++) {
        await container.pump();
        await Future<void>.delayed(Duration.zero);
      }

      await container
          .read(notificationsProvider.notifier)
          .markChatRoomRead('room-a');

      expect(repository.marked..sort(), [1, 2]);
    },
  );

  test('an unknown id is ignored rather than marking the first row', () async {
    // `firstWhere(..., orElse: () => current.first)` used to hand back an
    // unrelated row here.
    final open = await _open([_n(id: 1), _n(id: 2)]);

    await open.container.read(notificationsProvider.notifier).markRead(99);

    expect(open.repository.marked, isEmpty);
    expect(open.container.read(unreadNotificationCountProvider), 2);
  });
}
