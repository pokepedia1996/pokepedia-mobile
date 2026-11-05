import '../../../shared/widgets/app_search_field.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/card_model.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import 'package:flutter/services.dart';
import '../../../shared/utils/price_input_formatter.dart';
import '../../../shared/utils/variant_label.dart';
import '../../../shared/utils/collector_number.dart';
import '../../../shared/utils/card_filtering.dart';
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/card_language_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../repository/models/inventory_entry.dart';
import '../../../shared/utils/csv_export.dart';
import '../usecase/activity_export.dart';
import '../usecase/portfolio_notifier.dart';
import '../../home/usecase/portfolio_value_notifier.dart';
import '../../home/repository/models/portfolio_value.dart';
import '../../../core/utils/image_url.dart';

enum _InventorySection { database, add, remove, activity }

extension on _InventorySection {
  String get label => switch (this) {
    _InventorySection.database => 'Database',
    _InventorySection.add => 'Tambahkan',
    _InventorySection.remove => 'Hapuskan',
    _InventorySection.activity => 'Aktivitas',
  };
}

/// Ports `app/portfolio/inventory/page.tsx` — kept to its four core
/// workflows (Database, Tambahkan, Hapuskan, Aktivitas) with a mobile-native
/// segmented layout instead of the web's desktop data-grid (no custom
/// columns, keyboard nav, or cost-basis analytics — those don't translate
/// to a phone screen).
class InventoryTab extends ConsumerStatefulWidget {
  const InventoryTab({super.key});

  @override
  ConsumerState<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends ConsumerState<InventoryTab> {
  _InventorySection _section = _InventorySection.database;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final records = ref.watch(inventoryRecordsProvider).valueOrNull ?? const [];
    final totalValue = records.fold<int>(
      0,
      (sum, r) => sum + r.unitPrice * r.quantity,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ports the web header: the record count under the title, with the
        // holding's total value alongside it.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inventori Kartu',
                style: AppTypography.h2(colors.onSurface),
              ),
              const SizedBox(height: 2),
              Text(
                '${records.length} inventori',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  text: 'Nilai Total: ',
                  style: AppTypography.h3(colors.onSurface),
                  children: [
                    TextSpan(
                      // A dash rather than Rp0 while nothing is priced, the
                      // same distinction the web draws.
                      text: totalValue > 0 ? formatRupiah(totalValue) : 'Rp–',
                      style: AppTypography.h3(colors.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Web's four-up segmented control rather than the pill chips this
        // used to carry.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                for (final section in _InventorySection.values)
                  Expanded(
                    child: _SectionChip(
                      label: section.label,
                      selected: _section == section,
                      onTap: () => setState(() => _section = section),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: switch (_section) {
            _InventorySection.database => const _DatabaseSection(),
            _InventorySection.add => const _AddSection(),
            _InventorySection.remove => const _RemoveSection(),
            _InventorySection.activity => const _ActivitySection(),
          },
        ),
      ],
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).cardColor : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Text(
          label,
          style: selected
              ? AppTypography.captionSemibold(colors.onSurface)
              : AppTypography.caption(context.mutedForeground),
        ),
      ),
    );
  }
}

class _InventoryGroup {
  const _InventoryGroup({
    required this.card,
    required this.totalQty,
    required this.avgPrice,
    required this.records,
  });

  final CardModel card;
  final int totalQty;
  final int avgPrice;
  final List<InventoryEntry> records;

  int get totalValue => totalQty * avgPrice;

  /// When the most recent copy came in — web's Tanggal for a grouped row.
  DateTime get latestAt =>
      records.map((r) => r.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);

  /// The first copy's note that says anything — web's `notesForGroup`.
  String? get notes {
    for (final r in records) {
      final note = r.notes?.trim();
      if (note != null && note.isNotEmpty) return note;
    }
    return null;
  }

  InventoryEntry get first => records.first;
}

/// Web's `costBasisKey`: one Database row per card, finish and set of
/// custom values — two copies whose own columns say different things are
/// two rows, as they are on web.
String _costBasisKey(InventoryEntry r) {
  final keys = r.customData.keys.toList()..sort();
  final custom = [for (final k in keys) '$k=${r.customData[k]}'].join('&');
  return '${r.card.id}::${r.variantKey ?? ''}::$custom';
}

List<_InventoryGroup> _groupForDatabase(List<InventoryEntry> records) {
  final byKey = <String, List<InventoryEntry>>{};
  for (final r in records) {
    byKey.putIfAbsent(_costBasisKey(r), () => []).add(r);
  }
  return [for (final group in byKey.values) _summarise(group)];
}

_InventoryGroup _summarise(List<InventoryEntry> group) {
  final totalQty = group.fold<int>(0, (s, r) => s + r.quantity);
  final totalValue = group.fold<int>(0, (s, r) => s + r.totalValue);
  return _InventoryGroup(
    card: group.first.card,
    totalQty: totalQty,
    avgPrice: totalQty > 0 ? (totalValue / totalQty).round() : 0,
    records: group,
  );
}

List<_InventoryGroup> _groupByCard(List<InventoryEntry> records) {
  final byCard = <int, List<InventoryEntry>>{};
  for (final r in records) {
    byCard.putIfAbsent(r.card.id, () => []).add(r);
  }
  final groups = byCard.values.map((group) {
    final totalQty = group.fold<int>(0, (s, r) => s + r.quantity);
    final totalValue = group.fold<int>(0, (s, r) => s + r.totalValue);
    return _InventoryGroup(
      card: group.first.card,
      totalQty: totalQty,
      avgPrice: totalQty > 0 ? (totalValue / totalQty).round() : 0,
      records: group,
    );
  }).toList();
  groups.sort((a, b) {
    final aLatest = a.records
        .map((r) => r.createdAt)
        .reduce((x, y) => x.isAfter(y) ? x : y);
    final bLatest = b.records
        .map((r) => r.createdAt)
        .reduce((x, y) => x.isAfter(y) ? x : y);
    return bLatest.compareTo(aLatest);
  });
  return groups;
}

/// The card's own page, from a row of the Database or Aktivitas table.
void _openCard(BuildContext context, CardModel card) =>
    context.push(Routes.cardDetail(card.packSlug, card.id));

/// A card name that opens the card — web's underlined `Link`, the line in
/// the border colour so it marks the link without shouting.
TextStyle _linkStyle(BuildContext context) =>
    AppTypography.bodySm(context.appColors.onSurface).copyWith(
      decoration: TextDecoration.underline,
      decorationColor: context.borderColor,
    );

// ---------------------------------------------------------------- Database

/// A Database column — web's `SortTh` keys, plus the user's own columns
/// (`custom:<key>`). Every one but the picture sorts.
enum _DbColumn {
  date('Tanggal', 104),
  image('Gambar', 96),
  name('Nama Kartu', 156),
  expansion('Ekspansi', 92),
  number('Nomor', 88),
  rarity('Kelangkaan', 112),
  series('Seri', 132),
  qty('Jumlah', 80),
  avg('Harga Rata-rata', 128),
  value('Harga Total', 116),
  notes('Catatan', 180);

  const _DbColumn(this.label, this.width);

  final String label;
  final double width;

  /// The `column_key` web's column settings use, for the ones the user can
  /// hide. Jumlah, the two prices and Catatan are always shown.
  String? get configKey => switch (this) {
    _DbColumn.date => 'date',
    _DbColumn.image => 'image',
    _DbColumn.name => 'name',
    _DbColumn.expansion => 'expansion',
    _DbColumn.number => 'number',
    _DbColumn.rarity => 'rarity',
    _DbColumn.series => 'series',
    _ => null,
  };
}

/// What the Database table is sorted by: a built-in column, or one of the
/// user's own by its key.
@immutable
class _DbSort {
  const _DbSort.builtIn(_DbColumn this.column, {required this.ascending})
    : custom = null;
  const _DbSort.custom(InventoryColumn this.custom, {required this.ascending})
    : column = null;

  final _DbColumn? column;
  final InventoryColumn? custom;
  final bool ascending;

  /// Web opens on the newest first.
  static const initial = _DbSort.builtIn(_DbColumn.date, ascending: false);

  bool isOn(_DbColumn c) => column == c;
  bool isOnCustom(InventoryColumn c) => custom?.key == c.key;

  /// Tapping the column already sorted flips it; another starts ascending,
  /// as web's `handleAvgSort` does.
  _DbSort tapped(_DbColumn c) => isOn(c)
      ? _DbSort.builtIn(c, ascending: !ascending)
      : _DbSort.builtIn(c, ascending: true);

  _DbSort tappedCustom(InventoryColumn c) => isOnCustom(c)
      ? _DbSort.custom(c, ascending: !ascending)
      : _DbSort.custom(c, ascending: true);

  int compare(_InventoryGroup a, _InventoryGroup b) {
    final custom = this.custom;
    final result = custom != null
        ? _compareCustom(custom, a, b)
        : switch (column!) {
            _DbColumn.date => a.latestAt.compareTo(b.latestAt),
            _DbColumn.image => 0,
            _DbColumn.name => _compareText(a.card.name, b.card.name),
            _DbColumn.expansion => _compareText(
              a.card.expansionCode,
              b.card.expansionCode,
            ),
            _DbColumn.number => compareCollectorNumber(
              a.card.collectorNumber,
              b.card.collectorNumber,
            ),
            _DbColumn.rarity => rarityRank(
              a.card.rarity ?? '',
            ).compareTo(rarityRank(b.card.rarity ?? '')),
            // Release order, as web sorts it — not the names A–Z.
            _DbColumn.series => (a.first.seriesId ?? 0).compareTo(
              b.first.seriesId ?? 0,
            ),
            _DbColumn.qty => a.totalQty.compareTo(b.totalQty),
            _DbColumn.avg => a.avgPrice.compareTo(b.avgPrice),
            _DbColumn.value => a.totalValue.compareTo(b.totalValue),
            _DbColumn.notes => _compareBlankLast(a.notes, b.notes),
          };
    return ascending ? result : -result;
  }

  static int _compareText(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  /// Rows with nothing written sort after the rest whichever way the column
  /// runs — a note column sorted A–Z should open on notes, not on blanks.
  int _compareBlankLast(String? a, String? b) {
    if (a == null && b == null) return 0;
    if (a == null) return ascending ? 1 : -1;
    if (b == null) return ascending ? -1 : 1;
    return _compareText(a, b);
  }

  int _compareCustom(
    InventoryColumn column,
    _InventoryGroup a,
    _InventoryGroup b,
  ) {
    final av = _customText(a, column);
    final bv = _customText(b, column);
    if (column.isNumber) {
      final an = num.tryParse(av ?? '');
      final bn = num.tryParse(bv ?? '');
      if (an != null && bn != null) return an.compareTo(bn);
    }
    return _compareBlankLast(av, bv);
  }
}

/// What a group's own column holds, or null when it holds nothing.
String? _customText(_InventoryGroup group, InventoryColumn column) {
  final value = group.first.customData[column.key];
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

class _DatabaseSection extends ConsumerStatefulWidget {
  const _DatabaseSection();

  @override
  ConsumerState<_DatabaseSection> createState() => _DatabaseSectionState();
}

class _DatabaseSectionState extends ConsumerState<_DatabaseSection> {
  String _query = '';
  Timer? _debounce;
  _DbSort _sort = _DbSort.initial;
  int _page = 0;

  // Grouping and sorting every record is the expensive part of this tab, so
  // it is redone only when the records, the search or the sort change —
  // not on every rebuild, which a page turn or a keystroke also causes.
  List<InventoryEntry>? _groupedFrom;
  List<_InventoryGroup> _groups = const [];
  ({List<InventoryEntry> records, String query, _DbSort sort})? _shownFor;
  List<_InventoryGroup> _shown = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  List<_InventoryGroup> _visible(List<InventoryEntry> records) {
    if (!identical(_groupedFrom, records)) {
      _groupedFrom = records;
      _groups = _groupForDatabase(records);
    }
    final key = (records: records, query: _query, sort: _sort);
    final cached = _shownFor;
    if (cached != null &&
        identical(cached.records, records) &&
        cached.query == _query &&
        identical(cached.sort, _sort)) {
      return _shown;
    }
    final needle = _query.trim().toLowerCase();
    final shown = needle.isEmpty
        ? [..._groups]
        : _groups.where((g) {
            return g.card.name.toLowerCase().contains(needle) ||
                g.card.collectorNumber.toLowerCase().contains(needle) ||
                g.card.expansionCode.toLowerCase().contains(needle) ||
                (g.first.series?.toLowerCase().contains(needle) ?? false);
          }).toList();
    shown.sort(_sort.compare);
    _shownFor = key;
    return _shown = shown;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventoryRecordsProvider);
    final config = ref.watch(inventoryColumnsProvider).valueOrNull ?? const [];
    return async.when(
      data: (records) {
        if (records.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.package,
            title: 'Inventori kosong',
            description: 'Tambahkan kartu lewat tab Tambahkan.',
          );
        }
        final visible = _visible(records);
        final pageCount = (visible.length / _tablePageSize).ceil();
        final page = _page.clamp(0, pageCount == 0 ? 0 : pageCount - 1);
        final start = page * _tablePageSize;
        final rows = visible.sublist(
          start,
          (start + _tablePageSize).clamp(0, visible.length),
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppSearchField(
                hintText: 'Cari nama, ekspansi, nomor, seri...',
                // A short pause before filtering, so a long inventory isn't
                // searched again on every letter.
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 250), () {
                    if (mounted) {
                      setState(() {
                        _query = v;
                        _page = 0;
                      });
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        'Tidak ada kartu yang cocok.',
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        AppBottomNav.reservedSpace(context) + 12,
                      ),
                      children: [
                        _RecordTable(
                          groups: rows,
                          config: config,
                          sort: _sort,
                          // A new order starts again from its first page.
                          onSort: (sort) => setState(() {
                            _sort = sort;
                            _page = 0;
                          }),
                        ),
                        _Pager(
                          page: page,
                          pageCount: pageCount,
                          total: visible.length,
                          onPage: (p) => setState(() => _page = p),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat inventori')),
    );
  }
}

/// The Database tab's table — web's columns, in web's order, each one
/// sortable from its header.
///
/// Which of the hideable ones show, and the user's own columns, come from
/// the column settings they keep on web; with none saved, everything shows,
/// as it does there.
class _RecordTable extends StatelessWidget {
  const _RecordTable({
    required this.groups,
    required this.config,
    required this.sort,
    required this.onSort,
  });

  final List<_InventoryGroup> groups;
  final List<InventoryColumn> config;
  final _DbSort sort;
  final ValueChanged<_DbSort> onSort;

  static const _customWidth = 120.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Web's `isColVisible`: no settings saved means every column.
    final shown = {
      for (final c in config)
        if (c.isVisible) c.key,
    };
    bool visible(_DbColumn c) =>
        c.configKey == null || shown.isEmpty || shown.contains(c.configKey);
    final leading = [
      for (final c in _DbColumn.values.take(_DbColumn.value.index + 1))
        if (visible(c)) c,
    ];
    final customs = [
      for (final c in config)
        if (c.isCustom && c.isVisible) c,
    ];

    final headers = <({String label, double width})>[
      for (final c in leading) (label: c.label, width: c.width),
      for (final c in customs) (label: c.label, width: _customWidth),
      (label: _DbColumn.notes.label, width: _DbColumn.notes.width),
    ];
    final sorts = <_HeaderSort?>[
      for (final c in leading)
        c == _DbColumn.image
            ? null
            : _HeaderSort(
                active: sort.isOn(c),
                ascending: sort.ascending,
                onTap: () => onSort(sort.tapped(c)),
              ),
      for (final c in customs)
        _HeaderSort(
          active: sort.isOnCustom(c),
          ascending: sort.ascending,
          onTap: () => onSort(sort.tappedCustom(c)),
        ),
      _HeaderSort(
        active: sort.isOn(_DbColumn.notes),
        ascending: sort.ascending,
        onTap: () => onSort(sort.tapped(_DbColumn.notes)),
      ),
    ];

    Widget cell(_InventoryGroup group, _DbColumn column) {
      final card = group.card;
      return switch (column) {
        // Web prints the date and the clock together; stacked, because a
        // phone column has the height to spare and not the width.
        _DbColumn.date => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatSaleDate(group.latestAt.toLocal()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption(context.mutedForeground),
            ),
            Text(
              formatClockId(group.latestAt),
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
        // Web's 80×48 crop of the top of the card, in its 96px column.
        _DbColumn.image => ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: SizedBox(
            width: 80,
            height: 48,
            child: CardArt(
              imageUrl: card.imageUrl,
              size: ImageSize.half,
              aspectRatio: 80 / 48,
              alignment: const Alignment(0, -0.55),
            ),
          ),
        ),
        _DbColumn.name => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CardLanguageBadge(language: card.language, size: 13),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _linkStyle(context),
                  ),
                ),
              ],
            ),
            // Web's `VariantLabel`: which finish, under the name.
            if (formatCardVariant(group.first.variantKey ?? card.variant)
                case final variant?)
              Text(
                variant,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(context.mutedForeground),
              ),
          ],
        ),
        _DbColumn.expansion => _plain(
          context,
          card.expansionCode.toUpperCase(),
        ),
        _DbColumn.number => _plain(
          context,
          stripCardNumberSuffix(card.collectorNumber),
        ),
        _DbColumn.rarity => _plain(
          context,
          card.rarity ?? 'Tanpa tanda',
          muted: true,
        ),
        _DbColumn.series => _plain(
          context,
          group.first.series ?? '–',
          muted: true,
        ),
        _DbColumn.qty => Text(
          '${group.totalQty}',
          style: AppTypography.bodySmSemibold(colors.onSurface),
        ),
        // The average of what the copies cost, which is what a grouped row
        // can honestly say about a unit price.
        _DbColumn.avg => _plain(context, formatRupiah(group.avgPrice)),
        _DbColumn.value => Text(
          formatRupiah(group.totalValue),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmSemibold(colors.onSurface),
        ),
        _DbColumn.notes => Text(
          group.notes ?? '–',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySm(context.mutedForeground),
        ),
      };
    }

    return _TableFrame(
      headers: headers,
      sorts: sorts,
      onRowTap: (i) => _openCard(context, groups[i].card),
      rows: [
        for (final group in groups)
          [
            for (final c in leading) cell(group, c),
            for (final c in customs)
              _plain(context, _customText(group, c) ?? '–', muted: true),
            cell(group, _DbColumn.notes),
          ],
      ],
    );
  }

  Widget _plain(BuildContext context, String text, {bool muted = false}) =>
      Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySm(
          muted ? context.mutedForeground : context.appColors.onSurface,
        ),
      );
}

/// An Aktivitas column — web's `SortTh` keys, in `activity-table.tsx`'s
/// order. All but Aksi sort.
enum _ActColumn {
  date('Tanggal', 104),
  action('Aksi', 112),
  qty('Jumlah', 80),
  name('Nama Kartu', 156),
  expansion('Ekspansi', 92),
  number('Nomor', 88),
  rarity('Kelangkaan', 112),
  series('Seri', 132),
  price('Harga Satuan', 116),
  total('Harga Total', 116);

  const _ActColumn(this.label, this.width);

  final String label;
  final double width;

  /// The `column_key` of the column settings kept on web, which this tab
  /// honours as the Database tab does. Aksi, Jumlah and the prices always
  /// show.
  String? get configKey => switch (this) {
    _ActColumn.date => 'date',
    _ActColumn.name => 'name',
    _ActColumn.expansion => 'expansion',
    _ActColumn.number => 'number',
    _ActColumn.rarity => 'rarity',
    _ActColumn.series => 'series',
    _ => null,
  };
}

/// What the Aktivitas table is sorted by — web's `actSortCol`/`actSortDir`.
@immutable
class _ActSort {
  const _ActSort(this.column, {required this.ascending});

  final _ActColumn column;
  final bool ascending;

  /// Web opens on the latest first.
  static const initial = _ActSort(_ActColumn.date, ascending: false);

  /// Tapping the column already sorted flips it; another starts ascending.
  _ActSort tapped(_ActColumn c) => c == column
      ? _ActSort(c, ascending: !ascending)
      : _ActSort(c, ascending: true);

  int compare(InventoryActivityEntry a, InventoryActivityEntry b) {
    final result = switch (column) {
      _ActColumn.date => a.createdAt.compareTo(b.createdAt),
      _ActColumn.action => 0,
      _ActColumn.qty => a.quantity.compareTo(b.quantity),
      _ActColumn.name => _DbSort._compareText(a.card.name, b.card.name),
      _ActColumn.expansion => _DbSort._compareText(
        a.card.expansionCode,
        b.card.expansionCode,
      ),
      _ActColumn.number => compareCollectorNumber(
        a.card.collectorNumber,
        b.card.collectorNumber,
      ),
      _ActColumn.rarity => rarityRank(
        a.card.rarity ?? '',
      ).compareTo(rarityRank(b.card.rarity ?? '')),
      // Release order, as web sorts it.
      _ActColumn.series => (a.seriesId ?? 0).compareTo(b.seriesId ?? 0),
      _ActColumn.price => a.unitPrice.compareTo(b.unitPrice),
      _ActColumn.total => (a.unitPrice * a.quantity).compareTo(
        b.unitPrice * b.quantity,
      ),
    };
    return ascending ? result : -result;
  }
}

/// The Aktivitas tab's table — ports `features/inventory/components/
/// activity-table.tsx`: when, what, and to which card, each column sortable
/// from its header and the hideable ones following the web column settings.
class _ActivityTable extends StatelessWidget {
  const _ActivityTable({
    required this.rows,
    required this.config,
    required this.sort,
    required this.onSort,
  });

  final List<InventoryActivityEntry> rows;
  final List<InventoryColumn> config;
  final _ActSort sort;
  final ValueChanged<_ActSort> onSort;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Web's `isColVisible`: no settings saved means every column.
    final shown = {
      for (final c in config)
        if (c.isVisible) c.key,
    };
    final columns = [
      for (final c in _ActColumn.values)
        if (c.configKey == null || shown.isEmpty || shown.contains(c.configKey))
          c,
    ];

    Widget plain(String text, {bool muted = false, bool bold = false}) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: bold
          ? AppTypography.bodySmSemibold(colors.onSurface)
          : AppTypography.bodySm(
              muted ? context.mutedForeground : colors.onSurface,
            ),
    );

    Widget cell(InventoryActivityEntry row, _ActColumn column) {
      final card = row.card;
      return switch (column) {
        // Web prints the date and the clock together; stacked, because a
        // phone column has the height to spare and not the width.
        _ActColumn.date => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatSaleDate(row.createdAt.toLocal()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption(context.mutedForeground),
            ),
            Text(
              formatClockId(row.createdAt),
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
        _ActColumn.action => _ActionPill(action: row.action),
        _ActColumn.qty => plain('${row.quantity}', bold: true),
        _ActColumn.name => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CardLanguageBadge(language: card.language, size: 13),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _linkStyle(context),
                  ),
                ),
              ],
            ),
            if (formatCardVariant(row.variantKey ?? card.variant)
                case final variant?)
              Text(
                variant,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(context.mutedForeground),
              ),
          ],
        ),
        _ActColumn.expansion => plain(card.expansionCode.toUpperCase()),
        _ActColumn.number => plain(stripCardNumberSuffix(card.collectorNumber)),
        _ActColumn.rarity => plain(card.rarity ?? 'Tanpa tanda', muted: true),
        _ActColumn.series => plain(row.series ?? '–', muted: true),
        _ActColumn.price => plain(formatRupiah(row.unitPrice)),
        _ActColumn.total => plain(
          formatRupiah(row.unitPrice * row.quantity),
          bold: true,
        ),
      };
    }

    return _TableFrame(
      headers: [for (final c in columns) (label: c.label, width: c.width)],
      onRowTap: (i) => _openCard(context, rows[i].card),
      sorts: [
        for (final c in columns)
          c == _ActColumn.action
              ? null
              : _HeaderSort(
                  active: sort.column == c,
                  ascending: sort.ascending,
                  onTap: () => onSort(sort.tapped(c)),
                ),
      ],
      rows: [
        for (final row in rows) [for (final c in columns) cell(row, c)],
      ],
    );
  }
}

/// What happened, in web's words and colours: Masuk in green, Keluar in the
/// brand colour, Perbaikan — a price or quantity corrected — in red.
class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.action});

  final InventoryActivityAction action;

  @override
  Widget build(BuildContext context) {
    final tint = switch (action) {
      InventoryActivityAction.addedIn => context.appSemantic.success,
      InventoryActivityAction.removedOut => context.appColors.primary,
      InventoryActivityAction.updated => context.appColors.error,
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(action.label, style: AppTypography.badge(tint)),
      ),
    );
  }
}

// ------------------------------------------------------------- Tambahkan

class _AddSection extends ConsumerStatefulWidget {
  const _AddSection();

  @override
  ConsumerState<_AddSection> createState() => _AddSectionState();
}

class _AddSectionState extends ConsumerState<_AddSection> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _debouncedQuery = '';
  bool _syncing = false;

  /// What "Simpan Semua" is up to, while it runs.
  String? _bulkLabel;

  /// Nothing typed yet — when the sync button and the hint show. Follows
  /// the field itself rather than the debounced query, so they go the
  /// moment typing starts instead of 400ms later.
  bool _idle = true;

  void _onSearchChanged(String v) {
    final idle = v.trim().isEmpty;
    if (idle != _idle) setState(() => _idle = idle);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _debouncedQuery = v);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openAddSheet(CardModel card) async {
    final result = await showModalBottomSheet<({int quantity, int unitPrice})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddDraftSheet(card: card),
    );
    if (result == null || !mounted) return;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final res = await ref
        .read(portfolioRepositoryProvider)
        .createDraftRecord(
          userId: user.id,
          cardId: card.id,
          quantity: result.quantity,
          unitPrice: result.unitPrice,
        );
    if (!mounted) return;
    if (res.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.error!)));
      return;
    }
    ref.invalidate(inventoryDraftsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${card.name} ditambahkan ke draft')),
    );
  }

  /// Web's "Sinkronkan Koleksi": pick a collection, and whatever it holds
  /// that the inventory doesn't is staged as drafts to price and save.
  Future<void> _sync() async {
    if (_syncing) return;
    // Awaited rather than read: a tap that lands while the session is still
    // being restored should wait for it, not do nothing.
    final user = await ref.read(authProvider.future);
    if (user == null || !mounted) return;
    final target = await showModalBottomSheet<PortfolioTarget>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const _SyncSourceSheet(),
    );
    if (target == null || !mounted) return;

    setState(() => _syncing = true);
    final res = await ref
        .read(portfolioRepositoryProvider)
        .syncInventoryFromCollection(
          userId: user.id,
          collectionId: target.listId,
        );
    if (!mounted) return;
    setState(() => _syncing = false);

    final String message;
    if (res.error != null) {
      message = res.error!;
    } else if (res.inserted == 0) {
      message = '"${target.name}" sudah sinkron dengan inventori.';
    } else {
      ref.invalidate(inventoryDraftsProvider);
      message = '${res.inserted} draft ditambahkan dari "${target.name}".';
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Clears the staging table. Confirmed first: it is the one button here
  /// that throws work away.
  Future<void> _deleteAll(List<InventoryEntry> drafts) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null || _bulkLabel != null) return;

    await showConfirmDialog(
      context,
      title: 'Hapus semua?',
      description:
          '${drafts.length} draft akan dibuang. Kartu yang sudah disimpan '
          'ke inventori tidak terpengaruh.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () async {
        final error = await ref
            .read(portfolioRepositoryProvider)
            .deleteDraftRecords(
              userId: user.id,
              recordIds: [for (final d in drafts) d.id],
            );
        ref.invalidate(inventoryDraftsProvider);
        if (error != null && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error)));
        }
      },
    );
  }

  Future<void> _saveAll(List<InventoryEntry> drafts) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null || _bulkLabel != null) return;
    final total = formatCountId(drafts.length);
    setState(() => _bulkLabel = 'Menyimpan 0/$total...');

    // The tap on this button is what ends an edit in progress; its write
    // has to land before the drafts are confirmed as they stand on the
    // server. Web's `draftSave.flushAll()`.
    await Future.wait(_pendingDraftWrites.toList());
    // And confirmed as the list now reads, edits included.
    final latest = ref.read(inventoryDraftsProvider).valueOrNull ?? drafts;

    final result = await ref
        .read(cardOwnershipControllerProvider)
        .confirmInventoryDrafts(
          userId: user.id,
          drafts: latest,
          onProgress: (done) {
            if (mounted) {
              setState(
                () => _bulkLabel = 'Menyimpan ${formatCountId(done)}/$total...',
              );
            }
          },
        );
    if (!mounted) return;
    setState(() => _bulkLabel = null);
    final message = result.error != null && result.saved == 0
        ? result.error!
        : result.failed == 0
        ? '${formatCountId(result.saved)} inventori ditambahkan'
        : '${formatCountId(result.saved)} ditambahkan, '
              '${formatCountId(result.failed)} gagal';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final draftsAsync = ref.watch(inventoryDraftsProvider);
    final showResults = _debouncedQuery.trim().length >= 2;
    final resultsAsync = showResults
        ? ref.watch(
            cardSearchPickerProvider((query: _debouncedQuery, language: null)),
          )
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        AppSearchField(
          hintText: 'Cari kartu untuk ditambahkan...',
          controller: _searchController,
          onChanged: _onSearchChanged,
        ),
        // Before anything is typed, what else this tab can do: fill the
        // drafts from a collection in one go, and how searching works. Both
        // step aside once a search starts — the results need the room.
        if (_idle) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _syncing ? null : _sync,
              icon: _syncing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.refreshCw, size: 15),
              label: const Text('Sinkronkan Koleksi'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
            child: Text(
              'Ketik nama, nomor, ekspansi, atau kelangkaan kartu di atas '
              'untuk mencari.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          ),
        ],
        if (resultsAsync != null) ...[
          const SizedBox(height: 10),
          resultsAsync.when(
            data: (results) {
              if (results.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Tidak ditemukan.',
                    style: AppTypography.bodySm(context.mutedForeground),
                  ),
                );
              }
              // A rail, not a list: results are pictures, and a card is
              // recognised by its art long before its name is read. Web
              // scrolls these sideways for the same reason — a column of
              // thumbnails pushes the drafts table off the screen.
              final drafted = <int, int>{};
              final staged =
                  draftsAsync.valueOrNull ?? const <InventoryEntry>[];
              for (final draft in staged) {
                drafted.update(
                  draft.card.id,
                  (n) => n + draft.quantity,
                  ifAbsent: () => draft.quantity,
                );
              }

              return SizedBox(
                height: _AddResultCard.railHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  // Off the page's own padding, so the first card starts at
                  // the margin and the last can scroll clear of it.
                  padding: EdgeInsets.zero,
                  clipBehavior: Clip.none,
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => _AddResultCard(
                    card: results[i],
                    drafted: drafted[results[i].id] ?? 0,
                    onTap: () => _openAddSheet(results[i]),
                  ),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: PikachuLoader(size: 96),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
        const SizedBox(height: 20),
        draftsAsync.when(
          data: (drafts) {
            if (drafts.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DraftTable(
                  drafts: drafts,
                  busyLabel: _bulkLabel,
                  onSaveAll: () => _saveAll(drafts),
                  onDeleteAll: () => _deleteAll(drafts),
                ),
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Web's `CollectionSourceDialog`, as a bottom sheet: which collection to
/// sync from. Opens on the portfolio already selected elsewhere in the app,
/// as web opens on its active collection.
class _SyncSourceSheet extends ConsumerStatefulWidget {
  const _SyncSourceSheet();

  @override
  ConsumerState<_SyncSourceSheet> createState() => _SyncSourceSheetState();
}

class _SyncSourceSheetState extends ConsumerState<_SyncSourceSheet> {
  PortfolioTarget? _picked;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final targets = ref.watch(portfolioTargetsProvider);
    final lists = ref.watch(listsProvider).valueOrNull ?? const [];
    final counts = {for (final l in lists) l.id: l.cardCount};
    final picked = _picked ?? ref.watch(selectedPortfolioProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Sinkronkan dari koleksi',
              style: AppTypography.h3(colors.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Kartu di koleksi yang belum ada di inventori ditambahkan '
              'sebagai draft.',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: RadioGroup<PortfolioTarget>(
                groupValue: picked,
                onChanged: (t) => setState(() => _picked = t),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final target in targets)
                      RadioListTile<PortfolioTarget>(
                        value: target,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          target.name,
                          style: AppTypography.bodySmSemibold(colors.onSurface),
                        ),
                        subtitle: Text(
                          target.isPrimary
                              ? 'Koleksi utama'
                              : '${counts[target.listId] ?? 0} kartu',
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(picked),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text('Sinkronkan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ports `AddCardItem` — one result in the rail: the artwork, what it is
/// under it, and a badge for however many are already staged as drafts.
class _AddResultCard extends StatelessWidget {
  const _AddResultCard({
    required this.card,
    required this.drafted,
    required this.onTap,
  });

  /// `w-36` on the web.
  static const width = 140.0;

  /// Artwork at 245:342, plus the gap and the two lines under it. Measured
  /// in `inventory_add_rail_test`, which fails if the tile outgrows it.
  static const railHeight = width * 342 / 245 + 48;

  final CardModel card;

  /// Copies already staged for this card, which web badges in the corner.
  final int drafted;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: CardArt(imageUrl: card.imageUrl, size: ImageSize.half),
                ),
                if (drafted > 0)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$drafted',
                        style: AppTypography.captionSemibold(colors.onPrimary),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CardLanguageBadge(language: card.language, size: 13),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(colors.onSurface),
                  ),
                ),
              ],
            ),
            Text(
              '${card.collectorNumber} · ${card.expansionCode}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.badge(
                context.mutedForeground,
              ).copyWith(fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame every inventory table shares: a header band, fixed column
/// widths, and one sideways scroll over the lot.
///
/// Ports the shape of the tables in `app/portfolio/inventory/page.tsx`,
/// which are the same table three times over — the tab decides what the
/// columns are, not how they are drawn.
/// A sortable header's state — web's `SortTh`.
class _HeaderSort {
  const _HeaderSort({
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final bool active;
  final bool ascending;
  final VoidCallback onTap;
}

class _TableFrame extends StatelessWidget {
  const _TableFrame({
    required this.headers,
    required this.rows,
    this.sorts,
    this.onRowTap,
  });

  final List<({String label, double width})> headers;

  /// Per header, how it sorts — null for a table, or a column, that doesn't.
  final List<_HeaderSort?>? sorts;

  /// One list of cells per row, in the headers' order.
  final List<List<Widget>> rows;

  /// What tapping a row does, by its index — web's tables link the card's
  /// name; on a phone the whole row is the target.
  final ValueChanged<int>? onRowTap;

  @override
  Widget build(BuildContext context) {
    final width = headers.fold<double>(0, (sum, h) => sum + h.width);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: context.appColors.secondary,
                // The sortable cells carry their own padding, so the whole
                // height of the header is the tap target.
                padding: EdgeInsets.symmetric(vertical: sorts == null ? 10 : 0),
                child: Row(
                  children: [
                    for (var i = 0; i < headers.length; i++)
                      SizedBox(
                        width: headers[i].width,
                        child: _HeaderCell(
                          label: headers[i].label,
                          sort: sorts?[i],
                        ),
                      ),
                  ],
                ),
              ),
              for (var r = 0; r < rows.length; r++)
                InkWell(
                  onTap: onRowTap == null ? null : () => onRowTap!(r),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: context.borderColor),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        for (var i = 0; i < rows[r].length; i++)
                          SizedBox(
                            width: headers[i].width,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: rows[r][i],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A header: the label, and for a sortable column an arrow saying which
/// way it runs — or, on the columns not sorting, a faint both-ways mark
/// saying it can.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, this.sort});

  final String label;
  final _HeaderSort? sort;

  @override
  Widget build(BuildContext context) {
    final sort = this.sort;
    final colors = context.appColors;
    final color = sort?.active ?? false
        ? colors.primary
        : context.mutedForeground;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.captionSemibold(color),
    );
    if (sort == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: text,
      );
    }
    return InkWell(
      onTap: sort.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Flexible(child: text),
            const SizedBox(width: 4),
            Icon(
              !sort.active
                  ? LucideIcons.chevronsUpDown
                  : sort.ascending
                  ? LucideIcons.arrowUp
                  : LucideIcons.arrowDown,
              size: 12,
              color: sort.active
                  ? colors.primary
                  : context.mutedForeground.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// A column of the draft table. Web keeps the same set and lets each one be
/// hidden — the narrow ones carry facts you only need while you are checking
/// a batch, and on a phone they are what makes the table a scroll.
enum _DraftColumn {
  status('Status', 78),
  image('Gambar', 64),
  name('Nama Kartu', 130),
  expansion('Ekspansi', 84),
  number('Nomor', 88),
  rarity('Kelangkaan', 104),
  quantity('Jumlah', 116),
  unitPrice('Harga Satuan', 96),
  totalPrice('Harga Total', 104),
  notes('Catatan', 150),
  actions('', 90);

  const _DraftColumn(this.label, this.width);

  final String label;
  final double width;

  /// The two that are the point of the table: what you are saving, and the
  /// buttons that save it.
  bool get canHide => this != _DraftColumn.name && this != _DraftColumn.actions;
}

/// The staging table, in web's shape: one row per draft, the columns fixed
/// and the whole thing scrolling sideways.
///
/// A table rather than the stacked cards this used to be — the point of the
/// draft stage is comparing what you're about to save, and quantities and
/// prices only compare when they line up in columns.
/// Draft edits on their way to the server — see `_DraftRowState._commit`.
final _pendingDraftWrites = <Future<void>>{};

/// Rows per page in the drafts and Database tables.
///
/// Both used to draw every row at once: a sync of a large collection staged
/// thousands of drafts, and each one was a row of text fields and a card
/// picture, built and laid out together in a single frame.
const _tablePageSize = 20;

class _DraftTable extends StatefulWidget {
  const _DraftTable({
    required this.drafts,
    required this.onSaveAll,
    required this.onDeleteAll,
    this.busyLabel,
  });

  final List<InventoryEntry> drafts;
  final VoidCallback onSaveAll;
  final VoidCallback onDeleteAll;

  /// What a bulk save or delete is doing, while one runs — both buttons
  /// are held until it is done.
  final String? busyLabel;

  @override
  State<_DraftTable> createState() => _DraftTableState();
}

class _DraftTableState extends State<_DraftTable> {
  /// Held here rather than on the server: web persists a column config per
  /// user, which is worth having when you keep a spreadsheet open all day.
  /// A phone session is a batch, and a batch is over before a preference
  /// would pay for itself.
  final _hidden = <_DraftColumn>{};
  int _page = 0;

  List<_DraftColumn> get _visible => [
    for (final column in _DraftColumn.values)
      if (!_hidden.contains(column)) column,
  ];

  double get _tableWidth => _visible.fold<double>(0, (sum, c) => sum + c.width);

  @override
  Widget build(BuildContext context) {
    final busy = widget.busyLabel != null;
    final pageCount = (widget.drafts.length / _tablePageSize).ceil();
    // A page emptied by saving or deleting from it falls back to the last
    // one that still has rows.
    final page = _page.clamp(0, pageCount == 0 ? 0 : pageCount - 1);
    final start = page * _tablePageSize;
    final rows = widget.drafts.sublist(
      start,
      (start + _tablePageSize).clamp(0, widget.drafts.length),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Web's trio above the table: the destructive one outlined, the one
        // you came to press filled, and the columns behind an icon.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : widget.onDeleteAll,
                icon: const Icon(LucideIcons.trash2, size: 15),
                label: const Text('Hapus Semua'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.appColors.error,
                  side: BorderSide(
                    color: context.appColors.error.withValues(alpha: 0.4),
                  ),
                  minimumSize: const Size.fromHeight(40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: busy ? null : widget.onSaveAll,
                icon: const Icon(LucideIcons.check, size: 15),
                label: const Text('Simpan Semua'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.appSemantic.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _ColumnMenu(
              hidden: _hidden,
              onToggle: (column) => setState(() {
                if (!_hidden.remove(column)) _hidden.add(column);
              }),
            ),
          ],
        ),
        if (busy) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.busyLabel!,
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.borderColor),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: context.appColors.secondary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        for (final column in _visible)
                          SizedBox(
                            width: column.width,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Text(
                                column.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.captionSemibold(
                                  context.mutedForeground,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Keyed by draft: a page turn hands these slots to other
                  // drafts, and each row's fields belong to its own.
                  for (final draft in rows)
                    _DraftRow(
                      key: ValueKey(draft.id),
                      entry: draft,
                      columns: _visible,
                    ),
                ],
              ),
            ),
          ),
        ),
        _Pager(
          page: page,
          pageCount: pageCount,
          total: widget.drafts.length,
          onPage: (p) => setState(() => _page = p),
        ),
      ],
    );
  }
}

/// Under a paged table: which rows these are, and the way to the others.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.pageCount,
    required this.total,
    required this.onPage,
  });

  final int page;
  final int pageCount;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();
    final first = page * _tablePageSize + 1;
    final last = ((page + 1) * _tablePageSize).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${formatCountId(first)}–${formatCountId(last)} dari '
              '${formatCountId(total)}',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ),
          IconButton(
            onPressed: page > 0 ? () => onPage(page - 1) : null,
            icon: const Icon(LucideIcons.chevronLeft, size: 18),
            tooltip: 'Halaman sebelumnya',
            visualDensity: VisualDensity.compact,
          ),
          Text(
            '${page + 1} / $pageCount',
            style: AppTypography.captionSemibold(context.appColors.onSurface),
          ),
          IconButton(
            onPressed: page < pageCount - 1 ? () => onPage(page + 1) : null,
            icon: const Icon(LucideIcons.chevronRight, size: 18),
            tooltip: 'Halaman berikutnya',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

/// The icon beside the bulk actions: which columns the table shows.
class _ColumnMenu extends StatelessWidget {
  const _ColumnMenu({required this.hidden, required this.onToggle});

  final Set<_DraftColumn> hidden;
  final ValueChanged<_DraftColumn> onToggle;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DraftColumn>(
      tooltip: 'Atur kolom',
      position: PopupMenuPosition.under,
      onSelected: onToggle,
      itemBuilder: (context) => [
        for (final column in _DraftColumn.values)
          if (column.canHide)
            PopupMenuItem(
              value: column,
              child: Row(
                children: [
                  Icon(
                    hidden.contains(column)
                        ? LucideIcons.square
                        : LucideIcons.squareCheck,
                    size: 16,
                    color: hidden.contains(column)
                        ? context.mutedForeground
                        : context.appColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    column.label,
                    style: AppTypography.bodySm(context.appColors.onSurface),
                  ),
                ],
              ),
            ),
      ],
      child: Container(
        width: 44,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.borderColor),
        ),
        child: Icon(
          LucideIcons.settings2,
          size: 18,
          color: context.mutedForeground,
        ),
      ),
    );
  }
}

/// One draft, editable in place: how many, what each cost, and a note.
class _DraftRow extends ConsumerStatefulWidget {
  const _DraftRow({super.key, required this.entry, required this.columns});

  final InventoryEntry entry;

  /// Only the columns the table is showing, in order.
  final List<_DraftColumn> columns;

  @override
  ConsumerState<_DraftRow> createState() => _DraftRowState();
}

class _DraftRowState extends ConsumerState<_DraftRow> {
  late final TextEditingController _price = TextEditingController(
    text: widget.entry.unitPrice == 0
        ? ''
        : formatCountId(widget.entry.unitPrice),
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.entry.notes ?? '',
  );
  late int _quantity = widget.entry.quantity;
  bool _busy = false;

  @override
  void dispose() {
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _priceValue =>
      int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  /// Writes the row as it stands. Called when a field is done being edited
  /// rather than on every keystroke — a draft is a scratch pad, and saving
  /// each character would be a write per digit.
  ///
  /// Tracked in [_pendingDraftWrites] until it lands, so "Simpan Semua" —
  /// whose tap is what ends the edit — waits for it rather than confirming
  /// the row as it was before.
  Future<void> _commit() {
    final write = _write();
    _pendingDraftWrites.add(write);
    return write.whenComplete(() => _pendingDraftWrites.remove(write));
  }

  Future<void> _write() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final notes = _notes.text.trim();
    final error = await ref
        .read(portfolioRepositoryProvider)
        .updateDraftRecord(
          userId: user.id,
          recordId: widget.entry.id,
          quantity: _quantity,
          unitPrice: _priceValue,
          notes: notes,
        );
    // Written into the list rather than re-reading it: after a large sync
    // that list is thousands of rows, and this runs on every edit.
    if (error == null) {
      ref
          .read(inventoryDraftsProvider.notifier)
          .patch(
            widget.entry.copyWith(
              quantity: _quantity,
              unitPrice: _priceValue,
              notes: notes,
            ),
          );
    } else {
      ref.invalidate(inventoryDraftsProvider);
    }
  }

  Future<void> _confirm() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    setState(() => _busy = true);
    // Whatever is on screen is what gets saved, including an edit still in
    // the field.
    await _commit();
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .confirmInventoryDraft(
          userId: user.id,
          recordId: widget.entry.id,
          cardId: widget.entry.card.id,
          quantity: _quantity,
          unitPrice: _priceValue,
          synced: widget.entry.isSynced,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error), persist: false));
    }
  }

  Future<void> _delete() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    setState(() => _busy = true);
    await ref
        .read(portfolioRepositoryProvider)
        .deleteDraftRecord(userId: user.id, recordId: widget.entry.id);
    ref.invalidate(inventoryDraftsProvider);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final card = widget.entry.card;
    final total = _priceValue * _quantity;

    Widget cell(_DraftColumn column) => SizedBox(
      width: column.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _cellFor(column, card: card, total: total, colors: colors),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [for (final column in widget.columns) cell(column)],
      ),
    );
  }

  Widget _cellFor(
    _DraftColumn column, {
    required CardModel card,
    required int total,
    required ColorScheme colors,
  }) {
    switch (column) {
      case _DraftColumn.status:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: context.appSemantic.condMp.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
            child: Text(
              'Draft',
              style: AppTypography.badge(context.appSemantic.condMp),
            ),
          ),
        );

      case _DraftColumn.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xs),
          child: SizedBox(
            width: 44,
            height: 32,
            // The artwork, cropped the way the seller table crops it.
            child: CardArt(
              imageUrl: card.imageUrl,
              size: ImageSize.half,
              aspectRatio: 44 / 32,
              alignment: const Alignment(0, -0.55),
            ),
          ),
        );

      case _DraftColumn.name:
        return Row(
          children: [
            CardLanguageBadge(language: card.language, size: 13),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                card.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm(colors.primary),
              ),
            ),
          ],
        );

      case _DraftColumn.expansion:
        return Text(
          card.expansionCode.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySm(colors.onSurface),
        );

      case _DraftColumn.number:
        return Text(
          card.collectorNumber,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySm(colors.onSurface),
        );

      case _DraftColumn.rarity:
        return Text(
          card.rarity ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySm(context.mutedForeground),
        );

      case _DraftColumn.quantity:
        return QuantitySelector(
          value: _quantity,
          min: 1,
          size: QuantitySelectorSize.sm,
          enabled: !_busy,
          onChanged: (value) {
            setState(() => _quantity = value);
            _commit();
          },
        );

      case _DraftColumn.unitPrice:
        return TextField(
          controller: _price,
          keyboardType: TextInputType.number,
          enabled: !_busy,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            const PriceInputFormatter(),
          ],
          onChanged: (_) => setState(() {}),
          onEditingComplete: _commit,
          onTapOutside: (_) => _commit(),
          style: AppTypography.caption(colors.onSurface),
          decoration: const InputDecoration(
            prefixText: 'Rp ',
            hintText: '0',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        );

      case _DraftColumn.totalPrice:
        return Text(
          // "–" until there is a price to multiply, as web shows it.
          total <= 0 ? '–' : formatRupiah(total),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySmSemibold(colors.onSurface),
        );

      case _DraftColumn.notes:
        return TextField(
          controller: _notes,
          enabled: !_busy,
          onEditingComplete: _commit,
          onTapOutside: (_) => _commit(),
          style: AppTypography.caption(colors.onSurface),
          decoration: const InputDecoration(
            hintText: '–',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        );

      case _DraftColumn.actions:
        return Row(
          children: [
            _RowAction(
              icon: LucideIcons.check,
              tint: context.appSemantic.success,
              tooltip: 'Simpan draft ini',
              onPressed: _busy ? null : _confirm,
            ),
            const SizedBox(width: 6),
            _RowAction(
              icon: LucideIcons.x,
              tint: colors.error,
              tooltip: 'Hapus draft ini',
              onPressed: _busy ? null : _delete,
            ),
          ],
        );
    }
  }
}

/// The tinted square buttons that close a draft row.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.tint,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color tint;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 32,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withValues(alpha: onPressed == null ? 0.05 : 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: tint.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, size: 16, color: tint),
        ),
      ),
    );
  }
}

class _AddDraftSheet extends StatefulWidget {
  const _AddDraftSheet({required this.card});

  final CardModel card;

  @override
  State<_AddDraftSheet> createState() => _AddDraftSheetState();
}

class _AddDraftSheetState extends State<_AddDraftSheet> {
  // Always a fresh draft now: editing one happens in the table itself.
  int _quantity = 1;
  late final _priceController = TextEditingController(text: '');

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 48,
                child: CardArt(
                  imageUrl: widget.card.imageUrl,
                  size: ImageSize.half,
                  borderRadius: AppRadius.sm,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.card.name,
                      style: AppTypography.bodySmSemibold(
                        context.appColors.onSurface,
                      ),
                    ),
                    Text(
                      widget.card.collectorNumber,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Jumlah', style: AppTypography.caption(context.mutedForeground)),
          const SizedBox(height: 6),
          QuantitySelector(
            value: _quantity,
            min: 1,
            onChanged: (v) => setState(() => _quantity = v),
          ),
          const SizedBox(height: 12),
          Text(
            'Harga beli (opsional)',
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(prefixText: 'Rp '),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop((
                quantity: _quantity,
                unitPrice: int.tryParse(_priceController.text) ?? 0,
              )),
              child: const Text('Tambah ke Draft'),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- Hapuskan

class _RemoveSection extends ConsumerStatefulWidget {
  const _RemoveSection();

  @override
  ConsumerState<_RemoveSection> createState() => _RemoveSectionState();
}

class _RemoveSectionState extends ConsumerState<_RemoveSection> {
  String _query = '';
  final Set<int> _selectedCardIds = {};
  final Map<int, int> _removeQty = {};
  bool _removing = false;

  Future<void> _confirmAndRemove(List<_InventoryGroup> groups) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Hapus inventori?'),
        content: Text(
          '${_selectedCardIds.length} kartu terpilih akan dihapus dari inventori.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    setState(() => _removing = true);
    final items = <({int recordId, int delQty, int cardId})>[];
    for (final cardId in _selectedCardIds) {
      final group = groups.firstWhere((g) => g.card.id == cardId);
      var remaining = _removeQty[cardId] ?? group.totalQty;
      final sortedRecords = [...group.records]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final r in sortedRecords) {
        if (remaining <= 0) break;
        final take = remaining < r.quantity ? remaining : r.quantity;
        items.add((recordId: r.id, delQty: take, cardId: cardId));
        remaining -= take;
      }
    }

    final error = await ref
        .read(cardOwnershipControllerProvider)
        .removeInventory(userId: user.id, items: items);
    if (!mounted) return;
    setState(() {
      _removing = false;
      _selectedCardIds.clear();
      _removeQty.clear();
    });
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Inventori dihapus')));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventoryRecordsProvider);
    return async.when(
      data: (records) {
        if (records.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.package,
            title: 'Inventori kosong',
          );
        }
        final groups = _groupByCard(records);
        final visible = _query.isEmpty
            ? groups
            : groups
                  .where(
                    (g) => g.card.name.toLowerCase().contains(
                      _query.toLowerCase(),
                    ),
                  )
                  .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppSearchField(
                hintText: 'Cari kartu untuk dihapus...',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final g = visible[i];
                  final selected = _selectedCardIds.contains(g.card.id);
                  final qty = _removeQty[g.card.id] ?? g.totalQty;
                  return _RemoveGroupTile(
                    group: g,
                    selected: selected,
                    quantity: qty,
                    onToggle: () => setState(() {
                      if (selected) {
                        _selectedCardIds.remove(g.card.id);
                        _removeQty.remove(g.card.id);
                      } else {
                        _selectedCardIds.add(g.card.id);
                        _removeQty[g.card.id] = g.totalQty;
                      }
                    }),
                    onQuantityChanged: (v) => setState(
                      () => _removeQty[g.card.id] = v.clamp(1, g.totalQty),
                    ),
                  );
                },
              ),
            ),
            if (_selectedCardIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _removing
                        ? null
                        : () => _confirmAndRemove(groups),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.appColors.error,
                    ),
                    child: _removing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('Hapus Terpilih (${_selectedCardIds.length})'),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat inventori')),
    );
  }
}

class _RemoveGroupTile extends StatelessWidget {
  const _RemoveGroupTile({
    required this.group,
    required this.selected,
    required this.quantity,
    required this.onToggle,
    required this.onQuantityChanged,
  });

  final _InventoryGroup group;
  final bool selected;
  final int quantity;
  final VoidCallback onToggle;
  final ValueChanged<int> onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: selected
              ? colors.error.withValues(alpha: 0.4)
              : context.borderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              children: [
                Checkbox(value: selected, onChanged: (_) => onToggle()),
                SizedBox(
                  width: 40,
                  child: CardArt(
                    imageUrl: group.card.imageUrl,
                    size: ImageSize.half,
                    borderRadius: AppRadius.sm,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.card.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      Text(
                        'Dimiliki ×${group.totalQty}',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Row(
                children: [
                  Text(
                    'Jumlah dihapus: ',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  QuantitySelector(
                    value: quantity,
                    min: 1,
                    max: group.totalQty,
                    onChanged: onQuantityChanged,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- Aktivitas

class _ActivitySection extends ConsumerStatefulWidget {
  const _ActivitySection();

  @override
  ConsumerState<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends ConsumerState<_ActivitySection> {
  String _query = '';
  Timer? _debounce;
  _ActSort _sort = _ActSort.initial;
  int _page = 0;

  // A long-kept inventory has a long trail; filtering and sorting it again
  // is left for when the trail, the search or the sort change.
  ({List<InventoryActivityEntry> rows, String query, _ActSort sort})? _shownFor;
  List<InventoryActivityEntry> _shown = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Picks a date range, then shares that stretch of the trail as a CSV —
  /// all of it, whatever the search on screen is narrowed to.
  Future<void> _export(
    List<InventoryActivityEntry> activity,
    Rect? origin,
  ) async {
    final picked = await showModalBottomSheet<({DateTimeRange? range})>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _ExportSheet(rows: activity),
    );
    if (picked == null || !mounted) return;

    final rows = activityInRange(activity, picked.range);
    try {
      await ref.read(csvSharerProvider)(
        activityExportFileName(picked.range),
        activityCsv(rows),
        origin,
      );
    } catch (e, st) {
      debugPrint('[inventory] export failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengekspor aktivitas.')),
      );
    }
  }

  /// Web's `filteredActivity`: the search looks through what the row shows,
  /// prices and the date included.
  List<InventoryActivityEntry> _visible(List<InventoryActivityEntry> rows) {
    final cached = _shownFor;
    if (cached != null &&
        identical(cached.rows, rows) &&
        cached.query == _query &&
        identical(cached.sort, _sort)) {
      return _shown;
    }
    final needle = _query.trim().toLowerCase();
    final shown = needle.isEmpty
        ? [...rows]
        : rows.where((r) {
            final card = r.card;
            return card.name.toLowerCase().contains(needle) ||
                card.expansionCode.toLowerCase().contains(needle) ||
                card.collectorNumber.toLowerCase().contains(needle) ||
                (card.rarity?.toLowerCase().contains(needle) ?? false) ||
                (r.series?.toLowerCase().contains(needle) ?? false) ||
                formatRupiah(r.unitPrice).toLowerCase().contains(needle) ||
                formatRupiah(
                  r.unitPrice * r.quantity,
                ).toLowerCase().contains(needle) ||
                formatSaleDate(
                  r.createdAt.toLocal(),
                ).toLowerCase().contains(needle);
          }).toList();
    shown.sort(_sort.compare);
    _shownFor = (rows: rows, query: _query, sort: _sort);
    return _shown = shown;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventoryActivityProvider);
    final config = ref.watch(inventoryColumnsProvider).valueOrNull ?? const [];
    return async.when(
      data: (activity) {
        if (activity.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.history,
            title: 'Belum ada aktivitas',
          );
        }
        final visible = _visible(activity);
        final pageCount = (visible.length / _tablePageSize).ceil();
        final page = _page.clamp(0, pageCount == 0 ? 0 : pageCount - 1);
        final start = page * _tablePageSize;
        final rows = visible.sublist(
          start,
          (start + _tablePageSize).clamp(0, visible.length),
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: AppSearchField(
                      hintText: 'Cari nama, ekspansi, nomor, harga, tanggal...',
                      onChanged: (v) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 250),
                          () {
                            if (mounted) {
                              setState(() {
                                _query = v;
                                _page = 0;
                              });
                            }
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Its own context, so the share sheet can anchor to it.
                  Builder(
                    builder: (button) => IconButton.outlined(
                      onPressed: () => _export(activity, shareOriginOf(button)),
                      icon: const Icon(LucideIcons.download, size: 18),
                      tooltip: 'Ekspor',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        'Tidak ada aktivitas yang cocok dengan pencarian.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        AppBottomNav.reservedSpace(context) + 12,
                      ),
                      children: [
                        _ActivityTable(
                          rows: rows,
                          config: config,
                          sort: _sort,
                          // A new order starts again from its first page.
                          onSort: (sort) => setState(() {
                            _sort = sort;
                            _page = 0;
                          }),
                        ),
                        _Pager(
                          page: page,
                          pageCount: pageCount,
                          total: visible.length,
                          onPage: (p) => setState(() => _page = p),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat aktivitas')),
    );
  }
}

/// The ranges the export offers before a calendar is needed.
enum _ExportPreset {
  all('Semua'),
  week('7 hari terakhir'),
  month('30 hari terakhir'),
  thisMonth('Bulan ini'),
  custom('Pilih tanggal');

  const _ExportPreset(this.label);

  final String label;

  /// The days it covers up to [today], both ends included; null for all.
  DateTimeRange? rangeUntil(DateTime today) => switch (this) {
    _ExportPreset.all || _ExportPreset.custom => null,
    _ExportPreset.week => DateTimeRange(
      start: today.subtract(const Duration(days: 6)),
      end: today,
    ),
    _ExportPreset.month => DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    ),
    _ExportPreset.thisMonth => DateTimeRange(
      start: DateTime(today.year, today.month),
      end: today,
    ),
  };
}

/// Which stretch of the trail to export, with how many rows it holds.
/// Pops with the range — null for everything — or nothing on Batal.
class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.rows});

  final List<InventoryActivityEntry> rows;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  _ExportPreset _preset = _ExportPreset.all;
  DateTimeRange? _custom;

  DateTime get _today => DateUtils.dateOnly(DateTime.now());

  DateTimeRange? get _range =>
      _preset == _ExportPreset.custom ? _custom : _preset.rangeUntil(_today);

  Future<void> _pickDates() async {
    final initial = _custom ?? _preset.rangeUntil(_today);
    // The calendar opens at the oldest activity — or earlier, where the
    // range it opens on starts before that: a picker handed a range outside
    // its own days refuses to open at all.
    var first = _today;
    for (final r in widget.rows) {
      final day = DateUtils.dateOnly(r.createdAt.toLocal());
      if (day.isBefore(first)) first = day;
    }
    if (initial != null && initial.start.isBefore(first)) {
      first = initial.start;
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: _today,
      initialDateRange: initial,
      helpText: 'Pilih rentang tanggal',
      saveText: 'Pilih',
      cancelText: 'Batal',
      confirmText: 'Pilih',
      fieldStartLabelText: 'Dari',
      fieldEndLabelText: 'Sampai',
      fieldStartHintText: 'Dari',
      fieldEndHintText: 'Sampai',
      errorFormatText: 'Format tanggal salah',
      errorInvalidText: 'Di luar rentang',
      errorInvalidRangeText: 'Rentang tidak valid',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _custom = picked;
      _preset = _ExportPreset.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final range = _range;
    // Pilih tanggal with no dates picked yet has nothing to export.
    final waiting = _preset == _ExportPreset.custom && range == null;
    final count = waiting ? 0 : activityInRange(widget.rows, range).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ekspor aktivitas', style: AppTypography.h3(colors.onSurface)),
            const SizedBox(height: 4),
            Text(
              'Hasil ekspor akan disimpan dalam format csv.',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _ExportPreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: _preset == preset,
                    onSelected: (_) {
                      if (preset == _ExportPreset.custom) {
                        _pickDates();
                      } else {
                        setState(() => _preset = preset);
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (range != null)
              InkWell(
                onTap: _pickDates,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.calendar,
                        size: 16,
                        color: context.mutedForeground,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${formatSaleDate(range.start)} – '
                        '${formatSaleDate(range.end)}',
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                    ],
                  ),
                ),
              ),
            Text(
              waiting
                  ? 'Pilih tanggal untuk diekspor.'
                  : count == 0
                  ? 'Tidak ada aktivitas di rentang ini.'
                  : '${formatCountId(count)} aktivitas akan diekspor.',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text('Batal'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: count == 0
                        ? null
                        : () => Navigator.of(context).pop((range: range)),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text('Ekspor CSV'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
