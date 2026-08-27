import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/card_ownership_controller.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/pikachu_loader.dart';
import '../../../../shared/widgets/quantity_selector.dart';
import '../../usecase/portfolio_notifier.dart';

/// Minimum query length before the picker searches, matching
/// `searchCardsPicker`'s own guard on the web.
const _minPickerQuery = 2;

/// Opens the "Tambah Kartu" picker. Resolves true once at least one card was
/// added, so the caller can refresh the collection.
///
/// Ports the add-card modal from `app/portfolio/collection/page.tsx`: search
/// the catalog, pick a quantity, and write straight to `user_cards`.
Future<bool?> showCollectionAddSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const _CollectionAddSheet(),
  );
}

class _CollectionAddSheet extends ConsumerStatefulWidget {
  const _CollectionAddSheet();

  @override
  ConsumerState<_CollectionAddSheet> createState() =>
      _CollectionAddSheetState();
}

class _CollectionAddSheetState extends ConsumerState<_CollectionAddSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int? _addingCardId;
  bool _addedAny = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _add(CardModel card) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final quantity = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _QuantitySheet(card: card),
    );
    if (quantity == null || quantity < 1 || !mounted) return;

    setState(() => _addingCardId = card.id);
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .adjustQuantity(userId: user.id, cardId: card.id, delta: quantity);
    if (!mounted) return;
    setState(() => _addingCardId = null);

    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _addedAny = true;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('${card.name} ×$quantity ditambahkan'),
          duration: const Duration(seconds: 2),
          persist: false,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final searching = _query.length >= _minPickerQuery;
    final resultsAsync = searching
        ? ref.watch(cardSearchPickerProvider(_query))
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_addedAny);
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tambah Kartu',
                          style: AppTypography.h3(colors.onSurface),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(_addedAny),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      hintText: 'Cari nama kartu...',
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                  ),
                ),
                Flexible(
                  child: !searching
                      ? _hint('Ketik minimal $_minPickerQuery karakter.')
                      : resultsAsync!.when(
                          data: (results) {
                            if (results.isEmpty) {
                              return _hint('Kartu tidak ditemukan.');
                            }
                            return ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                              itemCount: results.length,
                              itemBuilder: (context, i) => _ResultTile(
                                card: results[i],
                                busy: _addingCardId == results[i].id,
                                onTap: () => _add(results[i]),
                              ),
                            );
                          },
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: PikachuLoader(size: 96),
                          ),
                          error: (_, __) =>
                              _hint('Gagal memuat hasil pencarian.'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodySm(context.mutedForeground),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.card,
    required this.busy,
    required this.onTap,
  });

  final CardModel card;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: CardArt(
                imageUrl: card.imageUrl,
                borderRadius: AppRadius.xs,
              ),
            ),
            const SizedBox(width: 12),
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
                    '${card.expansionCode.toUpperCase()} · '
                    '${card.collectorNumber}',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.add_circle_outline, size: 20, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

/// How many copies to add — the quantity step of the web modal.
class _QuantitySheet extends StatefulWidget {
  const _QuantitySheet({required this.card});

  final CardModel card;

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.card.name, style: AppTypography.h3(colors.onSurface)),
            Text(
              '${widget.card.expansionCode.toUpperCase()} · '
              '${widget.card.collectorNumber}',
              style: AppTypography.caption(context.mutedForeground),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Jumlah',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
                const Spacer(),
                QuantitySelector(
                  value: _quantity,
                  min: 1,
                  onChanged: (value) => setState(() => _quantity = value),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_quantity),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              child: const Text('Tambah ke Koleksi'),
            ),
          ],
        ),
      ),
    );
  }
}
