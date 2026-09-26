import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_condition.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/card_language_badge.dart';
import '../../repository/models/seller_listing.dart';
import 'seller_switch.dart';

/// One live listing, as a card.
///
/// The same shape as the draft card, deliberately: a seller moving between
/// Draft and Aktif is looking at the same stock at two moments of its life,
/// and making them read differently would mean learning the screen twice.
/// What a posted listing adds is the `⋮` — archive, restock, offers — and a
/// stock badge, because a posted listing can be partly sold.
class ListingCardTile extends StatefulWidget {
  const ListingCardTile({
    super.key,
    required this.listing,
    required this.offerCount,
    required this.onToggleAutoRelist,
    required this.onToggleOffers,
    required this.onMenu,
  });

  final SellerListing listing;

  /// Offers waiting on this listing, surfaced on the menu button so the one
  /// action with something pending isn't hidden behind a tap.
  final int offerCount;
  final ValueChanged<bool> onToggleAutoRelist;
  final ValueChanged<bool> onToggleOffers;
  final VoidCallback onMenu;

  @override
  State<ListingCardTile> createState() => _ListingCardTileState();
}

class _ListingCardTileState extends State<ListingCardTile> {
  late final TextEditingController _price = TextEditingController(
    text: formatRupiah(widget.listing.price),
  );

  late bool _autoRelist = widget.listing.autoRelist;
  late bool _acceptsOffers = widget.listing.acceptsOffers;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
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
                    CardArt(imageUrl: listing.card.imageUrl),
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: _StockBadge(
                        available: listing.available,
                        total: listing.quantity,
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
                        CardLanguageBadge(language: listing.card.language),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            listing.card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySemibold(colors.onSurface),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _ConditionPill(label: listing.condition.short),
                        const SizedBox(width: 4),
                        _MenuButton(
                          pending: widget.offerCount,
                          onTap: widget.onMenu,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _Chip(text: listing.card.expansionCode.toUpperCase()),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            listing.card.collectorNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _Field(
                  label: 'Jumlah',
                  child: _ReadOnlyStepper(value: listing.quantity),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: _Field(
                  label: 'Harga jual',
                  child: _PriceBox(controller: _price),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // A rule between the fields and the switches. Above it the card is
          // a form being filled in; below it are two standing choices about
          // the listing after it is posted.
          Divider(height: 1, thickness: 1, color: context.borderColor),
          const SizedBox(height: 8),
          // Left-aligned and hugging, not one half of the card each.
          Row(
            children: [
              Flexible(
                child: _SwitchRow(
                  label: 'Perpanjang otomatis',
                  value: _autoRelist,
                  onChanged: (v) {
                    setState(() => _autoRelist = v);
                    widget.onToggleAutoRelist(v);
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
                    widget.onToggleOffers(v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "1/4" — how many of the posted copies are still unsold.
///
/// Both numbers, not one: "1" alone reads as a small listing rather than a
/// nearly-sold-out one, and which of those it is changes what the seller
/// does next.
class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.available, required this.total});

  final int available;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.appColors.onSurface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        '$available/$total',
        style: AppTypography.badge(Colors.white),
      ),
    );
  }
}

class _ConditionPill extends StatelessWidget {
  const _ConditionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.mutedForeground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.captionSemibold(context.appColors.onSurface),
          ),
          const SizedBox(width: 2),
          Icon(
            LucideIcons.chevronDown,
            size: 13,
            color: context.mutedForeground,
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.pending, required this.onTap});

  final int pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: pending > 0 ? 'Aksi listing, $pending penawaran' : 'Aksi listing',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: context.mutedForeground.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.ellipsisVertical,
                size: 16,
                color: context.appColors.onSurface,
              ),
            ),
            if (pending > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.appColors.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).cardColor,
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    pending > 9 ? '9+' : '$pending',
                    style: AppTypography.badge(
                      Colors.white,
                    ).copyWith(fontSize: 8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption(context.mutedForeground)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

/// The posted quantity, shown in the stepper's shape but not editable.
///
/// Changing how many copies are for sale once buyers can lock them is
/// `restock`, which the `⋮` offers — it has rules about stock already
/// spoken for that a bare +/- would quietly break.
class _ReadOnlyStepper extends StatelessWidget {
  const _ReadOnlyStepper({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final muted = context.mutedForeground;

    return Container(
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(LucideIcons.minus, size: 16, color: muted),
          ),
          Text(
            '$value',
            style: AppTypography.bodySmSemibold(context.appColors.onSurface),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(LucideIcons.plus, size: 16, color: muted),
          ),
        ],
      ),
    );
  }
}

class _PriceBox extends StatelessWidget {
  const _PriceBox({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      keyboardType: TextInputType.number,
      style: AppTypography.bodySmSemibold(context.appColors.onSurface),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
