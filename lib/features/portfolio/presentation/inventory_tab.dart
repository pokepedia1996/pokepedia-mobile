import '../../../shared/widgets/app_search_field.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
import '../../../shared/widgets/card_art.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/card_language_badge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/quantity_selector.dart';
import '../repository/models/inventory_entry.dart';
import '../usecase/portfolio_notifier.dart';

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

// ---------------------------------------------------------------- Database

class _DatabaseSection extends ConsumerStatefulWidget {
  const _DatabaseSection();

  @override
  ConsumerState<_DatabaseSection> createState() => _DatabaseSectionState();
}

class _DatabaseSectionState extends ConsumerState<_DatabaseSection> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventoryRecordsProvider);
    return async.when(
      data: (records) {
        if (records.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.package,
            title: 'Inventori kosong',
            description: 'Tambahkan kartu lewat tab Tambahkan.',
          );
        }
        final groups = _groupByCard(records);
        final needle = _query.trim().toLowerCase();
        final visible = needle.isEmpty
            ? groups
            : groups.where((g) {
                return g.card.name.toLowerCase().contains(needle) ||
                    g.card.collectorNumber.toLowerCase().contains(needle) ||
                    g.card.expansionCode.toLowerCase().contains(needle);
              }).toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppSearchField(
                hintText: 'Cari nama, ekspansi, atau nomor...',
                onChanged: (v) => setState(() => _query = v),
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
                      children: [_RecordTable(groups: visible)],
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

/// The Database tab's table — what is actually held, a row per card.
///
/// Web's columns, minus the ones that would only ever repeat: every row here
/// is a saved record, so "Status" says the same thing on all of them, and
/// the sort/pagination controls belong to a screen with a mouse.
class _RecordTable extends StatelessWidget {
  const _RecordTable({required this.groups});

  final List<_InventoryGroup> groups;

  static const _headers = <({String label, double width})>[
    (label: 'Gambar', width: 64),
    (label: 'Nama Kartu', width: 140),
    (label: 'Ekspansi', width: 84),
    (label: 'Nomor', width: 88),
    (label: 'Kelangkaan', width: 104),
    (label: 'Jumlah', width: 64),
    (label: 'Harga Satuan', width: 104),
    (label: 'Harga Total', width: 108),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return _TableFrame(
      headers: _headers,
      rows: [
        for (final group in groups)
          [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: SizedBox(
                width: 44,
                height: 32,
                child: CardArt(
                  imageUrl: group.card.imageUrl,
                  aspectRatio: 44 / 32,
                  alignment: const Alignment(0, -0.55),
                ),
              ),
            ),
            Row(
              children: [
                CardLanguageBadge(language: group.card.language, size: 13),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    group.card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ),
              ],
            ),
            Text(
              group.card.expansionCode.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(colors.onSurface),
            ),
            Text(
              group.card.collectorNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(colors.onSurface),
            ),
            Text(
              group.card.rarity ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            Text(
              '${group.totalQty}',
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
            Text(
              // The average of what the copies cost, which is what a
              // grouped row can honestly say about a unit price.
              formatRupiah(group.avgPrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(colors.onSurface),
            ),
            Text(
              formatRupiah(group.totalValue),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
          ],
      ],
    );
  }
}

/// The Aktivitas tab's table — ports `features/inventory/components/
/// activity-table.tsx`, in its column order: when, what, and to which card.
class _ActivityTable extends StatelessWidget {
  const _ActivityTable({required this.rows});

  final List<InventoryActivityEntry> rows;

  static const _headers = <({String label, double width})>[
    (label: 'Tanggal', width: 104),
    (label: 'Aksi', width: 104),
    (label: 'Jumlah', width: 64),
    (label: 'Nama Kartu', width: 140),
    (label: 'Ekspansi', width: 84),
    (label: 'Nomor', width: 88),
    (label: 'Kelangkaan', width: 104),
    (label: 'Harga Satuan', width: 104),
    (label: 'Harga Total', width: 108),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return _TableFrame(
      headers: _headers,
      rows: [
        for (final row in rows)
          [
            // Web prints the date and the clock together; stacked, because a
            // phone column has the height to spare and not the width.
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatShortDateId(row.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySm(colors.onSurface),
                ),
                Text(
                  formatClockId(row.createdAt),
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
            _ActionPill(action: row.action),
            Text(
              '${row.quantity}',
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
            Row(
              children: [
                CardLanguageBadge(language: row.card.language, size: 13),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    row.card.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySm(colors.onSurface),
                  ),
                ),
              ],
            ),
            Text(
              row.card.expansionCode.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(colors.onSurface),
            ),
            Text(
              row.card.collectorNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(colors.onSurface),
            ),
            Text(
              row.card.rarity ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            Text(
              formatRupiah(row.unitPrice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySm(colors.onSurface),
            ),
            Text(
              formatRupiah(row.unitPrice * row.quantity),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
          ],
      ],
    );
  }
}

/// What happened, as a tinted word rather than an icon in a column of them.
class _ActionPill extends StatelessWidget {
  const _ActionPill({required this.action});

  final InventoryActivityAction action;

  @override
  Widget build(BuildContext context) {
    final (label, tint) = switch (action) {
      InventoryActivityAction.addedIn => (
        'Ditambahkan',
        context.appSemantic.success,
      ),
      InventoryActivityAction.removedOut => (
        'Dihapus',
        context.appColors.error,
      ),
      InventoryActivityAction.updated => (
        'Diperbarui',
        context.mutedForeground,
      ),
    };

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(label, style: AppTypography.badge(tint)),
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

  void _onSearchChanged(String v) {
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

  /// Clears the staging table. Confirmed first: it is the one button here
  /// that throws work away.
  Future<void> _deleteAll(List<InventoryEntry> drafts) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    await showConfirmDialog(
      context,
      title: 'Hapus semua?',
      description:
          '${drafts.length} draft akan dibuang. Kartu yang sudah disimpan '
          'ke inventori tidak terpengaruh.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () async {
        final repository = ref.read(portfolioRepositoryProvider);
        for (final draft in drafts) {
          await repository.deleteDraftRecord(
            userId: user.id,
            recordId: draft.id,
          );
        }
        ref.invalidate(inventoryDraftsProvider);
      },
    );
  }

  Future<void> _saveAll(List<InventoryEntry> drafts) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    var failures = 0;
    for (final d in drafts) {
      final error = await ref
          .read(cardOwnershipControllerProvider)
          .confirmInventoryDraft(
            userId: user.id,
            recordId: d.id,
            cardId: d.card.id,
            quantity: d.quantity,
            unitPrice: d.unitPrice,
          );
      if (error != null) failures++;
    }
    if (!mounted) return;
    final saved = drafts.length - failures;
    final message = failures == 0
        ? '$saved inventori ditambahkan'
        : '$saved ditambahkan, $failures gagal';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final draftsAsync = ref.watch(inventoryDraftsProvider);
    final showResults = _debouncedQuery.trim().length >= 2;
    final resultsAsync = showResults
        ? ref.watch(cardSearchPickerProvider(_debouncedQuery))
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        AppSearchField(
          hintText: 'Cari kartu untuk ditambahkan...',
          controller: _searchController,
          onChanged: _onSearchChanged,
        ),
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
                  child: CardArt(imageUrl: card.imageUrl),
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
class _TableFrame extends StatelessWidget {
  const _TableFrame({required this.headers, required this.rows});

  final List<({String label, double width})> headers;

  /// One list of cells per row, in the headers' order.
  final List<List<Widget>> rows;

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
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    for (final header in headers)
                      SizedBox(
                        width: header.width,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            header.label,
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
              for (final row in rows)
                Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: context.borderColor)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < row.length; i++)
                        SizedBox(
                          width: headers[i].width,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: row[i],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
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
class _DraftTable extends StatefulWidget {
  const _DraftTable({
    required this.drafts,
    required this.onSaveAll,
    required this.onDeleteAll,
  });

  final List<InventoryEntry> drafts;
  final VoidCallback onSaveAll;
  final VoidCallback onDeleteAll;

  @override
  State<_DraftTable> createState() => _DraftTableState();
}

class _DraftTableState extends State<_DraftTable> {
  /// Held here rather than on the server: web persists a column config per
  /// user, which is worth having when you keep a spreadsheet open all day.
  /// A phone session is a batch, and a batch is over before a preference
  /// would pay for itself.
  final _hidden = <_DraftColumn>{};

  List<_DraftColumn> get _visible => [
    for (final column in _DraftColumn.values)
      if (!_hidden.contains(column)) column,
  ];

  double get _tableWidth => _visible.fold<double>(0, (sum, c) => sum + c.width);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Web's trio above the table: the destructive one outlined, the one
        // you came to press filled, and the columns behind an icon.
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onDeleteAll,
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
                onPressed: widget.onSaveAll,
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
                  for (final draft in widget.drafts)
                    _DraftRow(entry: draft, columns: _visible),
                ],
              ),
            ),
          ),
        ),
      ],
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
  const _DraftRow({required this.entry, required this.columns});

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
  Future<void> _commit() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    await ref
        .read(portfolioRepositoryProvider)
        .updateDraftRecord(
          userId: user.id,
          recordId: widget.entry.id,
          quantity: _quantity,
          unitPrice: _priceValue,
          notes: _notes.text.trim(),
        );
    ref.invalidate(inventoryDraftsProvider);
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

class _ActivitySection extends ConsumerWidget {
  const _ActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(inventoryActivityProvider);
    return async.when(
      data: (activity) {
        if (activity.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.history,
            title: 'Belum ada aktivitas',
          );
        }
        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            AppBottomNav.reservedSpace(context) + 12,
          ),
          children: [_ActivityTable(rows: activity)],
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat aktivitas')),
    );
  }
}
