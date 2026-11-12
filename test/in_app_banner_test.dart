import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/features/notifications/presentation/widgets/in_app_banner_host.dart';
import 'package:pokepedia_mobile/features/notifications/repository/models/notification_model.dart';
import 'package:pokepedia_mobile/features/notifications/repository/notifications_repository.dart';
import 'package:pokepedia_mobile/features/notifications/usecase/in_app_banner_notifier.dart';
import 'package:pokepedia_mobile/features/notifications/usecase/notification_push_notifier.dart';
import 'package:pokepedia_mobile/features/notifications/usecase/notifications_notifier.dart';

/// A new notification row, with the app open, slides a banner in over
/// whatever is on screen. These pin when it shows, how long it stays, and
/// that a tap both reads the row and opens its screen.
const _user = AppUser(id: 'me', email: 'me@example.com');

NotificationModel _n({
  int id = 1,
  NotificationType type = NotificationType.paymentReceived,
  String title = 'Pembayaran Berhasil!',
  String body = 'Penjual akan segera mengirim kartu.',
  String? actionUrl = '/orders/ord-1',
  bool isRead = false,
}) => NotificationModel(
  id: id,
  slug: 'slug-$id',
  type: type,
  category: NotificationCategory.statusUpdate,
  title: title,
  body: body,
  createdAt: DateTime(2026, 11, 10),
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
  final markedSlugs = <String>[];

  @override
  Future<List<NotificationModel>> fetchNotifications({int limit = 50}) async =>
      rows;

  @override
  Future<void> markRead(String slug) async => markedSlugs.add(slug);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  group('deliveryFor', () {
    test('a read row shows nothing', () {
      expect(
        deliveryFor(_n(isRead: true), foreground: true, currentLocation: '/'),
        NotificationDelivery.none,
      );
    });

    test('in front it is a banner, behind it is the OS', () {
      expect(
        deliveryFor(_n(), foreground: true, currentLocation: '/'),
        NotificationDelivery.banner,
      );
      expect(
        deliveryFor(_n(), foreground: false, currentLocation: '/'),
        NotificationDelivery.system,
      );
    });

    test('a message for the open conversation shows nothing', () {
      final chat = _n(
        type: NotificationType.chatMessage,
        actionUrl: '/chat/room-a',
      );
      expect(
        deliveryFor(chat, foreground: true, currentLocation: '/chat/room-a'),
        NotificationDelivery.none,
      );
      // The thread's own query doesn't make it a different conversation.
      expect(
        deliveryFor(
          chat,
          foreground: true,
          currentLocation: '/chat/room-a?listing=9',
        ),
        NotificationDelivery.none,
      );
      // Another conversation still gets one.
      expect(
        deliveryFor(chat, foreground: true, currentLocation: '/chat/room-b'),
        NotificationDelivery.banner,
      );
    });

    test('a row about the screen on display still gets its banner', () {
      // Order pages don't update live, so the banner is the news.
      expect(
        deliveryFor(_n(), foreground: true, currentLocation: '/orders/ord-1'),
        NotificationDelivery.banner,
      );
    });

    test('no location known still shows the banner', () {
      expect(
        deliveryFor(
          _n(type: NotificationType.chatMessage, actionUrl: '/chat/room-a'),
          foreground: true,
          currentLocation: null,
        ),
        NotificationDelivery.banner,
      );
    });
  });

  group('banner', () {
    late _FakeRepository repository;
    late List<String> opened;

    Future<ProviderContainer> pumpHost(
      WidgetTester tester,
      List<NotificationModel> rows,
    ) async {
      repository = _FakeRepository(rows);
      opened = [];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(_FakeAuth.new),
            notificationsRepositoryProvider.overrideWithValue(repository),
            notificationRouteOpenerProvider.overrideWithValue(opened.add),
          ],
          // Mounted where the app mounts it: above the Navigator, with no
          // Overlay over it.
          child: MaterialApp(
            builder: (context, child) => InAppBannerHost(child: child!),
            home: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(InAppBannerHost)),
      );
      // The list loaded, as `_onInserted` awaits before showing.
      container.listen(notificationsProvider, (_, __) {});
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('shows the row and goes away on its own', (tester) async {
      final row = _n();
      final container = await pumpHost(tester, [row]);

      container.read(inAppBannerProvider.notifier).show(row);
      await tester.pumpAndSettle();
      expect(find.text('Pembayaran Berhasil!'), findsOneWidget);
      expect(find.text('Penjual akan segera mengirim kartu.'), findsOneWidget);

      await tester.pump(inAppBannerDuration);
      await tester.pumpAndSettle();
      expect(container.read(inAppBannerProvider), isNull);
      expect(find.text('Pembayaran Berhasil!'), findsNothing);
    });

    testWidgets('a newer row replaces it and restarts the clock', (
      tester,
    ) async {
      final first = _n();
      final second = _n(id: 2, title: 'Proposal Baru');
      final container = await pumpHost(tester, [first, second]);

      container.read(inAppBannerProvider.notifier).show(first);
      await tester.pump(const Duration(seconds: 3));
      container.read(inAppBannerProvider.notifier).show(second);
      await tester.pumpAndSettle();
      expect(find.text('Proposal Baru'), findsOneWidget);
      expect(find.text('Pembayaran Berhasil!'), findsNothing);

      // Past the first row's deadline, inside the second's.
      await tester.pump(const Duration(seconds: 2));
      expect(container.read(inAppBannerProvider)?.id, 2);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(container.read(inAppBannerProvider), isNull);
    });

    testWidgets('a tap reads the row and opens its screen', (tester) async {
      final row = _n();
      final container = await pumpHost(tester, [row]);

      container.read(inAppBannerProvider.notifier).show(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pembayaran Berhasil!'));
      await tester.pumpAndSettle();

      expect(opened, ['/orders/ord-1']);
      expect(repository.markedSlugs, ['slug-1']);
      expect(container.read(inAppBannerProvider), isNull);
    });

    testWidgets('a row with nowhere to go is only read', (tester) async {
      final row = _n(type: NotificationType.ratingReceived, actionUrl: null);
      final container = await pumpHost(tester, [row]);

      container.read(inAppBannerProvider.notifier).show(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pembayaran Berhasil!'));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(repository.markedSlugs, ['slug-1']);
    });

    testWidgets('swiped up, or closed, it goes without opening anything', (
      tester,
    ) async {
      final row = _n();
      final container = await pumpHost(tester, [row]);

      container.read(inAppBannerProvider.notifier).show(row);
      await tester.pumpAndSettle();
      await tester.fling(
        find.text('Pembayaran Berhasil!'),
        const Offset(0, -200),
        800,
      );
      await tester.pumpAndSettle();
      expect(container.read(inAppBannerProvider), isNull);

      container.read(inAppBannerProvider.notifier).show(row);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Tutup notifikasi'));
      await tester.pumpAndSettle();
      expect(container.read(inAppBannerProvider), isNull);

      expect(opened, isEmpty);
      expect(repository.markedSlugs, isEmpty);
    });
  });
}
