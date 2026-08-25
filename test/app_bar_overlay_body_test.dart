import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pokepedia_mobile/shared/widgets/transparent_app_bar.dart';

/// The status bar inset a test view reports, standing in for a notched phone.
const _statusBarHeight = 47.0;

Widget _page({required Widget body, bool? reserveToolbar}) {
  return MaterialApp(
    home: Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(reserveToolbar: reserveToolbar, child: body),
    ),
  );
}

/// A page reached by a push, so `ModalRoute.canPop` is true and the bar
/// really does draw a back button over the body.
Widget _pushedPage({required Widget body}) {
  return MaterialApp(
    home: const Scaffold(body: SizedBox()),
    routes: {
      '/detail': (_) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const TransparentAppBar(),
        body: AppBarOverlayBody(child: body),
      ),
    },
  );
}

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.viewInsets = FakeViewPadding.zero;
    view.padding = const FakeViewPadding(top: _statusBarHeight);
    view.devicePixelRatio = 1.0;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!.reset();
  });

  testWidgets('content clears the status bar and the back button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _pushedPage(
        body: const Align(alignment: Alignment.topLeft, child: Text('Konten')),
      ),
    );
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/detail');
    await tester.pumpAndSettle();

    final contentTop = tester.getTopLeft(find.text('Konten')).dy;
    expect(
      contentTop,
      greaterThanOrEqualTo(_statusBarHeight + kToolbarHeight),
      reason: 'Scaffold strips the body padding an app bar would have '
          'covered, so both the status bar inset and the toolbar row have to '
          'be re-added — otherwise the first widget sits under the back '
          'button.',
    );

    // And specifically: below the back button, not behind it.
    final backButtonBottom = tester
        .getRect(find.byType(CircularBackButton))
        .bottom;
    expect(contentTop, greaterThanOrEqualTo(backButtonBottom));
  });

  testWidgets('a root page reserves no toolbar it does not draw', (
    tester,
  ) async {
    // Nothing to pop, so `TransparentAppBar` renders no back button and the
    // body should not open a hole where one would have been.
    await tester.pumpWidget(
      _page(body: const Align(alignment: Alignment.topLeft, child: Text('Konten'))),
    );

    expect(find.byType(CircularBackButton), findsNothing);
    final top = tester.getTopLeft(find.text('Konten')).dy;
    expect(top, greaterThanOrEqualTo(_statusBarHeight));
    expect(top, lessThan(_statusBarHeight + kToolbarHeight));
  });

  testWidgets('reserveToolbar forces the gap for an actions-only bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(
        reserveToolbar: true,
        body: const Align(alignment: Alignment.topLeft, child: Text('Konten')),
      ),
    );

    final top = tester.getTopLeft(find.text('Konten')).dy;
    expect(top, greaterThanOrEqualTo(_statusBarHeight + kToolbarHeight));
  });

  testWidgets('page still paints edge to edge behind the status bar', (
    tester,
  ) async {
    await tester.pumpWidget(_page(body: const SizedBox.expand()));

    // The scaffold itself keeps the full height: only the content is inset,
    // so backgrounds and artwork still run under the status bar.
    final scaffold = tester.getRect(find.byType(Scaffold));
    expect(scaffold.top, 0);
  });
}
