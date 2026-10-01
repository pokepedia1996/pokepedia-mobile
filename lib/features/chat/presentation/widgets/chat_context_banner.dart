import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../repository/models/chat_models.dart';

/// Ports `features/chat/components/room/chat-context-banner.tsx` — the strip
/// pinned under the header naming what the conversation is about.
///
/// Pinned rather than scrolled with the messages: it answers "which card is
/// this about" at any point in a long thread, and it is the first thing
/// wanted in a thread with no messages in it at all.
class ChatContextBanner extends StatelessWidget {
  const ChatContextBanner({super.key, required this.listing});

  final ChatListingContext listing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final slug = listing.packSlug;

    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(LucideIcons.tag, size: 16, color: colors.primary),
          const SizedBox(width: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 40,
              height: 40,
              child: listing.cardImage == null
                  ? Container(color: colors.secondary)
                  : Image.network(
                      listing.cardImage!,
                      fit: BoxFit.cover,
                      // `object-[center_15%]` on the web: a square crop of a
                      // portrait card taken from the top, where the art is.
                      alignment: const Alignment(0, -0.7),
                      errorBuilder: (context, error, stack) =>
                          Container(color: colors.secondary),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TENTANG LISTING',
                  style: AppTypography.overline(context.mutedForeground),
                ),
                const SizedBox(height: 1),
                Text(
                  listing.cardName ?? 'Kartu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySm(colors.onSurface),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatRupiah(listing.priceIdr),
            style: AppTypography.bodySmSemibold(colors.primary),
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: slug == null
          ? body
          : InkWell(
              onTap: () =>
                  context.push(Routes.cardDetail(slug, listing.cardId)),
              child: body,
            ),
    );
  }
}
