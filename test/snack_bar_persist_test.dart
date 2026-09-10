import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `SnackBar.persist` defaults to `action != null`, so any snackbar with an
/// action silently ignores its `duration` and waits for a tap. Every
/// "added to cart" / "offer sent" toast in the app carries an action, so
/// these pin the behaviour both ways.
Widget _host(SnackBar snackBar) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(snackBar),
          child: const Text('Tambah'),
        ),
      ),
    ),
  );
}

SnackBar _snackBar({required bool? persist}) {
  return SnackBar(
    content: const Text('Ditambahkan ke keranjang'),
    duration: const Duration(seconds: 2),
    persist: persist,
    action: SnackBarAction(label: 'Lihat', onPressed: () {}),
  );
}

void main() {
  testWidgets('an action snackbar left at its default never times out', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_snackBar(persist: null)));
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();

    expect(find.text('Ditambahkan ke keranjang'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(
      find.text('Ditambahkan ke keranjang'),
      findsOneWidget,
      reason: 'This is the bug: duration is ignored while persist is on.',
    );
  });

  testWidgets('persist: false lets the same snackbar dismiss itself', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_snackBar(persist: false)));
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();

    expect(find.text('Ditambahkan ke keranjang'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Ditambahkan ke keranjang'), findsNothing);
  });
}
