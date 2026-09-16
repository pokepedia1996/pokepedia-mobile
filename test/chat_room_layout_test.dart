import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pokepedia_mobile/app/router/routes.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/chat/presentation/chat_thread_page.dart';
import 'package:pokepedia_mobile/features/chat/presentation/widgets/chat_context_banner.dart';
import 'package:pokepedia_mobile/features/chat/presentation/widgets/chat_event_cards.dart';
import 'package:pokepedia_mobile/features/chat/repository/models/chat_models.dart';
import 'package:pokepedia_mobile/features/chat/usecase/chat_notifier.dart';

/// The room after it was rebuilt to match the website: a run opens with the
/// sender's avatar and name, every bubble carries its clock, and your own
/// carry read ticks. The layout is nested three deep (row → constrained
/// bubble → text/stamp row), which is exactly the shape that overflows if a
/// long message isn't allowed to shrink.
const _me = AppUser(id: 'me', email: 'me@example.com');

ChatMessage _msg({
  required int id,
  required bool mine,
  String text = 'Halo',
  int minute = 0,
}) => ChatMessage(
  id: id,
  senderId: mine ? 'me' : 'them',
  fromMe: mine,
  text: text,
  createdAt: DateTime(2026, 9, 7, 15, minute),
);

const _room = ChatRoom(
  id: 1,
  slug: 'room-a',
  title: 'Toko User1',
  otherUserId: 'them',
  otherUsername: 'user1',
  otherStoreSlug: 'toko-user1',
);

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

class _FakeThread extends ChatThreadNotifier {
  _FakeThread(this.value);

  final ChatThreadState value;

  @override
  Future<ChatThreadState> build(ChatThreadArg arg) async {
    _builtWith = arg;
    return value;
  }
}

/// The argument the page handed the notifier — where the listing id was
/// being lost between the button and the thread.
ChatThreadArg? _builtWith;

/// Where a tap on the header landed, if anywhere.
String? _openedRoute;

Future<void> _pump(
  WidgetTester tester,
  ChatThreadState state, {
  int? listingId,
  ChatListingContext? seedContext,
}) async {
  _openedRoute = null;
  _builtWith = null;
  tester.view.physicalSize = const Size(1170, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        chatThreadProvider.overrideWith(() => _FakeThread(state)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: GoRouter(
          initialLocation: '/chat/room-a',
          routes: [
            GoRoute(
              path: '/chat/:slug',
              builder: (_, __) => ChatThreadPage(
                slug: 'room-a',
                listingId: listingId,
                seedContext: seedContext,
              ),
            ),
            GoRoute(
              path: '/market/:handle',
              builder: (_, routeState) {
                _openedRoute = routeState.uri.path;
                return const Text('storefront');
              },
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a conversation lays out without overflowing', (tester) async {
    await _pump(
      tester,
      ChatThreadState(
        title: _room.title,
        room: _room,
        messages: [
          _msg(id: 1, mine: false, text: 'Halo bang', minute: 40),
          _msg(id: 2, mine: true, text: 'halo bro', minute: 51),
          _msg(id: 3, mine: true, text: 'testtt', minute: 53),
          _msg(
            id: 4,
            mine: false,
            // The case the old fixed-width bubble could not take: one word
            // longer than the screen.
            text: 'Haiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii',
            minute: 55,
          ),
        ],
        othersReadUpTo: 2,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a run opens with the sender and every bubble is stamped', (
    tester,
  ) async {
    await _pump(
      tester,
      ChatThreadState(
        title: _room.title,
        room: _room,
        messages: [
          _msg(id: 1, mine: false, text: 'Hai juga', minute: 43),
          _msg(id: 2, mine: true, text: 'halo bro', minute: 51),
          _msg(id: 3, mine: true, text: 'testtt', minute: 53),
        ],
        othersReadUpTo: 2,
      ),
    );

    // The other party is named once, on the message that opens their run —
    // and again in the app bar, which is the header's own copy.
    expect(find.text('Toko User1'), findsNWidgets(2));
    expect(find.text('@user1'), findsOneWidget);

    // Web stamps each bubble rather than only the last of a run.
    expect(find.text('15.51'), findsOneWidget);
    expect(find.text('15.53'), findsOneWidget);
    expect(find.text('15.43'), findsOneWidget);
  });

  test('the room route can name the listing it was opened about', () {
    // `extra` already carries the title hint on this route, and would not
    // survive a deep link anyway.
    expect(Routes.chatThread('room-a'), '/chat/room-a');
    expect(
      Uri.parse(
        Routes.chatThread('room-a', listingId: 9),
      ).queryParameters['listing'],
      '9',
    );
    // The plain form stays plain: notification action URLs are matched
    // against it exactly.
    expect(Uri.parse(Routes.chatThread('room-a')).hasQuery, isFalse);
  });

  testWidgets('the listing reaches the thread when the room already exists', (
    tester,
  ) async {
    // The bug: "Hubungi" pushed /chat/<slug> with nothing else, so a
    // conversation that already existed had no idea which card was tapped
    // and the banner never had anything to draw.
    await _pump(
      tester,
      const ChatThreadState(title: 'Toko User1', messages: []),
      listingId: 9,
    );

    expect(_builtWith?.listingId, 9);
  });

  testWidgets('a chat opened from a listing shows the card at once', (
    tester,
  ) async {
    // Rooms are created lazily, so tapping "Hubungi" writes nothing until
    // the first message — the thread used to open on a blank screen with no
    // sign of which card it was about.
    await _pump(
      tester,
      const ChatThreadState(
        title: 'Toko User1',
        messages: [],
        openedListingId: 9,
        previewContext: ChatListingContext(
          listingOrderId: 9,
          cardId: 42,
          priceIdr: 10000,
          cardName: 'Levigato',
          packSlug: 'sv2a',
          condition: 'NM',
        ),
      ),
    );

    // The pinned banner web puts under the header: what this is about, and
    // what it costs.
    expect(find.byType(ChatContextBanner), findsOneWidget);
    expect(find.text('TENTANG LISTING'), findsOneWidget);
    expect(find.text('Levigato'), findsOneWidget);
    expect(find.text('Rp10.000'), findsOneWidget);
  });

  testWidgets('the banner names the newest listing the thread carries', (
    tester,
  ) async {
    // The real `listing_context` message says the same thing, with a clock.
    await _pump(
      tester,
      ChatThreadState(
        title: 'Toko User1',
        room: _room,
        openedListingId: 9,
        messages: [
          ChatMessage(
            id: 1,
            senderId: 'them',
            fromMe: false,
            text: '',
            createdAt: DateTime(2026, 9, 12, 15, 35),
            kind: 'listing_context',
            listingContext: const ChatListingContext(
              listingOrderId: 9,
              cardId: 42,
              priceIdr: 10000,
              cardName: 'Levigato',
              packSlug: 'sv2a',
              condition: 'NM',
            ),
          ),
        ],
      ),
    );

    // Once: pinned above, since the in-thread card is the message itself.
    expect(find.byType(ChatContextBanner), findsOneWidget);
    expect(find.text('Levigato'), findsNWidgets(2));
  });

  testWidgets('the opening page\'s card is pinned without any lookup', (
    tester,
  ) async {
    // The listing page is holding the listing already, so it hands it over
    // — the pin is on screen in the first frame and doesn't depend on
    // `chat_about_listing` answering, or answering at all.
    await _pump(
      tester,
      const ChatThreadState(title: 'Toko User1', messages: []),
      seedContext: const ChatListingContext(
        listingOrderId: 9,
        cardId: 42,
        priceIdr: 10000,
        cardName: 'Levigato',
        packSlug: 'sv2a',
        condition: 'NM',
      ),
    );

    expect(find.byType(ChatContextBanner), findsOneWidget);
    expect(find.text('Levigato'), findsOneWidget);
  });

  testWidgets('a chat opened from a profile pins nothing', (tester) async {
    // The same conversation, reached from the profile's chat button rather
    // than from a listing: the old card stays in the timeline as history,
    // but nothing is announced at the top.
    await _pump(
      tester,
      ChatThreadState(
        title: 'Toko User1',
        room: _room,
        messages: [
          ChatMessage(
            id: 1,
            senderId: 'them',
            fromMe: false,
            text: '',
            createdAt: DateTime(2026, 9, 12, 15, 35),
            kind: 'listing_context',
            listingContext: const ChatListingContext(
              listingOrderId: 9,
              cardId: 42,
              priceIdr: 10000,
              cardName: 'Levigato',
              packSlug: 'sv2a',
              condition: 'NM',
            ),
          ),
        ],
      ),
    );

    expect(find.byType(ChatContextBanner), findsNothing);
    // Still in the thread itself.
    expect(find.text('Levigato'), findsOneWidget);
  });

  testWidgets('an event card sits on its sender\'s side', (tester) async {
    // The listing card is posted by whoever opened the chat — you — so it
    // belongs on your side, like anything else you sent.
    const listing = ChatListingContext(
      listingOrderId: 9,
      cardId: 42,
      priceIdr: 10000,
      cardName: 'Levigato',
      packSlug: 'sv2a',
      condition: 'NM',
    );
    await _pump(
      tester,
      ChatThreadState(
        title: 'Toko User1',
        room: _room,
        messages: [
          ChatMessage(
            id: 1,
            senderId: 'me',
            fromMe: true,
            text: '',
            createdAt: DateTime(2026, 9, 12, 15, 30),
            kind: 'listing_context',
            listingContext: listing,
          ),
          ChatMessage(
            id: 2,
            senderId: 'them',
            fromMe: false,
            text: '',
            createdAt: DateTime(2026, 9, 12, 15, 31),
            kind: 'listing_context',
            listingContext: listing,
          ),
        ],
      ),
    );

    final cards = tester.widgetList<ChatEventCard>(find.byType(ChatEventCard));
    expect(cards.length, 2);

    final boxes = find.byType(ChatEventCard).evaluate().toList();
    final mine = tester.getTopRight(find.byWidget(boxes.first.widget));
    final theirs = tester.getTopLeft(find.byWidget(boxes.last.widget));
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;

    // Mine hugs the right edge; theirs hugs the left.
    expect(mine.dx, greaterThan(width / 2));
    expect(theirs.dx, lessThan(width / 2));
  });

  testWidgets('tapping who you are talking to opens their shop', (
    tester,
  ) async {
    await _pump(
      tester,
      const ChatThreadState(title: 'Toko User1', room: _room, messages: []),
    );

    await tester.tap(find.text('Toko User1'));
    await tester.pumpAndSettle();

    expect(_openedRoute, '/market/toko-user1');
  });

  testWidgets('a counterparty with no shop is not a link', (tester) async {
    const shopless = ChatRoom(
      id: 2,
      slug: 'room-b',
      title: 'user2',
      otherUserId: 'them',
    );
    await _pump(
      tester,
      const ChatThreadState(title: 'user2', room: shopless, messages: []),
    );

    await tester.tap(find.text('user2'));
    await tester.pumpAndSettle();

    expect(_openedRoute, isNull);
  });

  testWidgets('only your own messages carry ticks', (tester) async {
    await _pump(
      tester,
      ChatThreadState(
        title: _room.title,
        room: _room,
        messages: [
          _msg(id: 1, mine: false, minute: 40),
          _msg(id: 2, mine: true, minute: 41),
          _msg(id: 3, mine: true, minute: 42),
        ],
        // Only the first of the two has been read.
        othersReadUpTo: 2,
      ),
    );

    expect(find.byIcon(LucideIcons.checkCheck), findsNWidgets(2));
  });
}
