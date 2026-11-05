import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/portfolio/repository/models/inventory_entry.dart';
import 'package:pokepedia_mobile/features/portfolio/usecase/activity_export.dart';
import 'package:pokepedia_mobile/shared/models/card_model.dart';

/// The Aktivitas export: which rows a range takes, and the CSV they become.
InventoryActivityEntry _row(
  int id,
  DateTime at, {
  String name = 'Caterpie',
  InventoryActivityAction action = InventoryActivityAction.addedIn,
  int quantity = 1,
  int unitPrice = 1000,
  String? rarity = 'AR',
  String? series,
  String? variantKey,
  String number = '001/099',
}) => InventoryActivityEntry(
  id: id,
  card: CardModel(
    id: id,
    category: CardCategory.pokemon,
    nameId: name,
    expansionCode: 'sv9s',
    packSlug: 'sv9s',
    collectorNumber: number,
    rarity: rarity,
  ),
  action: action,
  quantity: quantity,
  unitPrice: unitPrice,
  createdAt: at,
  series: series,
  variantKey: variantKey,
);

void main() {
  group('activityInRange', () {
    final rows = [
      _row(1, DateTime(2026, 8, 31, 23, 59)),
      _row(2, DateTime(2026, 9, 1)),
      _row(3, DateTime(2026, 9, 30, 23, 59)),
      _row(4, DateTime(2026, 10, 1)),
    ];

    test('takes whole days, both ends included', () {
      final range = DateTimeRange(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 30),
      );
      expect(activityInRange(rows, range).map((r) => r.id), [2, 3]);
    });

    test('a single day is that whole day', () {
      final day = DateTime(2026, 9, 30);
      expect(
        activityInRange(
          rows,
          DateTimeRange(start: day, end: day),
        ).map((r) => r.id),
        [3],
      );
    });

    test('no range is everything', () {
      expect(activityInRange(rows, null), hasLength(4));
    });
  });

  group('activityCsv', () {
    test('a header, then a row each, in the order given', () {
      final csv = activityCsv([
        _row(
          1,
          DateTime(2026, 9, 13, 14, 5),
          quantity: 3,
          unitPrice: 2500,
          series: 'Scarlet & Violet',
          variantKey: 'reverse',
          number: '025/165-2',
        ),
        _row(
          2,
          DateTime(2026, 9, 12, 9, 0),
          name: 'Metapod',
          action: InventoryActivityAction.removedOut,
          rarity: null,
        ),
      ]);

      // Excel reads it as UTF-8 only with the mark.
      expect(csv.startsWith('﻿'), isTrue);
      final lines = csv.substring(1).split('\r\n');
      expect(
        lines[0],
        'Tanggal,Aksi,Jumlah,Nama Kartu,Varian,Ekspansi,Nomor,Kelangkaan,'
        'Seri,Harga Satuan,Harga Total',
      );
      // Bare rupiah, so the column adds up.
      expect(
        lines[1],
        '2026-09-13 14:05,Masuk,3,Caterpie,Holo Reverse,SV9S,025/165,AR,'
        'Scarlet & Violet,2500,7500',
      );
      expect(
        lines[2],
        '2026-09-12 09:00,Keluar,1,Metapod,,SV9S,001/099,,,1000,1000',
      );
      expect(lines[3], isEmpty);
    });

    test('quotes what would break a field', () {
      final csv = activityCsv([
        _row(1, DateTime(2026, 9, 1), name: 'Pikachu, "Surfing"'),
      ]);
      expect(csv, contains('"Pikachu, ""Surfing"""'));
    });

    test('a name a spreadsheet would run stays text', () {
      final csv = activityCsv([
        _row(1, DateTime(2026, 9, 1), name: '=HYPERLINK("x")'),
      ]);
      expect(csv, contains('"\'=HYPERLINK(""x"")"'));
    });
  });

  test('the file is named for its range', () {
    expect(
      activityExportFileName(
        DateTimeRange(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30)),
      ),
      'pokepedia-aktivitas-2026-09-01_2026-09-30.csv',
    );
    expect(
      activityExportFileName(null, now: DateTime(2026, 10, 21)),
      'pokepedia-aktivitas-semua-2026-10-21.csv',
    );
  });
}
