import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/image_url.dart';
import '../../../../shared/widgets/app_network_image.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../repository/models/custom_listing_form.dart';
import '../../repository/seller_listings_repository.dart';
import '../../usecase/seller_listings_notifier.dart';

/// What "Tambahkan Listing" can make.
enum NewListingKind { singles, custom }

/// Web's `AddListingChooser`: a card from the catalog, or a custom listing
/// with the seller's own title and photos. Null when dismissed.
Future<NewListingKind?> showAddListingChooser(BuildContext context) {
  return showModalBottomSheet<NewListingKind>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheet) {
      Widget option(
        NewListingKind kind,
        IconData icon,
        String title,
        String description,
      ) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => Navigator.of(sheet).pop(kind),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: sheet.borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: sheet.appColors.secondary,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.bodySemibold(
                          sheet.appColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: AppTypography.bodySm(sheet.mutedForeground),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: sheet.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      );

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tambahkan Listing',
                      style: AppTypography.h3(sheet.appColors.onSurface),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 20),
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(sheet).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              option(
                NewListingKind.singles,
                LucideIcons.rectangleVertical,
                'Singles',
                'Kartu dari katalog',
              ),
              option(
                NewListingKind.custom,
                LucideIcons.packageOpen,
                'Custom',
                'Judul & foto sendiri',
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// "Draft custom" at the top of the Draft tab — web's `CustomDraftList`:
/// the custom listings saved but not yet published, each to pick up or
/// throw away. Absent when there are none.
class CustomDraftsSection extends ConsumerStatefulWidget {
  const CustomDraftsSection({super.key, required this.onOpen});

  /// Opens a draft in the custom listing form.
  final ValueChanged<String> onOpen;

  @override
  ConsumerState<CustomDraftsSection> createState() =>
      _CustomDraftsSectionState();
}

class _CustomDraftsSectionState extends ConsumerState<CustomDraftsSection> {
  Future<void> _delete(CustomDraftSummary draft) {
    final name = draft.title?.trim().isNotEmpty == true
        ? draft.title!
        : 'Draft tanpa judul';
    return showConfirmDialog(
      context,
      title: 'Hapus draft?',
      description: '$name akan dihapus.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () async {
        // A custom draft is a `listings` row: `delete_listing`, as web's
        // `deleteListingPermanent` sends it.
        final error = await ref
            .read(sellerListingsRepositoryProvider)
            .deletePermanent(draft.slug);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(error ?? 'Draft dihapus'), persist: false),
          );
        if (error == null) ref.invalidate(customDraftsProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(customDraftsProvider).valueOrNull ?? const [];
    if (drafts.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Text(
              'Draft custom',
              style: AppTypography.bodySmSemibold(colors.onSurface),
            ),
          ),
          for (final draft in drafts) ...[
            Divider(height: 1, color: context.borderColor),
            _CustomDraftRow(
              draft: draft,
              onOpen: () => widget.onOpen(draft.slug),
              onDelete: () => _delete(draft),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomDraftRow extends StatelessWidget {
  const _CustomDraftRow({
    required this.draft,
    required this.onOpen,
    required this.onDelete,
  });

  final CustomDraftSummary draft;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final title = draft.title?.trim().isNotEmpty == true
        ? draft.title!
        : 'Tanpa judul';
    final price = draft.price;
    final cover = proxyImageUrl(draft.coverUrl);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: cover == null
                ? Icon(
                    LucideIcons.packageOpen,
                    size: 18,
                    color: context.mutedForeground,
                  )
                : cachedNetworkImage(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmSemibold(colors.onSurface),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: colors.secondary,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        'CUSTOM',
                        style: AppTypography.badge(colors.onSurface),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${price == null || price <= 0 ? 'Harga belum diisi' : formatRupiah(price)}'
                        ' · ×${draft.quantity}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onOpen,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text('Lanjutkan'),
          ),
          IconButton(
            tooltip: 'Hapus draft $title',
            icon: Icon(
              LucideIcons.trash2,
              size: 18,
              color: context.mutedForeground,
            ),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
