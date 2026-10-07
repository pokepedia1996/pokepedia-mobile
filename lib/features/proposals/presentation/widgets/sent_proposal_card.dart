import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/models/card_model.dart';
import '../../../../shared/widgets/card_art.dart';
import '../../../../shared/widgets/condition_badge.dart';
import '../../../../shared/widgets/photo_strip.dart';
import '../../../../shared/widgets/status_pill.dart';
import '../../repository/models/bid_proposal_model.dart';
import '../../repository/models/sent_proposal.dart';

/// A proposal this user sent as a seller — a "Penuhi Bid" — with where it
/// stands: the price asked against the bid's, the grade and quantity, the
/// buyer's clock, whether they have seen it, the note and the photos.
///
/// Shared by a card's own proposals page and Penawaranku, the list of every
/// one across all cards.
class SentProposalCard extends StatelessWidget {
  const SentProposalCard({
    super.key,
    required this.proposal,
    required this.busy,
    required this.onDismiss,
    this.onOpenCard,
  });

  final SentProposalModel proposal;
  final bool busy;
  final VoidCallback onDismiss;

  /// Given, the row leads with the card it is for and opens it on tap. Off
  /// on a card's own page, which already says which card this is; on in
  /// Penawaranku, where every row can be a different one.
  final VoidCallback? onOpenCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onOpenCard != null) ...[
            _CardLine(card: proposal.card, onTap: onOpenCard!),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // What this row is: the offer *you* sent, and who to.
                      // It used to lead with "Bid dari @x", which names the
                      // bid being answered and reads as something received.
                      'Proposal ke @${proposal.buyerUsername ?? "pembeli"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    // Web's row: the price asked, the bid it answers struck
                    // through when they differ, then the grade and the rest.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 5,
                      runSpacing: 2,
                      children: [
                        // Either can be unknown once the buyer's bid has
                        // closed and the seller can no longer read it.
                        if (proposal.effectivePrice case final price?)
                          Text(
                            formatRupiah(price),
                            style: AppTypography.bodySmSemibold(
                              colors.onSurface,
                            ),
                          ),
                        if (proposal.bidPrice case final bidPrice?
                            when bidPrice != proposal.effectivePrice)
                          Text(
                            formatRupiah(bidPrice),
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ).copyWith(decoration: TextDecoration.lineThrough),
                          ),
                        ConditionBadge(
                          condition: proposal.condition,
                          dense: true,
                        ),
                        Text(
                          [
                            '${proposal.proposedQuantity} pcs',
                            // Said out loud: a bare "23 jam lalu" in a run
                            // of dot-separated facts doesn't say which of
                            // them it is timing.
                            if (proposal.createdAt case final at?)
                              'dikirim ${formatRelativeId(at).toLowerCase()}',
                          ].join(' · '),
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: proposal.status.label,
                color: switch (proposal.status) {
                  BidProposalStatus.pending => context.appSemantic.condMp,
                  BidProposalStatus.accepted => context.appSemantic.success,
                  BidProposalStatus.rejected => colors.error,
                  _ => context.mutedForeground,
                },
              ),
              // `dismiss_bid_proposal` refuses a pending row, so the button
              // only exists once the proposal has settled.
              if (proposal.isDismissible)
                IconButton(
                  onPressed: busy ? null : onDismiss,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Hapus dari daftar',
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          LucideIcons.trash2,
                          size: 18,
                          color: context.mutedForeground,
                        ),
                ),
            ],
          ),

          // The clock, on a line of its own: it's the one fact here that
          // changes by itself, and it was the easiest to miss at the end of
          // a run of dot-separated ones. Only while the proposal can still
          // be answered — a settled one's clock is history.
          if (proposal.remaining case final left?) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  LucideIcons.clock,
                  size: 13,
                  color: context.mutedForeground,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    // "Waktu habis" once it has run out, as web's countdown
                    // says — a clock that reads "Expired dalam kurang dari 1
                    // menit" for a week is telling the wrong story.
                    left == Duration.zero
                        ? 'Waktu habis'
                        : 'Expired dalam ${formatCountdownId(left)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(
                      left == Duration.zero
                          ? colors.error
                          : context.mutedForeground,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Whether the buyer has actually opened it. Web shows this only
          // while pending: once answered, being seen is implied.
          if (proposal.status == BidProposalStatus.pending) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  proposal.seenAt == null
                      ? LucideIcons.eyeOff
                      : LucideIcons.eye,
                  size: 13,
                  color: proposal.seenAt == null
                      ? context.mutedForeground
                      : context.appSemantic.success,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    proposal.seenAt == null
                        ? 'Belum dilihat pembeli'
                        : 'Dilihat pembeli · '
                              '${formatRelativeId(proposal.seenAt!)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(
                      proposal.seenAt == null
                          ? context.mutedForeground
                          : context.appSemantic.success,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // The note the seller sent with the offer — web's blockquote.
          if (proposal.message?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.4),
                border: Border(
                  left: BorderSide(color: context.borderColor, width: 2),
                ),
              ),
              child: Text(
                proposal.message!.trim(),
                style: AppTypography.bodySm(
                  colors.onSurface,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],

          // The photos that went with the proposal. Sending these is what
          // makes an offer above Rp100.000 valid, so a row without them was
          // hiding the seller's actual evidence.
          if (proposal.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  // `isStockPhoto` — catalog art rather than the seller's own
                  // copy, which a buyer should be able to tell apart.
                  proposal.usesStockPhoto ? 'Foto Stok' : 'Foto Listing',
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ),
            ),
            const SizedBox(height: 6),
            PhotoStrip(srcs: proposal.photos),
          ],
        ],
      ),
    );
  }
}

/// The card a proposal is for — art, name, number and set — as the row's
/// first line, tappable through to the card.
class _CardLine extends StatelessWidget {
  const _CardLine({required this.card, required this.onTap});

  final CardModel card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: CardArt(imageUrl: card.imageUrl, borderRadius: AppRadius.sm),
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
                  style: AppTypography.bodySmSemibold(
                    context.appColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    card.expansionCode.toUpperCase(),
                    card.collectorNumber,
                    if (card.variantLabel != null) card.variantLabel!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(context.mutedForeground),
                ),
              ],
            ),
          ),
          Icon(
            LucideIcons.chevronRight,
            size: 16,
            color: context.mutedForeground,
          ),
        ],
      ),
    );
  }
}
