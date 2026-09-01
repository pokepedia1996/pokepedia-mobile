import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/card_ownership_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/card_language_badge.dart';
import '../../../../shared/widgets/quantity_selector.dart';
import '../../repository/models/scan_models.dart';
import '../../repository/scanner_repository.dart';
import '../../usecase/scan_session_notifier.dart';
import 'scan_card_search_sheet.dart';
import 'scan_card_thumb.dart';
import 'scan_variant_strip.dart';

/// Ports `ScanSessionSheet` — the batch as an editable list, and the only path
/// out of the scanner into either destination.
///
/// Rows that need a human decision sort to the top, so a long scanning run can
/// be corrected in one pass at the end rather than interrupting every capture.
/// That ordering is what makes imperfect recognition tolerable: nothing forces
/// the user to resolve a card before moving to the next one.
class ScanSessionSheet extends ConsumerStatefulWidget {
  const ScanSessionSheet({
    super.key,
    required this.onClose,
    required this.onSelectVariant,
  });

  final VoidCallback onClose;
  final void Function(ScanSessionItem item, ScanCard card) onSelectVariant;

  @override
  ConsumerState<ScanSessionSheet> createState() => _ScanSessionSheetState();
}

enum _Submitting { collection, listing }

class _ScanSessionSheetState extends ConsumerState<ScanSessionSheet> {
  /// Inverted so "select all" is the default with no bookkeeping: a freshly
  /// scanned row is selected the moment it exists, nothing has to be added
  /// here, and a stale id (row already deleted) is simply inert.
  final _excluded = <String>{};

  String? _expandedTempId;
  _Submitting? _submitting;

  bool _isSelected(String tempId) => !_excluded.contains(tempId);

  void _toggleSelect(String tempId) => setState(() {
    if (!_excluded.remove(tempId)) _excluded.add(tempId);
  });

  /// Quantities summed per `card_id`, so the same card scanned twice is one
  /// `+2` rather than two racing `+1`s against the same row.
  Map<int, int> _quantityByCardId(List<ScanSessionItem> selected) {
    final quantities = <int, int>{};
    for (final item in selected) {
      quantities[item.card.id] = (quantities[item.card.id] ?? 0) + item.quantity;
    }
    return quantities;
  }

  Future<void> _addAllToCollection(List<ScanSessionItem> selected) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null || selected.isEmpty) return;

    setState(() => _submitting = _Submitting.collection);
    final quantities = _quantityByCardId(selected);

    // One call per distinct card, through the same controller every other
    // ownership mutation uses — so the collection and portfolio screens
    // revalidate without this sheet knowing they exist.
    final failed = <int>{};
    for (final entry in quantities.entries) {
      final error = await ref
          .read(cardOwnershipControllerProvider)
          .adjustQuantity(
            userId: user.id,
            cardId: entry.key,
            delta: entry.value,
          );
      if (error != null) failed.add(entry.key);
    }
    if (!mounted) return;
    setState(() => _submitting = null);

    // Only what actually landed leaves the session, so a partial failure is
    // retryable instead of silently losing scans.
    ref
        .read(scanSessionProvider.notifier)
        .removeItems(
          selected
              .where((it) => !failed.contains(it.card.id))
              .map((it) => it.tempId),
        );

    if (failed.isNotEmpty) {
      _toast('${failed.length} kartu gagal ditambahkan, coba lagi');
      return;
    }
    final count = quantities.values.fold(0, (a, b) => a + b);
    _toast('$count kartu ditambahkan ke koleksi');
    widget.onClose();
  }

  Future<void> _sendToDraftListings(List<ScanSessionItem> selected) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null || selected.isEmpty) return;

    setState(() => _submitting = _Submitting.listing);
    final result = await ref
        .read(scannerRepositoryProvider)
        .importDraftListings(
          userId: user.id,
          quantityByCardId: _quantityByCardId(selected),
        );
    if (!mounted) return;
    setState(() => _submitting = null);

    if (result.error != null) {
      _toast(result.error!);
      return;
    }

    // Cards the RPC skipped — trading-blocked, or already listed — stay in the
    // session so they're still available via "Tambah ke koleksi".
    final inserted = result.insertedCardIds.toSet();
    ref
        .read(scanSessionProvider.notifier)
        .removeItems(
          selected
              .where((it) => inserted.contains(it.card.id))
              .map((it) => it.tempId),
        );

    if (inserted.isEmpty) {
      _toast('Tidak ada kartu yang bisa dijadikan draft');
      return;
    }
    _toast(
      inserted.length == selected.length
          ? '${inserted.length} kartu dijadikan draft'
          : '${inserted.length} dari ${selected.length} kartu dijadikan draft',
    );
    widget.onClose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<void> _openSearch(ScanSessionItem item) async {
    final picked = await showModalBottomSheet<ScanCard>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The sheet's own context, not this widget's — popping the outer one
      // would dismiss the scanner instead of the search sheet.
      builder: (sheetContext) => ScanCardSearchSheet(
        language: item.card.language,
        onSelect: (card) => Navigator.of(sheetContext).pop(card),
      ),
    );
    if (picked != null && mounted) {
      widget.onSelectVariant(item, picked);
      setState(() => _expandedTempId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(scanSessionProvider);
    final prices = ref.watch(scanSessionPricesProvider).valueOrNull;

    // Unresolved rows first — the point of the whole sheet.
    final sorted = [...items]
      ..sort(
        (a, b) => (b.needsReview ? 1 : 0).compareTo(a.needsReview ? 1 : 0),
      );

    final selected = items.where((it) => _isSelected(it.tempId)).toList();
    final selectedCount = selected.fold(0, (sum, it) => sum + it.quantity);
    final totalCards = items.fold(0, (sum, it) => sum + it.quantity);
    final allSelected = items.isNotEmpty && selected.length == items.length;
    final busy = _submitting != null;

    return Positioned.fill(
      child: ColoredBox(
        color: context.appColors.surface,
        child: SafeArea(
          child: Column(
            children: [
              _Header(total: totalCards, onClose: widget.onClose),
              if (items.isNotEmpty)
                CheckboxListTile(
                  value: allSelected,
                  tristate: false,
                  onChanged: busy
                      ? null
                      : (_) => setState(() {
                          _excluded
                            ..clear()
                            ..addAll(
                              allSelected ? items.map((it) => it.tempId) : [],
                            );
                        }),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Pilih semua ($selectedCount)',
                    style: AppTypography.bodySmSemibold(
                      context.appColors.onSurface,
                    ),
                  ),
                ),
              Expanded(
                child: sorted.isEmpty
                    ? Center(
                        child: Text(
                          'Belum ada kartu dipindai',
                          style: AppTypography.bodySm(context.mutedForeground),
                        ),
                      )
                    : ListView.separated(
                        itemCount: sorted.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: context.borderColor,
                        ),
                        itemBuilder: (context, index) {
                          final item = sorted[index];
                          return _SessionRow(
                            item: item,
                            price: prices?[item.card.id]?.price,
                            selected: _isSelected(item.tempId),
                            expanded: _expandedTempId == item.tempId,
                            enabled: !busy,
                            onToggleSelect: () => _toggleSelect(item.tempId),
                            onToggleStrip: () => setState(() {
                              _expandedTempId =
                                  _expandedTempId == item.tempId
                                  ? null
                                  : item.tempId;
                            }),
                            onSelectVariant: (card) {
                              widget.onSelectVariant(item, card);
                              setState(() => _expandedTempId = null);
                            },
                            onOpenSearch: () => _openSearch(item),
                            onSetQuantity: (quantity) => ref
                                .read(scanSessionProvider.notifier)
                                .setQuantity(item.tempId, quantity),
                            onRemove: () => ref
                                .read(scanSessionProvider.notifier)
                                .removeItem(item.tempId),
                          );
                        },
                      ),
              ),
              _Actions(
                selectedCount: selectedCount,
                submitting: _submitting,
                onAddToCollection: () => _addAllToCollection(selected),
                onSendToDrafts: () => _sendToDraftListings(selected),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.total, required this.onClose});

  final int total;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          Text(
            'Kelola kartu ($total)',
            style: AppTypography.bodySemibold(context.appColors.onSurface),
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            tooltip: 'Tutup',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.item,
    required this.price,
    required this.selected,
    required this.expanded,
    required this.enabled,
    required this.onToggleSelect,
    required this.onToggleStrip,
    required this.onSelectVariant,
    required this.onOpenSearch,
    required this.onSetQuantity,
    required this.onRemove,
  });

  final ScanSessionItem item;
  final int? price;
  final bool selected;
  final bool expanded;
  final bool enabled;
  final VoidCallback onToggleSelect;
  final VoidCallback onToggleStrip;
  final ValueChanged<ScanCard> onSelectVariant;
  final VoidCallback onOpenSearch;
  final ValueChanged<int> onSetQuantity;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final card = item.card;
    final language = card.language;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: enabled ? (_) => onToggleSelect() : null,
              ),
              Expanded(
                child: InkWell(
                  onTap: enabled ? onToggleStrip : null,
                  child: Row(
                    children: [
                      ScanCardThumb(card: card, width: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (language != null) ...[
                                  CardLanguageBadge(
                                    language: language,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 5),
                                ],
                                Flexible(
                                  child: Text(
                                    card.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.bodySmSemibold(
                                      context.appColors.onSurface,
                                    ),
                                  ),
                                ),
                                Icon(
                                  expanded
                                      ? Icons.expand_more
                                      : Icons.chevron_right,
                                  size: 15,
                                  color: context.mutedForeground,
                                ),
                              ],
                            ),
                            Text(
                              [
                                card.printingLabel,
                                if (card.variantLabel != null)
                                  card.variantLabel!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                            Text(
                              price == null ? 'Rp-' : formatRupiah(price!),
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              QuantitySelector(
                value: item.quantity,
                max: 99,
                onChanged: enabled ? onSetQuantity : (_) {},
              ),
              IconButton(
                onPressed: enabled ? onRemove : null,
                tooltip: 'Hapus',
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: context.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ScanVariantStrip(
              selected: card,
              variants: item.variants.isNotEmpty ? item.variants : [card],
              onSelect: onSelectVariant,
              onSearch: onOpenSearch,
            ),
          ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.selectedCount,
    required this.submitting,
    required this.onAddToCollection,
    required this.onSendToDrafts,
  });

  final int selectedCount;
  final _Submitting? submitting;
  final VoidCallback onAddToCollection;
  final VoidCallback onSendToDrafts;

  @override
  Widget build(BuildContext context) {
    final disabled = selectedCount == 0 || submitting != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: disabled ? null : onAddToCollection,
              child: submitting == _Submitting.collection
                  ? const _ButtonSpinner()
                  : Text('Tambah ke koleksi ($selectedCount)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: disabled ? null : onSendToDrafts,
              child: submitting == _Submitting.listing
                  ? const _ButtonSpinner()
                  : Text('Jadikan draft jual ($selectedCount)'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 16,
    height: 16,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
