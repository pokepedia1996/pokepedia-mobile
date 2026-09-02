import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/pikachu_loader.dart';
import '../../../expansions/presentation/widgets/place_order_sheet.dart';
import '../../../portfolio/usecase/portfolio_notifier.dart';

/// Ports `add-listing-picker.tsx` — find the card, then post the ask.
///
/// The form itself is the same `showPlaceOrderSheet` the catalog page uses
/// for "Pasang Ask (WTS)": one implementation of the gates, the photo
/// upload and the `place_order` call, whichever screen the seller started
/// from.
///
/// Returns true when a listing was posted, so the caller can refresh.
Future<bool?> showAddListingSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const _AddListingSheet(),
  );
}

/// Web's picker refuses to search on one character; so does the RPC.
const _minQuery = 2;

class _AddListingSheet extends ConsumerStatefulWidget {
  const _AddListingSheet();

  @override
  ConsumerState<_AddListingSheet> createState() => _AddListingSheetState();
}

class _AddListingSheetState extends ConsumerState<_AddListingSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _postedAny = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _pick(CardModel card) async {
    final posted = await showPlaceOrderSheet(context, card: card, side: 'ask');
    if (posted != true || !mounted) return;
    _postedAny = true;
    // Straight out on success: the seller came here to post one listing,
    // and the list behind this needs to refresh to show it.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final searching = _query.length >= _minQuery;
    final resultsAsync = searching
        ? ref.watch(cardSearchPickerProvider(_query))
        : null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_postedAny);
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
                          'Tambah Listing',
                          style: AppTypography.h3(colors.onSurface),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x),
                        onPressed: () => Navigator.of(context).pop(_postedAny),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    onChanged: _onChanged,
                    decoration: const InputDecoration(
                      hintText: 'Cari kartu yang mau dijual...',
                      prefixIcon: Icon(LucideIcons.search, size: 20),
                    ),
                  ),
                ),
                Flexible(
                  child: !searching
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          child: Text(
                            'Ketik minimal $_minQuery huruf untuk mencari.',
                            style: AppTypography.bodySm(
                              context.mutedForeground,
                            ),
                          ),
                        )
                      : resultsAsync!.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: PikachuLoader(),
                          ),
                          error: (_, __) => Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            child: Text(
                              'Gagal mencari kartu.',
                              style: AppTypography.bodySm(
                                context.mutedForeground,
                              ),
                            ),
                          ),
                          data: (cards) {
                            if (cards.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  8,
                                  20,
                                  32,
                                ),
                                child: Text(
                                  'Tidak ada kartu yang cocok.',
                                  style: AppTypography.bodySm(
                                    context.mutedForeground,
                                  ),
                                ),
                              );
                            }
                            return ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.only(bottom: 12),
                              itemCount: cards.length,
                              separatorBuilder: (context, _) => Divider(
                                height: 1,
                                color: context.borderColor,
                                indent: 72,
                              ),
                              itemBuilder: (context, i) => _CardRow(
                                card: cards[i],
                                onTap: () => _pick(cards[i]),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.card, required this.onTap});

  final CardModel card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: CardArt(
                imageUrl: card.imageUrl,
                borderRadius: AppRadius.sm,
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
            if (card.marketPrice != null) ...[
              const SizedBox(width: 8),
              Text(
                formatRupiah(card.marketPrice!),
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}
