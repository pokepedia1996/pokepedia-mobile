import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/wantlist_model.dart';
import '../usecase/portfolio_notifier.dart';
import 'deck_form_sheet.dart';

/// Ports `app/portfolio/list/page.tsx` — the buyer's saved lists, each with
/// its share link, duplicate, edit and delete actions.
class ListsPage extends ConsumerStatefulWidget {
  const ListsPage({super.key});

  @override
  ConsumerState<ListsPage> createState() => _ListsPageState();
}

class _ListsPageState extends ConsumerState<ListsPage> {
  /// Which list is mid-duplicate, so only that card shows a spinner —
  /// mirrors the web's `duplicatingId`.
  String? _duplicatingId;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }

  Future<void> _create() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final result = await showModalBottomSheet<({String name, String description})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => const DeckFormSheet(
        title: 'Buat List Baru',
        submitLabel: 'Buat',
        nameLabel: 'Nama list',
      ),
    );
    if (result == null) return;

    final created = await ref.read(portfolioRepositoryProvider).createList(
      userId: user.id,
      name: result.name,
      description: result.description,
    );
    if (created.error != null) {
      _toast(created.error!);
      return;
    }
    ref.invalidate(listsProvider);
    _toast('List "${created.list!.name}" dibuat');
  }

  Future<void> _edit(WantlistModel list) async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final result = await showModalBottomSheet<({String name, String description})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => DeckFormSheet(
        title: 'Edit List',
        submitLabel: 'Simpan',
        nameLabel: 'Nama list',
        initialName: list.name,
        initialDescription: list.description,
      ),
    );
    if (result == null) return;

    final error = await ref.read(portfolioRepositoryProvider).updateList(
      listId: list.id,
      userId: user.id,
      name: result.name,
      description: result.description,
    );
    if (error != null) {
      _toast(error);
      return;
    }
    ref.invalidate(listsProvider);
    _toast('List diperbarui');
  }

  Future<void> _delete(WantlistModel list) {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return Future.value();

    return showConfirmDialog(
      context,
      title: 'Hapus list?',
      description:
          'List "${list.name}" dan semua kartu di dalamnya akan dihapus permanen.',
      confirmLabel: 'Hapus',
      loadingLabel: 'Menghapus...',
      onConfirm: () async {
        final error = await ref.read(portfolioRepositoryProvider).deleteList(
          listId: list.id,
          userId: user.id,
        );
        if (error != null) {
          _toast(error);
          return;
        }
        ref.invalidate(listsProvider);
        _toast('List dihapus');
      },
    );
  }

  Future<void> _duplicate(WantlistModel list) async {
    setState(() => _duplicatingId = list.id);
    final result =
        await ref.read(portfolioRepositoryProvider).duplicateList(list.id);
    if (!mounted) return;
    setState(() => _duplicatingId = null);

    if (result.error != null) {
      _toast(result.error!);
      return;
    }
    ref.invalidate(listsProvider);
    _toast('List berhasil diduplikasi');
  }

  Future<void> _copyShareLink(WantlistModel list) async {
    // Same URL the web copies: the share code resolves for anyone, which is
    // what `Public read via share_code` on `lists` is for.
    await Clipboard.setData(
      ClipboardData(text: '${AppConfig.appUrl}/list/${list.shareCode}'),
    );
    _toast('Link disalin ke clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final user = ref.watch(authProvider).valueOrNull;
    final async = ref.watch(listsProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: user == null
            ? EmptyState(
                icon: Icons.checklist,
                title: 'Masuk untuk melihat list',
                description: 'Silakan masuk untuk melihat list kartu kamu.',
                action: ElevatedButton(
                  onPressed: () => context.push(Routes.login),
                  child: const Text('Masuk'),
                ),
              )
            : async.when(
                loading: () => const PikachuLoader(),
                error: (_, __) =>
                    const Center(child: Text('Gagal memuat list')),
                data: (lists) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(listsProvider);
                    await ref.read(listsProvider.future);
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Text(
                        'List Kartu',
                        style: AppTypography.h1(colors.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${lists.length} list',
                            style: AppTypography.bodySm(
                              context.mutedForeground,
                            ),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _create,
                            icon: const Icon(Icons.add, size: 15),
                            label: const Text('Buat List Baru'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (lists.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: EmptyState(
                            icon: Icons.checklist,
                            title: 'Belum ada list',
                            description:
                                'Buat list pertamamu untuk mulai mengatur kartu!',
                          ),
                        )
                      else
                        for (final list in lists) ...[
                          _ListCard(
                            list: list,
                            duplicating: _duplicatingId == list.id,
                            onCopyLink: () => _copyShareLink(list),
                            onDuplicate: () => _duplicate(list),
                            onEdit: () => _edit(list),
                            onDelete: () => _delete(list),
                          ),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// One list. Ports the web card: icon tile, name, description, the
/// "N kartu · date" line, then the action row beneath a rule.
class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.list,
    required this.duplicating,
    required this.onCopyLink,
    required this.onDuplicate,
    required this.onEdit,
    required this.onDelete,
  });

  final WantlistModel list;
  final bool duplicating;
  final VoidCallback onCopyLink;
  final VoidCallback onDuplicate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push(Routes.listDetail(list.id)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      Icons.checklist,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          list.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmSemibold(
                            colors.onSurface,
                          ),
                        ),
                        if (list.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            list.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption(
                              context.mutedForeground,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          _metaLine(list),
                          style: AppTypography.caption(
                            context.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: context.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: context.borderColor),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                _ListAction(
                  icon: Icons.link,
                  label: 'Salin Link',
                  onTap: onCopyLink,
                ),
                _ListAction(
                  icon: Icons.copy_all_outlined,
                  label: 'Duplikat',
                  onTap: onDuplicate,
                  busy: duplicating,
                ),
                const Spacer(),
                _ListAction(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: onEdit,
                ),
                _ListAction(
                  icon: Icons.delete_outline,
                  label: 'Hapus',
                  onTap: onDelete,
                  destructive: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "12 kartu · 21/08/2026" — the web's `cardCount` + localised created
  /// date.
  static String _metaLine(WantlistModel list) {
    final created = list.createdAt;
    final date = created == null
        ? null
        : '${created.day.toString().padLeft(2, '0')}/'
              '${created.month.toString().padLeft(2, '0')}/'
              '${created.year}';
    return [
      '${list.cardCount} kartu',
      if (date != null) date,
    ].join(' · ');
  }
}

class _ListAction extends StatelessWidget {
  const _ListAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color =
        destructive ? context.appColors.error : context.mutedForeground;

    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: AppTypography.caption(color)),
          ],
        ),
      ),
    );
  }
}
