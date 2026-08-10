import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/card_ownership_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/models/deck_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../usecase/portfolio_notifier.dart';
import 'deck_form_sheet.dart';

const _deckMaxCards = 60;

/// Ports `app/portfolio/deck/page.tsx` — deck list with create / rename /
/// duplicate / delete / share-link, mirroring the web's card grid.
class DeckTab extends ConsumerStatefulWidget {
  const DeckTab({super.key});

  @override
  ConsumerState<DeckTab> createState() => _DeckTabState();
}

class _DeckTabState extends ConsumerState<DeckTab> {
  String _query = '';

  Future<void> _openCreateSheet() async {
    final result =
        await showModalBottomSheet<({String name, String description})>(
          context: context,
          isScrollControlled: true,
          builder: (context) =>
              const DeckFormSheet(title: 'Buat Deck Baru', submitLabel: 'Buat'),
        );
    if (result == null || !mounted) return;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final res = await ref
        .read(cardOwnershipControllerProvider)
        .createDeck(
          userId: user.id,
          name: result.name,
          description: result.description,
        );
    if (!mounted) return;
    if (res.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.error!)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Deck "${res.deck!.name}" dibuat')));
    context.push(Routes.deckDetail(res.deck!.id));
  }

  Future<void> _openEditSheet(DeckModel deck) async {
    final result =
        await showModalBottomSheet<({String name, String description})>(
          context: context,
          isScrollControlled: true,
          builder: (context) => DeckFormSheet(
            title: 'Edit Deck',
            submitLabel: 'Simpan',
            initialName: deck.name,
            initialDescription: deck.description,
          ),
        );
    if (result == null || !mounted) return;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .updateDeck(
          deckId: deck.id,
          userId: user.id,
          name: result.name,
          description: result.description,
        );
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Deck diperbarui')));
  }

  Future<void> _confirmDelete(DeckModel deck) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Hapus deck?'),
        content: Text(
          'Deck "${deck.name}" dan semua kartu di dalamnya akan dihapus permanen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.appColors.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    final error = await ref
        .read(cardOwnershipControllerProvider)
        .deleteDeck(deckId: deck.id, userId: user.id);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Deck dihapus')));
  }

  Future<void> _duplicate(DeckModel deck) async {
    final res = await ref
        .read(cardOwnershipControllerProvider)
        .duplicateDeck(deck.id);
    if (!mounted) return;
    if (res.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(res.error!)));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Deck berhasil diduplikasi')));
  }

  Future<void> _copyShareLink(DeckModel deck) async {
    await Clipboard.setData(
      ClipboardData(text: 'https://pokepedia.id/deck/${deck.shareCode}'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Link disalin ke clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(decksProvider);
    return async.when(
      data: (decks) {
        final visible = _query.isEmpty
            ? decks
            : decks
                  .where(
                    (d) => d.name.toLowerCase().contains(_query.toLowerCase()),
                  )
                  .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${decks.length} deck',
                      style: AppTypography.bodySm(context.mutedForeground),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _openCreateSheet,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Buat Deck Baru'),
                  ),
                ],
              ),
            ),
            if (decks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Cari deck...',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                ),
              ),
            Expanded(
              child: decks.isEmpty
                  ? const EmptyState(
                      icon: Icons.style_outlined,
                      title: 'Belum ada deck',
                      description:
                          'Buat deck pertamamu untuk mulai membangun strategi!',
                    )
                  : visible.isEmpty
                  ? Center(
                      child: Text(
                        'Tidak ada deck yang cocok.',
                        style: AppTypography.bodySm(context.mutedForeground),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _DeckTile(
                        deck: visible[i],
                        onTap: () =>
                            context.push(Routes.deckDetail(visible[i].id)),
                        onEdit: () => _openEditSheet(visible[i]),
                        onDelete: () => _confirmDelete(visible[i]),
                        onDuplicate: () => _duplicate(visible[i]),
                        onCopyLink: () => _copyShareLink(visible[i]),
                      ),
                    ),
            ),
          ],
        );
      },
      loading: () => const PikachuLoader(),
      error: (_, __) => const Center(child: Text('Gagal memuat deck')),
    );
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({
    required this.deck,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onCopyLink,
  });

  final DeckModel deck;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final full = deck.cardCount >= _deckMaxCards;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    Icons.layers_outlined,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmSemibold(colors.onSurface),
                      ),
                      if (deck.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          deck.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '${deck.cardCount}/$_deckMaxCards kartu',
                        style: AppTypography.caption(
                          full
                              ? context.appSemantic.success
                              : context.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: context.mutedForeground,
                    size: 20,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case 'copy':
                        onCopyLink();
                      case 'duplicate':
                        onDuplicate();
                      case 'edit':
                        onEdit();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 16),
                          SizedBox(width: 8),
                          Text('Salin Link'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Row(
                        children: [
                          Icon(Icons.copy_all, size: 16),
                          SizedBox(width: 8),
                          Text('Buat Duplikat'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 16),
                          SizedBox(width: 8),
                          Text('Hapus'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
