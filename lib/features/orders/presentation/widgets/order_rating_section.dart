import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/inline_pill.dart';
import '../../repository/models/order_model.dart';
import '../../repository/models/order_rating.dart';
import '../../usecase/orders_notifier.dart';

/// Ports the "Penilaian" section of `order-detail.tsx`.
///
/// Only shown once the whole order is settled and nothing is under
/// complaint — web's `groupIsCompleteForReview`. Offers the rating until one
/// is left, then shows what was said.
class OrderRatingSection extends ConsumerWidget {
  const OrderRatingSection({
    super.key,
    required this.order,
    required this.child,
  });

  final OrderModel order;

  /// The section shell to wrap the contents in, so this file doesn't need
  /// the detail page's private `_Section`.
  final Widget Function(String title, List<Widget> children) child;

  /// `groupIsCompleteForReview`: every line settled, none disputed.
  static bool isReviewable(OrderModel order) {
    if (order.items.isEmpty) return false;
    if (order.openDispute != null) return false;
    // `groupIsCompleteForReview`: settled and undisputed. Read off the item
    // — `orders.status` lags, so a finished order was never offered the
    // rating at all.
    return order.isSettledSuccessfully;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isReviewable(order)) return const SizedBox.shrink();
    final rating = ref.watch(orderRatingProvider(order.slug)).valueOrNull;

    return child('Penilaian', [
      const Align(
        alignment: Alignment.centerLeft,
        child: InlinePill(
          tone: InlinePillTone.success,
          icon: LucideIcons.circleCheck,
          label: 'Transaksi selesai',
        ),
      ),
      const SizedBox(height: 12),
      if (rating == null)
        ElevatedButton(
          onPressed: () => _openSheet(context, ref),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
          ),
          child: const Text('Beri Penilaian'),
        )
      else
        _SubmittedFeedback(rating: rating),
    ]);
  }

  Future<void> _openSheet(BuildContext context, WidgetRef ref) async {
    final itemId = order.firstItemId;
    if (itemId == null) return;

    final result =
        await showModalBottomSheet<({FeedbackKind kind, String note})>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Theme.of(context).cardColor,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          builder: (_) => const _RatingSheet(),
        );
    if (result == null || !context.mounted) return;

    final error = await ref
        .read(ordersRepositoryProvider)
        .submitRating(
          orderItemId: itemId,
          feedback: result.kind,
          comment: result.note,
        );
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(error ?? 'Penilaian terkirim!'), persist: false),
      );
    if (error == null) ref.invalidate(orderRatingProvider(order.slug));
  }
}

/// The review as it stands, once left.
class _SubmittedFeedback extends StatelessWidget {
  const _SubmittedFeedback({required this.rating});

  final OrderRating rating;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tone = switch (rating.feedback) {
      FeedbackKind.positive => InlinePillTone.success,
      FeedbackKind.neutral => InlinePillTone.neutral,
      FeedbackKind.negative => InlinePillTone.danger,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InlinePill(
                tone: tone,
                icon: switch (rating.feedback) {
                  FeedbackKind.positive => LucideIcons.thumbsUp,
                  FeedbackKind.neutral => LucideIcons.minus,
                  FeedbackKind.negative => LucideIcons.thumbsDown,
                },
                label: rating.feedback.label,
              ),
              const Spacer(),
              Text(
                formatShortDateId(rating.createdAt),
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
          if (rating.comment?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              rating.comment!,
              style: AppTypography.bodySm(colors.onSurface),
            ),
          ],
          // The seller's answer, if they left one.
          if (rating.reply?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Balasan penjual',
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rating.reply!,
                    style: AppTypography.bodySm(colors.onSurface),
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

/// Ports `feedback-modal.tsx`: pick a verdict, optionally say why.
class _RatingSheet extends StatefulWidget {
  const _RatingSheet();

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  final _note = TextEditingController();
  FeedbackKind? _kind;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Beri Penilaian', style: AppTypography.h3(colors.onSurface)),
              const SizedBox(height: 4),
              Text(
                'Bagaimana transaksi dengan penjual ini?',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final kind in FeedbackKind.values) ...[
                    Expanded(
                      child: _KindButton(
                        kind: kind,
                        selected: _kind == kind,
                        onTap: () => setState(() => _kind = kind),
                      ),
                    ),
                    if (kind != FeedbackKind.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                // `z.string().max(500)` on the route.
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Ceritakan pengalamanmu (opsional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _kind == null
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop((kind: _kind!, note: _note.text)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                child: const Text('Kirim Penilaian'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final FeedbackKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = switch (kind) {
      FeedbackKind.positive => InlinePillTone.success,
      FeedbackKind.neutral => InlinePillTone.neutral,
      FeedbackKind.negative => InlinePillTone.danger,
    };
    final color = toneColor(context, tone);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? color : context.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              switch (kind) {
                FeedbackKind.positive => LucideIcons.thumbsUp,
                FeedbackKind.neutral => LucideIcons.minus,
                FeedbackKind.negative => LucideIcons.thumbsDown,
              },
              size: 20,
              color: selected ? color : context.mutedForeground,
            ),
            const SizedBox(height: 4),
            Text(
              kind.label,
              style: selected
                  ? AppTypography.captionSemibold(color)
                  : AppTypography.caption(context.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}
