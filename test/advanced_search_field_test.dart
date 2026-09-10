import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/search/presentation/advanced_search_page.dart';
import 'package:pokepedia_mobile/features/search/presentation/widgets/search_filter_controls.dart';

void main() {
  testWidgets('the search inputs sit level with the filter row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Column(
            children: [
              SearchTextField(
                value: '',
                hint: 'Cari nama kartu...',
                prefix: const Icon(Icons.search, size: 18),
                onChanged: (_) {},
                onSubmitted: (_) {},
              ),
              const FilterDropdownButton(
                label: 'Kategori',
                options: [],
                selectedCount: 0,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final field = tester.getSize(find.byType(SearchTextField)).height;
    final dropdown = tester.getSize(find.byType(FilterDropdownButton)).height;

    // On the shared form decoration the field stood 48 against the filter
    // row's 37 — an 11pt step that read as two different control sizes on
    // one card. Web's own input is `typo-body-sm py-2.5`, which is what this
    // now uses.
    expect(
      field - dropdown,
      lessThanOrEqualTo(6),
      reason: 'field $field vs dropdown $dropdown',
    );
  });
}
