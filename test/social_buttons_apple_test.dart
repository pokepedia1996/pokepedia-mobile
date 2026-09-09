import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/auth/presentation/widgets/google_sign_in_button.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: Center(child: SizedBox(width: 340, child: child)),
  ),
);

void main() {
  testWidgets('Apple sits beside Google on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      _host(SocialButtons(onGooglePressed: () {}, onApplePressed: () {})),
    );
    await tester.pumpAndSettle();

    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(find.text('Masuk dengan Apple'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Apple is absent on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(
      _host(SocialButtons(onGooglePressed: () {}, onApplePressed: () {})),
    );
    await tester.pumpAndSettle();

    // Apple's Android flow is a browser redirect, which this app avoids.
    expect(find.text('Masuk dengan Google'), findsOneWidget);
    expect(find.text('Masuk dengan Apple'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('no Apple button when the caller offers no handler', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(_host(SocialButtons(onGooglePressed: () {})));
    await tester.pumpAndSettle();

    expect(find.text('Masuk dengan Apple'), findsNothing);
    expect(find.text('Daftar dengan Apple'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('signup wording is used in signup mode', (tester) async {
    await tester.pumpWidget(
      _host(
        SocialButtons(
          mode: SocialButtonsMode.signup,
          onGooglePressed: () {},
          onApplePressed: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daftar dengan Google'), findsOneWidget);
    expect(find.text('Masuk dengan Google'), findsNothing);
  });

  testWidgets('a busy Google sign-in disables the row', (tester) async {
    await tester.pumpWidget(
      _host(
        SocialButtons(
          onGooglePressed: () {},
          onApplePressed: () {},
          loading: true,
        ),
      ),
    );
    // `pump`, not `pumpAndSettle`: the loading spinner animates forever, so
    // settling never completes.
    await tester.pump();

    final google = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(google.onPressed, isNull);
  });
}
