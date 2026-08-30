import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/core/theme/app_theme.dart';
import 'package:pokepedia_mobile/features/seller/presentation/widgets/listing_table.dart';
import 'package:pokepedia_mobile/features/seller/repository/models/listing_offer.dart';
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
  Map<String, OfferCount> offerCounts = const {},
  ValueChanged<SellerListing>? onViewOffers,
  ValueChanged<SellerListing>? onDelete,
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
          onDelete: onDelete ?? (_) {},
          onToggleOffers: (_, __) {},
          onToggleAutoRelist: (_, __) {},
          onViewOffers: onViewOffers ?? (_) {},
          offerCounts: offerCounts,
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
      expect(sort.apply(listings).map((l) => l.price), [300000, 125000, 50000]);
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
      final sorted = const ListingSort(ListingSortCol.name, ascending: true)
          .apply([
            SellerListing.fromRow(_row(id: 1, name: 'zapdos')),
            SellerListing.fromRow(_row(id: 2, name: 'Alakazam')),
          ]);
      expect(sorted.first.card.name, 'Alakazam');
    });

    test('collector numbers sort numerically, not as raw text', () {
      // The bug this guards: "#10" sorting before "#9" because 1 < 9.
      final sorted = const ListingSort(ListingSortCol.number, ascending: true)
          .apply([
            SellerListing.fromRow(_row(id: 1, number: '10/165')),
            SellerListing.fromRow(_row(id: 2, number: '9/165')),
            SellerListing.fromRow(_row(id: 3, number: '100/165')),
          ]);
      expect(sorted.map((l) => l.card.collectorNumber), [
        '9/165',
        '10/165',
        '100/165',
      ]);
    });

    test('condition sorts best grade first', () {
      final sorted =
          const ListingSort(ListingSortCol.condition, ascending: true).apply([
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
      await _pumpTable(tester, [
        SellerListing.fromRow(_row()),
      ], onSort: (col) => tapped = col);

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

  group('Aksi menu', () {
    final listing = SellerListing.fromRow(_row(price: 100000));
    final listings = [listing];

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
    }

    testWidgets('carries web\'s entries, offers first', (tester) async {
      await _pumpTable(tester, listings);
      await openMenu(tester);

      expect(find.text('Lihat penawaran'), findsOneWidget);
      expect(find.text('Tambah stok'), findsOneWidget);
      expect(find.text('Arsipkan'), findsOneWidget);
      expect(find.text('Hapus permanen'), findsOneWidget);
    });

    testWidgets('offers needing an answer are counted in the menu', (
      tester,
    ) async {
      await _pumpTable(
        tester,
        listings,
        offerCounts: {
          listing.slug: const OfferCount(total: 3, needsResponse: 2),
        },
      );
      await openMenu(tester);

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a listing with nothing waiting shows no count', (
      tester,
    ) async {
      // An offer waiting on the buyer is not work; badging it would send
      // the seller into a screen with nothing to do.
      await _pumpTable(
        tester,
        listings,
        offerCounts: {
          listing.slug: const OfferCount(total: 2, needsResponse: 0),
        },
      );
      await openMenu(tester);

      expect(find.text('2'), findsNothing);
    });

    testWidgets('"Lihat penawaran" reports the listing it belongs to', (
      tester,
    ) async {
      SellerListing? opened;
      await _pumpTable(tester, listings, onViewOffers: (l) => opened = l);
      await openMenu(tester);

      await tester.tap(find.text('Lihat penawaran'));
      await tester.pumpAndSettle();

      expect(opened?.slug, listing.slug);
    });

    testWidgets('deleting goes through the page, which confirms first', (
      tester,
    ) async {
      SellerListing? deleted;
      await _pumpTable(tester, listings, onDelete: (l) => deleted = l);
      await openMenu(tester);

      await tester.tap(find.text('Hapus permanen'));
      await tester.pumpAndSettle();

      expect(deleted?.slug, listing.slug);
    });

    testWidgets('locked stock disables the destructive entries only', (
      tester,
    ) async {
      // A buyer is mid-checkout: archiving or deleting would pull the row
      // out from under them, but their offers are still worth reading.
      await _pumpTable(tester, [
        SellerListing.fromRow(_row(quantity: 3, qtyLocked: 1)),
      ]);
      await openMenu(tester);

      bool enabled(String label) => tester
          .widget<PopupMenuItem<String>>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(PopupMenuItem<String>),
            ),
          )
          .enabled;

      expect(enabled('Lihat penawaran'), isTrue);
      expect(enabled('Arsipkan'), isFalse);
      expect(enabled('Hapus permanen'), isFalse);
    });
  });
}
