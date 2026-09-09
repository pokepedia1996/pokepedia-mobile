import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/widgets/condition_badge.dart';
import '../../../../shared/widgets/quantity_selector.dart';
import '../../usecase/trading_notifier.dart';

/// Photos become mandatory at this price — `PHOTO_REQUIRED_THRESHOLD`.
const _photoRequiredThreshold = 100000;
const _minPhotos = 1;
const _maxPhotos = 4;
const _maxMessage = 280;

/// The one bid a proposal is aimed at, when it is aimed at one.
///
/// Omitted from the order book, which has only a price level to work with;
/// supplied by the bid detail page, which is looking at the listing itself.
typedef BidProposalTarget = ({String slug, int available, String buyerName});

/// Opens "Kirim proposal" for a bid. Resolves how many buyers it reached, or
/// null if nothing was sent.
///
/// Ports `bid-proposal-modal.tsx`. Two shapes, and [target] picks between
/// them: without one, an order-book row is a price level rather than one
/// listing, so the card is offered to *every* buyer bidding at that price at
/// once (`submit_bid_proposal_broadcast`); with one, the proposal goes to
/// that single wanted-ad (`submit_bid_proposal`) and nobody else hears about
/// it.
Future<int?> showBidProposalSheet(
  BuildContext context, {
  required CardModel card,
  required int price,
  required CardCondition condition,
  String? variantKey,
  BidProposalTarget? target,
}) {
  return showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _BidProposalSheet(
      card: card,
      price: price,
      condition: condition,
      variantKey: variantKey,
      target: target,
    ),
  );
}

class _BidProposalSheet extends ConsumerStatefulWidget {
  const _BidProposalSheet({
    required this.card,
    required this.price,
    required this.condition,
    required this.variantKey,
    required this.target,
  });

  final CardModel card;
  final int price;
  final CardCondition condition;
  final String? variantKey;
  final BidProposalTarget? target;

  @override
  ConsumerState<_BidProposalSheet> createState() => _BidProposalSheetState();
}

class _BidProposalSheetState extends ConsumerState<_BidProposalSheet> {
  final _message = TextEditingController();
  late final TextEditingController _askPrice = TextEditingController(
    text: '${widget.price}',
  );
  final _photos = <File>[];

  int _quantity = 1;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  /// How deep the level is, and how many buyers stand behind it.
  int _buyerCount = 0;
  int _availableQty = 0;

  @override
  void initState() {
    super.initState();
    final target = widget.target;
    if (target == null) {
      _loadLevel();
      return;
    }
    // One named bid: its depth is already on screen behind this sheet, so
    // there is nothing to look up and nothing to wait for.
    _buyerCount = 1;
    _availableQty = target.available;
    _loading = false;
  }

  @override
  void dispose() {
    _message.dispose();
    _askPrice.dispose();
    super.dispose();
  }

  Future<void> _loadLevel() async {
    final level = await ref
        .read(tradingRepositoryProvider)
        .fetchBidLevel(
          cardId: widget.card.id,
          condition: widget.condition,
          price: widget.price,
          variantKey: widget.variantKey,
        );
    if (!mounted) return;
    setState(() {
      _buyerCount = level.buyerCount;
      _availableQty = level.availableQty;
      _quantity = level.availableQty < 1 ? 1 : 1;
      _loading = false;
    });
  }

  /// What the seller is asking. Sent only when it's above the bid — matching
  /// the bid exactly is an acceptance, not a counter.
  int get _askValue => int.tryParse(_askPrice.text.trim()) ?? widget.price;
  bool get _photosRequired => _askValue >= _photoRequiredThreshold;

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
    );
    if (picked == null || !mounted) return;
    setState(() => _photos.add(File(picked.path)));
  }

  Future<void> _submit() async {
    if (_photosRequired && _photos.length < _minPhotos) {
      setState(() {
        _error =
            'Unggah minimal $_minPhotos foto untuk kartu di atas '
            '${formatRupiah(_photoRequiredThreshold)}';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final repository = ref.read(tradingRepositoryProvider);

    // Uploaded first so the RPC receives the URLs in one call, the way the
    // web route passes them.
    var photoUrls = const <String>[];
    if (_photos.isNotEmpty) {
      try {
        photoUrls = await repository.uploadListingPhotos(_photos);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _submitting = false;
          _error = 'Gagal mengunggah foto. Coba lagi.';
        });
        return;
      }
      if (!mounted) return;
    }

    final target = widget.target;
    final message = _message.text.trim().isEmpty ? null : _message.text.trim();
    final proposedPrice = _askValue > widget.price ? _askValue : null;

    final ({int sentCount, String? error}) result;
    if (target == null) {
      result = await repository.broadcastBidProposal(
        cardId: widget.card.id,
        condition: widget.condition,
        price: widget.price,
        quantity: _quantity,
        photoUrls: photoUrls,
        variantKey: widget.variantKey,
        message: message,
        proposedPrice: proposedPrice,
      );
    } else {
      final single = await repository.submitBidProposal(
        bidSlug: target.slug,
        condition: widget.condition,
        quantity: _quantity,
        photoUrls: photoUrls,
        message: message,
        proposedPrice: proposedPrice,
      );
      // One bid, so one buyer reached — the callers all speak in counts.
      result = (sentCount: single.error == null ? 1 : 0, error: single.error);
    }
    if (!mounted) return;

    if (result.error != null) {
      setState(() {
        _submitting = false;
        _error = result.error;
      });
      return;
    }
    Navigator.of(context).pop(result.sentCount);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final canSend = !_submitting && !_loading && _buyerCount > 0;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Kirim Proposal', style: AppTypography.h3(colors.onSurface)),
              const SizedBox(height: 2),
              Text(
                widget.card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySm(context.mutedForeground),
              ),
              const SizedBox(height: 14),

              _LevelSummary(
                loading: _loading,
                buyerCount: _buyerCount,
                availableQty: _availableQty,
                price: widget.price,
                condition: widget.condition,
                buyerName: widget.target?.buyerName,
              ),

              if (!_loading && _buyerCount == 0) ...[
                const SizedBox(height: 14),
                Text(
                  'Tidak ada bid di harga ini lagi.',
                  style: AppTypography.bodySm(colors.error),
                ),
              ] else ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Jumlah',
                        style: AppTypography.captionSemibold(
                          context.mutedForeground,
                        ),
                      ),
                    ),
                    QuantitySelector(
                      value: _quantity,
                      min: 1,
                      max: _availableQty < 1 ? 1 : _availableQty,
                      onChanged: (value) => setState(() => _quantity = value),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Text(
                  'Harga jualmu',
                  style: AppTypography.captionSemibold(context.mutedForeground),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _askPrice,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixText: 'Rp ',
                    isDense: true,
                    helperText: _askValue > widget.price
                        ? 'Di atas bid — pembeli harus menyetujui harga ini'
                        : 'Sama dengan bid — langsung cocok',
                    helperStyle: AppTypography.caption(context.mutedForeground),
                  ),
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    Text(
                      'Foto kartu',
                      style: AppTypography.captionSemibold(
                        context.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_photosRequired)
                      Text(
                        'wajib di atas ${formatRupiah(_photoRequiredThreshold)}',
                        style: AppTypography.caption(colors.error),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < _photos.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _PhotoThumb(
                          file: _photos[i],
                          onRemove: () => setState(() => _photos.removeAt(i)),
                        ),
                      ),
                    if (_photos.length < _maxPhotos)
                      InkWell(
                        onTap: _pickPhoto,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            border: Border.all(color: context.borderColor),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            LucideIcons.imagePlus,
                            size: 20,
                            color: context.mutedForeground,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: _message,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: _maxMessage,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Pesan untuk pembeli (opsional)',
                    counterText: '',
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppTypography.bodySm(colors.error)),
              ],

              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: canSend ? _submit : null,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _buyerCount > 1
                            ? 'Kirim ke $_buyerCount pembeli'
                            : 'Kirim Proposal',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the level being proposed to actually holds.
class _LevelSummary extends StatelessWidget {
  const _LevelSummary({
    required this.loading,
    required this.buyerCount,
    required this.availableQty,
    required this.price,
    required this.condition,
    this.buyerName,
  });

  final bool loading;
  final int buyerCount;
  final int availableQty;
  final int price;
  final CardCondition condition;

  /// Set when the proposal is aimed at one bid: who it goes to is more use
  /// than a count of one.
  final String? buyerName;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bid',
                style: AppTypography.caption(context.mutedForeground),
              ),
              Text(
                formatRupiah(price),
                style: AppTypography.bodySemibold(context.appSemantic.success),
              ),
            ],
          ),
          const SizedBox(width: 12),
          ConditionBadge(condition: condition, dense: true),
          const Spacer(),
          if (loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            // Flexible because a buyer's store name can be long, and this
            // sits after a Spacer with nothing else to bound it.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    buyerName ??
                        (buyerCount == 1 ? '1 pembeli' : '$buyerCount pembeli'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.captionSemibold(colors.onSurface),
                  ),
                  Text(
                    'butuh $availableQty kartu',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.file, required this.onRemove});

  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Image.file(file, width: 56, height: 56, fit: BoxFit.cover),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.appColors.onSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.x,
                size: 11,
                color: Theme.of(context).cardColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
