import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pokepedia_mobile/core/providers/auth_provider.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/home/usecase/portfolio_value_notifier.dart';
import 'package:pokepedia_mobile/features/portfolio/presentation/widgets/portfolio_picker_sheet.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/wantlist_model.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/portfolio_notifier.dart';

/// The picker carried a star per row that set a stored "default portfolio" —
/// a second, invisible kind of selection sitting next to the visible one.
const _me = AppUser(id: 'me', email: 'me@example.com');

class _FakeAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async => _me;
}

WantlistModel _list(String id, String name) => WantlistModel(
  id: id,
  name: name,
  slug: id,
  cardCount: 0,
  createdAt: DateTime(2026, 9, 1),
  updatedAt: DateTime(2026, 9, 1),
);

Future<ProviderContainer> _open(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      authProvider.overrideWith(_FakeAuth.new),
      listsProvider.overrideWith(
        (ref) async => [_list('a', 'Dua'), _list('b', 'tiga')],
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showPortfolioPicker(context, ref),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('buka'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('the rows carry no star', (tester) async {
    await _open(tester);

    expect(find.text('Pilih portofolio'), findsOneWidget);
    expect(find.text('Utama'), findsOneWidget);
    expect(find.byIcon(LucideIcons.star), findsNothing);
    // The actions that remain are the ones that do something to a list.
    expect(find.byIcon(LucideIcons.pencil), findsNWidgets(2));
    expect(find.byIcon(LucideIcons.trash2), findsNWidgets(2));
  });

  testWidgets('picking one is the only way to choose', (tester) async {
    final container = await _open(tester);

    await tester.tap(find.text('Dua'));
    await tester.pumpAndSettle();

    expect(container.read(selectedPortfolioProvider).name, 'Dua');
  });

  test('with nothing picked, the whole collection is what is valued', () {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(_FakeAuth.new),
        listsProvider.overrideWith((ref) async => [_list('a', 'Dua')]),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(selectedPortfolioProvider).isPrimary, isTrue);
  });
}
