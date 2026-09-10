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
import '../../../shared/widgets/card_art.dart';
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
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        AppBottomNav.reservedSpace(context) + 12,
                      ),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) =>
                          _InventoryGroupTile(group: visible[i]),
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

class _InventoryGroupTile extends StatelessWidget {
  const _InventoryGroupTile({required this.group});

  final _InventoryGroup group;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
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
                  '${group.card.collectorNumber} · ×${group.totalQty}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatRupiah(group.totalValue),
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
              Text(
                'Rata-rata ${formatRupiah(group.avgPrice)}',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
        ],
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
              return Column(
                children: [
                  for (final c in results)
                    _SearchResultTile(card: c, onTap: () => _openAddSheet(c)),
                ],
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Draft belum disimpan (${drafts.length})',
                        style: AppTypography.bodySmSemibold(
                          context.appColors.onSurface,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _saveAll(drafts),
                      child: const Text('Simpan Semua'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final d in drafts) _DraftTile(entry: d),
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

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.card, required this.onTap});

  final CardModel card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: CardArt(
                imageUrl: card.imageUrl,
                borderRadius: AppRadius.sm,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    '${card.collectorNumber} · ${card.expansionCode}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.circlePlus, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

class _DraftTile extends ConsumerWidget {
  const _DraftTile({required this.entry});

  final InventoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: CardArt(
              imageUrl: entry.card.imageUrl,
              borderRadius: AppRadius.sm,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                Text(
                  '×${entry.quantity} · ${formatRupiah(entry.unitPrice)}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.pencil, size: 18),
            onPressed: () async {
              final result =
                  await showModalBottomSheet<({int quantity, int unitPrice})>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => _AddDraftSheet(
                      card: entry.card,
                      initialQuantity: entry.quantity,
                      initialUnitPrice: entry.unitPrice,
                    ),
                  );
              if (result == null) return;
              final user = ref.read(authProvider).valueOrNull;
              if (user == null) return;
              await ref
                  .read(portfolioRepositoryProvider)
                  .updateDraftRecord(
                    userId: user.id,
                    recordId: entry.id,
                    quantity: result.quantity,
                    unitPrice: result.unitPrice,
                  );
              ref.invalidate(inventoryDraftsProvider);
            },
          ),
          IconButton(
            icon: Icon(
              LucideIcons.circleCheck,
              size: 18,
              color: context.appSemantic.success,
            ),
            onPressed: () async {
              final user = ref.read(authProvider).valueOrNull;
              if (user == null) return;
              final error = await ref
                  .read(cardOwnershipControllerProvider)
                  .confirmInventoryDraft(
                    userId: user.id,
                    recordId: entry.id,
                    cardId: entry.card.id,
                    quantity: entry.quantity,
                    unitPrice: entry.unitPrice,
                  );
              if (error != null && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error)));
              }
            },
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 18, color: colors.error),
            onPressed: () async {
              final user = ref.read(authProvider).valueOrNull;
              if (user == null) return;
              await ref
                  .read(portfolioRepositoryProvider)
                  .deleteDraftRecord(userId: user.id, recordId: entry.id);
              ref.invalidate(inventoryDraftsProvider);
            },
          ),
        ],
      ),
    );
  }
}

class _AddDraftSheet extends StatefulWidget {
  const _AddDraftSheet({
    required this.card,
    this.initialQuantity = 1,
    this.initialUnitPrice = 0,
  });

  final CardModel card;
  final int initialQuantity;
  final int initialUnitPrice;

  @override
  State<_AddDraftSheet> createState() => _AddDraftSheetState();
}

class _AddDraftSheetState extends State<_AddDraftSheet> {
  late int _quantity = widget.initialQuantity;
  late final _priceController = TextEditingController(
    text: widget.initialUnitPrice > 0 ? '${widget.initialUnitPrice}' : '',
  );

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
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: activity.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _ActivityTile(entry: activity[i]),
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat aktivitas')),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.entry});

  final InventoryActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (icon, color, label) = switch (entry.action) {
      InventoryActivityAction.addedIn => (
        LucideIcons.circlePlus,
        context.appSemantic.success,
        'Ditambahkan',
      ),
      InventoryActivityAction.removedOut => (
        LucideIcons.circleMinus,
        colors.error,
        'Dihapus',
      ),
      InventoryActivityAction.updated => (
        LucideIcons.pencil,
        context.mutedForeground,
        'Diperbarui',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                Text(
                  '$label ×${entry.quantity} · ${formatRupiah(entry.unitPrice)}',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
          Text(
            formatRelativeId(entry.createdAt),
            style: AppTypography.caption(context.mutedForeground),
          ),
        ],
      ),
    );
  }
}
