import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/shared/widgets/dismiss_keyboard_on_tap_outside.dart';

Widget _host() {
  return MaterialApp(
    builder: (context, child) => DismissKeyboardOnTapOutside(child: child!),
    home: Scaffold(
      body: Column(
        children: [
          const TextField(key: Key('a')),
          const TextField(key: Key('b')),
          // Plain space to tap on, well clear of both fields.
          const Expanded(child: SizedBox.expand(key: Key('blank'))),
        ],
      ),
    ),
  );
}

FocusNode _focusOf(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode;

void main() {
  testWidgets('a touch outside the field drops its focus', (tester) async {
    await tester.pumpWidget(_host());

    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    expect(_focusOf(tester, 'a').hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('blank')));
    await tester.pump();
    expect(_focusOf(tester, 'a').hasFocus, isFalse);
  });

  testWidgets('a touch on another field moves focus there', (tester) async {
    await tester.pumpWidget(_host());

    await tester.tap(find.byKey(const Key('a')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('b')));
    await tester.pump();

    expect(_focusOf(tester, 'a').hasFocus, isFalse);
    expect(_focusOf(tester, 'b').hasFocus, isTrue);
  });
}
