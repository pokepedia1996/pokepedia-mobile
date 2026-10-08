import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/card_language_badge.dart';
import '../../../../shared/models/card_condition.dart';
import '../../repository/models/seller_listing.dart';
import 'draft_photo_sheet.dart';
import 'seller_switch.dart';
import '../../repository/seller_listings_repository.dart';

/// One draft, as a card you can finish in place.
///
/// This was a row in a table that scrolled sideways: ten columns, of which
/// the two that decide whether a draft can be posted at all — quantity and
/// price — were off the right edge on every phone. A draft is a form the
/// seller has not finished yet, so the card puts the unfinished parts where
/// they can be finished.
///
/// Each field writes on its own, as it is changed. There is no Simpan here
/// because there is nothing to submit: a draft is already saved, and these
/// are edits to it.
class DraftCard extends ConsumerStatefulWidget {
  const DraftCard({
    super.key,
    required this.draft,
    required this.onDelete,
    required this.onChanged,
    required this.selected,
    required this.onToggleSelect,
  });

  final SellerDraft draft;
  final VoidCallback onDelete;

  /// Ticked for the bottom bar's batch actions. The card carries the whole
  /// signal — there is no separate checkbox, because at this size a tick box
  /// would be a smaller target than the card it belongs to.
  final bool selected;
  final VoidCallback onToggleSelect;

  /// Fired after a field is written, so the list can re-read and the chips'
  /// counts can move with it.
  final VoidCallback onChanged;

  @override
  ConsumerState<DraftCard> createState() => _DraftCardState();
}

class _DraftCardState extends ConsumerState<DraftCard> {
  late final TextEditingController _price = TextEditingController(
    text: widget.draft.price == null ? '' : formatRupiah(widget.draft.price!),
  );

  /// The card holds what the seller has typed rather than re-reading the
  /// draft: a rebuild mid-edit would otherwise put the saved value back
  /// under the cursor.
  late int _quantity = widget.draft.quantity;
  late bool _autoRelist = widget.draft.autoRelist;
  late bool _acceptsOffers = widget.draft.acceptsOffers;
  late CardCondition _condition = widget.draft.condition;

  @override
  void didUpdateWidget(DraftCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // These two can be set from outside the card: the bulk menu applies
    // either switch to every ticked draft at once, and the card has to show
    // what was just done to it rather than the value it was built with.
    //
    // Adopted only when the arriving draft differs from the one this card
    // was showing. That difference is what marks a change made elsewhere —
    // the echo of a toggle made here arrives already equal, so a seller
    // flipping a switch never sees it snap back while the write is in
    // flight. The typed fields above stay out of this on purpose.
    if (widget.draft.autoRelist != oldWidget.draft.autoRelist) {
      _autoRelist = widget.draft.autoRelist;
    }
    if (widget.draft.acceptsOffers != oldWidget.draft.acceptsOffers) {
      _acceptsOffers = widget.draft.acceptsOffers;
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _write({
    int? quantity,
    int? price,
    bool? autoRelist,
    bool? acceptsOffers,
    CardCondition? condition,
  }) async {
    final error = await ref
        .read(sellerListingsRepositoryProvider)
        .updateDraft(
          widget.draft.id,
          quantity: quantity,
          price: price,
          autoRelist: autoRelist,
          acceptsOffers: acceptsOffers,
          condition: condition,
        );

    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error), persist: false));
      return;
    }
    widget.onChanged();
  }

  Future<void> _editPhotos() async {
    final changed = await showDraftPhotoSheet(context, widget.draft);
    if (changed == true) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final colors = context.appColors;
    final success = context.appSemantic.success;

    return GestureDetector(
      // The card is the tick target. Tapping a field inside it does that
      // field's job instead — those all absorb their own taps.
      onTap: widget.onToggleSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          // Green is selection, not readiness. Whether a draft can be posted
          // is already legible from whether its price field is filled in;
          // what the card cannot otherwise say is that the button at the
          // bottom of the screen is about this one.
          color: widget.selected
              ? success.withValues(alpha: 0.10)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: widget.selected ? success : context.borderColor,
            width: widget.selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 42,
                  child: Stack(
                    children: [
                      CardArt(imageUrl: draft.card.imageUrl),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: _PhotoBadge(
                          count: draft.photoCount,
                          onTap: _editPhotos,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CardLanguageBadge(language: draft.card.language),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              draft.card.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmSemibold(
                                colors.onSurface,
                              ),
                            ),
                          ),
                          if (!draft.card.isSealed) ...[
                            const SizedBox(width: 6),
                            _ConditionPicker(
                              condition: _condition,
                              onChanged: (c) {
                                setState(() => _condition = c);
                                _write(condition: c);
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Chip(text: draft.card.expansionCode.toUpperCase()),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              draft.card.collectorNumber,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption(
                                context.mutedForeground,
                              ),
                            ),
                          ),
                          if (draft.card.rarity != null) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                draft.card.rarity!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Top-aligned, not bottom: the two labels are a line of the card
            // and have to read as one. Bottom-aligning let the shorter
            // column drop, which put "Jumlah" a pixel below "Harga jual" —
            // small, but enough to make the row look staggered.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The counter takes exactly the room it needs and the price
                // field takes the rest. Splitting the row by flex gave the
                // stepper a box half again its width, so the two controls
                // sat with a gap between them instead of beside each other —
                // and the price, which is the longer thing to read and the
                // one being decided, got the narrower half.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Jumlah',
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    const SizedBox(height: 4),
                    _QtyStepper(
                      value: _quantity,
                      onChanged: (v) {
                        setState(() => _quantity = v);
                        _write(quantity: v);
                      },
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Harga jual',
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                      const SizedBox(height: 4),
                      _PriceField(
                        controller: _price,
                        marketPrice: draft.card.marketPrice,
                        onSubmitted: (value) {
                          final parsed = _digitsOf(value);
                          if (parsed > 0) _write(price: parsed);
                        },
                        onUseMarketPrice: () {
                          final market = draft.card.marketPrice;
                          if (market == null || market <= 0) {
                            // Said out loud rather than a dead tap: the
                            // seller cannot tell from the outside whether
                            // the button is broken or the card simply has
                            // no trades behind it yet.
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Belum ada harga pasaran untuk kartu ini',
                                  ),
                                  persist: false,
                                ),
                              );
                            return;
                          }
                          _price.text = formatRupiah(market);
                          _write(price: market);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // A rule between the fields and the switches. Above it the card
            // is a form being filled in; below it are two standing choices
            // about the listing after it is posted. They are different kinds
            // of thing and the line says so.
            Divider(height: 1, thickness: 1, color: context.borderColor),
            const SizedBox(height: 8),
            // Left-aligned and hugging, not one half of the card each:
            // spreading them put "Terima penawaran" against the right edge
            // with a hole in the middle, which read as two separate rows
            // rather than one pair of settings.
            Row(
              children: [
                Flexible(
                  child: _SwitchRow(
                    label: 'Perpanjang otomatis',
                    value: _autoRelist,
                    onChanged: (v) {
                      setState(() => _autoRelist = v);
                      _write(autoRelist: v);
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: _SwitchRow(
                    label: 'Terima penawaran',
                    value: _acceptsOffers,
                    onChanged: (v) {
                      setState(() => _acceptsOffers = v);
                      _write(acceptsOffers: v);
                    },
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

/// The camera badge over the thumbnail, carrying how many photos the draft
/// has. A draft with none is the common case, so it shows the icon alone
/// rather than a zero.
class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A tick once there are photos, a camera while there are none: the badge
    // is answering "does this still need pictures?", and a count answers a
    // question nobody asked of a draft. Either way it is the way in — the
    // thumbnail is the only place a photo control belongs.
    final done = count > 0;
    final success = context.appSemantic.success;

    return Semantics(
      button: true,
      label: done ? 'Ubah foto kartu' : 'Tambah foto kartu',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: done ? success : context.appColors.onSurface,
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).cardColor, width: 2),
          ),
          child: Icon(
            done ? LucideIcons.check : LucideIcons.camera,
            size: 11,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.marketPrice,
    required this.onSubmitted,
    required this.onUseMarketPrice,
  });

  final TextEditingController controller;

  /// What the card is going for. Shown as the placeholder rather than
  /// filled in: it is a suggestion, and a price the seller never chose
  /// should not be sitting in the field as though they had.
  final int? marketPrice;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onUseMarketPrice;

  @override
  Widget build(BuildContext context) {
    final hasMarket = marketPrice != null && marketPrice! > 0;

    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: const [_RupiahInputFormatter()],
      textInputAction: TextInputAction.done,
      // Left, with the label above it. A number typed left-to-right that
      // re-centres itself on every keystroke moves under the cursor.
      textAlign: TextAlign.start,
      // Written when the field is left as well as on submit: a seller who
      // types a price and taps the next card has still decided the price.
      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
        onSubmitted(controller.text);
      },
      onSubmitted: onSubmitted,
      style: AppTypography.bodySmSemibold(context.appColors.onSurface),
      decoration: InputDecoration(
        isDense: true,
        hintText: hasMarket ? '${formatRupiah(marketPrice!)} pasaran' : 'Harga',
        hintStyle: AppTypography.bodySm(context.mutedForeground),
        // Always drawn, never conditional on the field being empty or on the
        // catalog having a price. A seller who mistyped wants it back most
        // of all, and a button that disappears for some cards reads as a
        // feature this card doesn't have rather than as a price the cache is
        // missing — so it stays and says which it is.
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Semantics(
            button: true,
            label: 'Pakai harga pasaran',
            child: InkWell(
              onTap: onUseMarketPrice,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: hasMarket
                      ? context.mutedForeground.withValues(alpha: 0.10)
                      : context.mutedForeground.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  LucideIcons.sparkles,
                  size: 15,
                  color: hasMarket
                      ? context.appColors.onSurface
                      : context.mutedForeground.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 36),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: context.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: context.borderColor),
        ),
      ),
    );
  }
}

/// The digits in [text] as a number — the field carries "Rp" and thousand
/// separators, and none of that is the price.
int _digitsOf(String text) =>
    int.tryParse(text.replaceAll(RegExp(r'\D'), '')) ?? 0;

/// Formats the field as it is typed: "45000" becomes "Rp45.000".
///
/// Grouped rather than raw because a price is read at a glance and six
/// unseparated digits are not — a seller checking a draft against the
/// market price is comparing "Rp45.000" to "Rp45.000", not "45000" to a
/// hint that spells it out.
class _RupiahInputFormatter extends TextInputFormatter {
  const _RupiahInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = _digitsOf(newValue.text);
    if (digits <= 0) return const TextEditingValue();

    final text = formatRupiah(digits);
    // The caret goes to the end: separators shift every character left of
    // the cursor as they appear, so holding a mid-string position would put
    // it somewhere the reader did not leave it.
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The draft card's quantity control: round steppers either side of the
/// count, hugging its content rather than filling the column.
class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  /// One is the floor. A draft of nothing is a draft that should have been
  /// deleted, and the selection bar is where deleting lives.
  static const _min = 1;
  static const _max = 99;

  /// Shorter than the price field beside it. The counter holds two digits
  /// and is nudged rather than typed into, so it does not need the field's
  /// height — and taking it back keeps the row from dominating the card.
  static const _height = 33.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RoundStep(
          icon: LucideIcons.minus,
          onTap: value > _min ? () => onChanged(value - 1) : null,
        ),
        Container(
          width: 36,
          height: _height,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.borderColor),
          ),
          child: Text(
            '$value',
            style: AppTypography.bodySmSemibold(context.appColors.onSurface),
          ),
        ),
        _RoundStep(
          icon: LucideIcons.plus,
          onTap: value < _max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _RoundStep extends StatelessWidget {
  const _RoundStep({required this.icon, required this.onTap});

  final IconData icon;

  /// Null at a bound, which dims it rather than hiding it — a control that
  /// vanishes at the edge moves the one beside it.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: _QtyStepper._height,
        height: _QtyStepper._height,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          shape: BoxShape.circle,
          border: Border.all(color: context.borderColor),
        ),
        child: Icon(
          icon,
          size: 13,
          color: enabled
              ? context.appColors.onSurface
              : context.mutedForeground.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

/// The "NM v" pill: the grade, and a menu to change it without leaving the
/// card. A draft's condition is one of the things being decided here, so it
/// is a control rather than a badge.
class _ConditionPicker extends StatelessWidget {
  const _ConditionPicker({required this.condition, required this.onChanged});

  final CardCondition condition;
  final ValueChanged<CardCondition> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return PopupMenuButton<CardCondition>(
      initialValue: condition,
      tooltip: 'Ubah kondisi',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final c in CardCondition.values)
          PopupMenuItem(value: c, child: Text(c.label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.mutedForeground.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              condition.short,
              style: AppTypography.captionSemibold(colors.onSurface),
            ),
            const SizedBox(width: 2),
            Icon(
              LucideIcons.chevronDown,
              size: 13,
              color: context.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SellerSwitch(value: value, onChanged: onChanged),
        const SizedBox(width: 4),
        // A point smaller than the card's other captions, so both labels fit
        // on one line at the *same* size. Scaling each to fit instead shrank
        // only the longer one, leaving two different text sizes side by side
        // — worse than the wrapping it fixed.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(
              context.appColors.onSurface,
            ).copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.mutedForeground.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: AppTypography.captionSemibold(context.mutedForeground),
      ),
    );
  }
}
