import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/listing_table.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/seller_listing.dart';

Map<String, dynamic> _row({
  int id = 1,
  String name = 'Charizard ex',
  String number = '201/165',
  String expansion = 'SV2a',
  String condition = 'LP',
  int price = 125000,
  int quantity = 3,
  int qtyLocked = 0,
  int viewCount = 42,
}) {
  return {
    'id': id,
    'slug': '9c0f3a10-2b44-4e91-8a77-1d5e6f2b3c4$id',
    'price': price,
    'condition': condition,
    'quantity': quantity,
    'qty_locked': qtyLocked,
    'status': 'open',
    'accepts_offers': false,
    'auto_relist': true,
    'view_count': viewCount,
    'created_at': '2026-08-01T10:00:00+00:00',
    'archived_at': null,
    'expires_at': '2099-09-01T10:00:00+00:00',
    'cards': {
      'id': id,
      'name_id': name,
      'expansion_code': expansion,
      'collector_number': number,
      'rarity': 'SAR',
      'category': 'Pokemon',
      'language': 'id',
      'variant': 'normal',
      'details': <String, dynamic>{},
    },
  };
}

Future<void> _pumpTable(
  WidgetTester tester,
  List<SellerListing> listings, {
  ValueChanged<ListingSortCol>? onSort,
}) async {
  // A blank frame first: pumping an identical tree twice repaints nothing,
  // so a fresh overflow error would never be reported.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.takeException();

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ListingTable(
          listings: listings,
          sort: const ListingSort(ListingSortCol.price),
          onSort: onSort ?? (_) {},
          onArchive: (_) {},
          onUnarchive: (_) {},
          onRestock: (_) {},
          onToggleOffers: (_, __) {},
          onToggleAutoRelist: (_, __) {},
          onRefresh: () async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('ListingSort', () {
    final listings = [
      SellerListing.fromRow(_row(id: 1, name: 'Alakazam', price: 50000)),
      SellerListing.fromRow(_row(id: 2, name: 'Charizard ex', price: 300000)),
      SellerListing.fromRow(_row(id: 3, name: 'Blastoise', price: 125000)),
    ];

    test('price descending is the default order, as on web', () {
      const sort = ListingSort(ListingSortCol.price);
      expect(sort.ascending, isFalse);
      expect(
        sort.apply(listings).map((l) => l.price),
        [300000, 125000, 50000],
      );
    });

    test('tapping the active column flips its direction', () {
      const sort = ListingSort(ListingSortCol.price);
      final flipped = sort.toggled(ListingSortCol.price);
      expect(flipped.col, ListingSortCol.price);
      expect(flipped.ascending, isTrue);
      expect(flipped.apply(listings).map((l) => l.price), [
        50000,
        125000,
        300000,
      ]);
    });

    test('tapping another column moves to it, descending', () {
      final moved = const ListingSort(
        ListingSortCol.price,
        ascending: true,
      ).toggled(ListingSortCol.name);
      expect(moved.col, ListingSortCol.name);
      expect(moved.ascending, isFalse);
    });

    test('names sort case-insensitively', () {
      final sorted = const ListingSort(
        ListingSortCol.name,
        ascending: true,
      ).apply([
        SellerListing.fromRow(_row(id: 1, name: 'zapdos')),
        SellerListing.fromRow(_row(id: 2, name: 'Alakazam')),
      ]);
      expect(sorted.first.card.name, 'Alakazam');
    });

    test('collector numbers sort numerically, not as raw text', () {
      // The bug this guards: "#10" sorting before "#9" because 1 < 9.
      final sorted = const ListingSort(
        ListingSortCol.number,
        ascending: true,
      ).apply([
        SellerListing.fromRow(_row(id: 1, number: '10/165')),
        SellerListing.fromRow(_row(id: 2, number: '9/165')),
        SellerListing.fromRow(_row(id: 3, number: '100/165')),
      ]);
      expect(
        sorted.map((l) => l.card.collectorNumber),
        ['9/165', '10/165', '100/165'],
      );
    });

    test('condition sorts best grade first', () {
      final sorted = const ListingSort(
        ListingSortCol.condition,
        ascending: true,
      ).apply([
        SellerListing.fromRow(_row(id: 1, condition: 'HP')),
        SellerListing.fromRow(_row(id: 2, condition: 'NM')),
        SellerListing.fromRow(_row(id: 3, condition: 'MP')),
      ]);
      expect(sorted.map((l) => l.condition.name), ['nm', 'mp', 'hp']);
    });
  });

  group('ListingTable', () {
    testWidgets('renders web\'s column headers in order', (tester) async {
      await _pumpTable(tester, [SellerListing.fromRow(_row())]);

      for (final label in [
        'Aksi',
        'Gambar',
        'Nama kartu',
        'Ekspansi',
        'Nomor',
        'Kondisi',
        'Harga',
        'Jumlah',
        'Harga Total',
        'Dilihat',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a row lays out on a phone without overflowing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pumpTable(tester, [
        SellerListing.fromRow(_row(name: 'Charizard ex Special Art Rare')),
      ]);

      // The table is wider than the screen by design — it must scroll
      // sideways rather than overflow.
      expect(tester.takeException(), isNull);
      expect(find.text('Charizard ex Special Art Rare'), findsOneWidget);
    });

    testWidgets('tapping a sortable header reports the column', (tester) async {
      ListingSortCol? tapped;
      await _pumpTable(
        tester,
        [SellerListing.fromRow(_row())],
        onSort: (col) => tapped = col,
      );

      await tester.tap(find.text('Nama kartu'));
      await tester.pump();
      expect(tapped, ListingSortCol.name);
    });

    testWidgets('locked stock shows available over total', (tester) async {
      await _pumpTable(tester, [
        SellerListing.fromRow(_row(quantity: 5, qtyLocked: 2)),
      ]);

      expect(find.text('3 / 5'), findsOneWidget);
      expect(find.text('×5'), findsNothing);
    });
  });
}
