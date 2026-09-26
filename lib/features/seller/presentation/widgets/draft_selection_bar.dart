import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../repository/seller_listings_repository.dart';
import '../../usecase/seller_listings_notifier.dart';

/// The bar that rises once drafts are ticked: how many, a way to delete
/// them, and the one action the whole screen is for — posting them.
///
/// It rides over the list rather than sitting under it so the drafts stay
/// visible while they are being chosen. Absent entirely when nothing is
/// ticked: a disabled bar permanently occupying the bottom of the screen
/// would cost every seller the room to serve the moment they are selecting.
class DraftSelectionBar extends ConsumerStatefulWidget {
  const DraftSelectionBar({super.key, required this.onDone});

  final Future<void> Function() onDone;

  @override
  ConsumerState<DraftSelectionBar> createState() => _DraftSelectionBarState();
}

class _DraftSelectionBarState extends ConsumerState<DraftSelectionBar> {
  bool _busy = false;

  /// The ticked drafts that can actually be posted. A draft without a price
  /// is refused by `confirm_listing_draft`, so the button counts what will
  /// succeed rather than what is selected.
  ///
  /// [listen] while building, so the count moves when the drafts finish
  /// loading or a price is filled in; a plain read would leave the button
  /// saying "Pasang 0" over a list that has since arrived.
  List<int> _postable({bool listen = false}) {
    final selected = listen
        ? ref.watch(draftSelectionProvider)
        : ref.read(draftSelectionProvider);
    final draftsAsync = listen
        ? ref.watch(sellerDraftsProvider)
        : ref.read(sellerDraftsProvider);
    final drafts = draftsAsync.valueOrNull ?? const [];
    return [
      for (final d in drafts)
        if (selected.contains(d.id) && d.isReady) d.id,
    ];
  }

  Future<void> _post() async {
    final ids = _postable();
    if (ids.isEmpty || _busy) return;
    setState(() => _busy = true);

    final repo = ref.read(sellerListingsRepositoryProvider);
    String? failure;
    var posted = 0;
    for (final id in ids) {
      final error = await repo.confirmDraft(id);
      if (error == null) {
        posted++;
      } else {
        failure ??= error;
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);
    ref.read(draftSelectionProvider.notifier).state = const {};
    await widget.onDone();
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(failure ?? '$posted listing dipasang'),
          persist: false,
        ),
      );
  }

  Future<void> _delete() async {
    final ids = ref.read(draftSelectionProvider).toList();
    if (ids.isEmpty) return;

    await showConfirmDialog(
      context,
      title: 'Hapus draft?',
      description: '${ids.length} draft akan dihapus.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () async {
        setState(() => _busy = true);
        final repo = ref.read(sellerListingsRepositoryProvider);
        String? failure;
        for (final id in ids) {
          failure ??= await repo.deleteDraft(id);
        }
        if (!mounted) return;
        setState(() => _busy = false);
        ref.read(draftSelectionProvider.notifier).state = const {};
        await widget.onDone();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(failure ?? '${ids.length} draft dihapus'),
              persist: false,
            ),
          );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(draftSelectionProvider);
    if (selected.isEmpty) return const SizedBox.shrink();

    final colors = context.appColors;
    final success = context.appSemantic.success;
    final postable = _postable(listen: true).length;

    return Padding(
      // Close to the nav pill rather than floating above it: the bar and the
      // nav are the two things pinned to the bottom, and a gap between them
      // read as a third layer.
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 7, 7, 7),
        decoration: BoxDecoration(
          color: colors.onSurface,
          // A rounded rectangle, not a stadium. `AppRadius.full` gave the
          // bar semicircular ends, which read as a floating pill; squarer
          // corners let it sit as a bar across the bottom of the list.
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            // The count takes whatever is left, which is what pushes the two
            // actions to the right edge. It ellipsises rather than wrapping:
            // a bar pinned over the list has nowhere to grow.
            Expanded(
              child: Text(
                '${selected.length} dipilih',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmSemibold(
                  Theme.of(context).cardColor,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(LucideIcons.trash2, size: 18),
              color: Theme.of(context).cardColor,
              tooltip: 'Hapus draft terpilih',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              padding: EdgeInsets.zero,
              onPressed: _busy ? null : _delete,
            ),
            const SizedBox(width: 6),
            // Sized to its label rather than flexed: it is the action the
            // bar exists for, and a button that shrinks as the count grows
            // gets smaller exactly when it matters more.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.55,
              ),
              child: FilledButton.icon(
                // Counts what will actually post. Ticking five drafts of
                // which two are priced and being told "Pasang 5 listing"
                // would be a promise the server then refuses three times.
                onPressed: _busy || postable == 0 ? null : _post,
                icon: const Icon(LucideIcons.check, size: 15),
                label: Text(
                  'Pasang $postable listing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  // A step tighter than the bar around it, so the two
                  // corners nest instead of tracing the same curve.
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
