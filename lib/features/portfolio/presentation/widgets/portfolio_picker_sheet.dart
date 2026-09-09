import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../home/repository/models/portfolio_value.dart';
import '../../../home/usecase/portfolio_value_notifier.dart';
import '../../repository/models/wantlist_model.dart';
import '../../usecase/portfolio_notifier.dart';
import '../deck_form_sheet.dart';

/// Opens the portfolio picker: switch between the whole collection and any
/// saved list, star a default, or create, rename and delete one.
///
/// Shared by Beranda's value header and the Koleksi title, so both screens
/// offer the same sheet and act on the same selection.
Future<void> showPortfolioPicker(BuildContext context, WidgetRef ref) async {
  final result = await showModalBottomSheet<_PickerResult>(
    context: context,
    // The root navigator, not the shell branch this page sits in: a sheet
    // mounted on the branch is confined to the Scaffold body and gets cut
    // off by the bottom nav, rather than laying over it.
    useRootNavigator: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    // A Consumer so the rows react while the sheet is open: starring a
    // default and deleting a list both change what should be drawn here.
    builder: (sheetContext) => Consumer(
      builder: (sheetContext, sheetRef, _) {
        final colors = context.appColors;
        final rows = sheetRef.watch(portfolioTargetsProvider);
        final current = sheetRef.watch(selectedPortfolioProvider);
        final defaultId = sheetRef.watch(defaultPortfolioIdProvider);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pilih portofolio',
                        style: AppTypography.h3(colors.onSurface),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.of(
                        sheetContext,
                      ).pop(const _CreateListRequest()),
                      icon: const Icon(LucideIcons.plus, size: 16),
                      label: const Text('Buat list'),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              for (final target in rows)
                _TargetRow(
                  target: target,
                  selected: target == current,
                  isDefault: target.listId == defaultId,
                  onSelect: () =>
                      Navigator.of(sheetContext).pop(_PickedTarget(target)),
                  // Starring doesn't close the sheet — it's a setting, not
                  // a choice of what to look at now.
                  onStar: () => sheetRef
                      .read(defaultPortfolioIdProvider.notifier)
                      .set(target.listId),
                  onEdit: target.isPrimary
                      ? null
                      : () => Navigator.of(
                          sheetContext,
                        ).pop(_EditListRequest(target)),
                  onDelete: target.isPrimary
                      ? null
                      : () => Navigator.of(
                          sheetContext,
                        ).pop(_DeleteListRequest(target)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );

  switch (result) {
    case _PickedTarget(:final target):
      ref.read(selectedPortfolioProvider.notifier).select(target);
    case _CreateListRequest():
      if (context.mounted) await _createList(context, ref);
    case _EditListRequest(:final target):
      if (context.mounted) await _editList(context, ref, target);
    case _DeleteListRequest(:final target):
      if (context.mounted) await _deleteList(context, ref, target);
    case null:
      break;
  }
}

/// Renames a list, prefilled from the row it belongs to.
Future<void> _editList(
  BuildContext context,
  WidgetRef ref,
  PortfolioTarget target,
) async {
  final user = ref.read(authProvider).valueOrNull;
  final list = _listFor(ref, target);
  if (user == null || list == null) return;

  final form = await showModalBottomSheet<({String name, String description})>(
    context: context,
    useRootNavigator: true,
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
  if (form == null) return;

  final error = await ref
      .read(portfolioRepositoryProvider)
      .updateList(
        listId: list.id,
        userId: user.id,
        name: form.name,
        description: form.description,
      );
  if (!context.mounted) return;
  if (error != null) {
    _toast(context, error);
    return;
  }
  ref.invalidate(listsProvider);
  _toast(context, 'List diperbarui');
}

Future<void> _deleteList(
  BuildContext context,
  WidgetRef ref,
  PortfolioTarget target,
) async {
  final user = ref.read(authProvider).valueOrNull;
  final list = _listFor(ref, target);
  if (user == null || list == null) return;

  await showConfirmDialog(
    context,
    title: 'Hapus list?',
    description:
        'List "${list.name}" dan semua kartu di dalamnya akan dihapus '
        'permanen.',
    confirmLabel: 'Hapus',
    loadingLabel: 'Menghapus...',
    onConfirm: () async {
      final error = await ref
          .read(portfolioRepositoryProvider)
          .deleteList(listId: list.id, userId: user.id);
      if (error != null) {
        if (context.mounted) _toast(context, error);
        return;
      }
      // A starred list that no longer exists would leave Beranda pointing
      // at nothing on next launch.
      if (ref.read(defaultPortfolioIdProvider) == list.id) {
        await ref.read(defaultPortfolioIdProvider.notifier).set(null);
      }
      ref.invalidate(listsProvider);
      if (context.mounted) _toast(context, 'List dihapus');
    },
  );
}

/// The saved list behind a target, for the actions that need its fields.
WantlistModel? _listFor(WidgetRef ref, PortfolioTarget target) {
  final lists = ref.read(listsProvider).valueOrNull ?? const <WantlistModel>[];
  for (final list in lists) {
    if (list.id == target.listId) return list;
  }
  return null;
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message), persist: false));
}

/// Same create flow as the Lists page, so a list made from here is the
/// same thing made there — then the graph switches to it, since making a
/// list from the picker is a way of asking to see it.
Future<void> _createList(BuildContext context, WidgetRef ref) async {
  final user = ref.read(authProvider).valueOrNull;
  if (user == null) return;

  final form = await showModalBottomSheet<({String name, String description})>(
    context: context,
    // Same reason as the picker: the shell branch would clip it.
    useRootNavigator: true,
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
  if (form == null) return;

  final created = await ref
      .read(portfolioRepositoryProvider)
      .createList(
        userId: user.id,
        name: form.name,
        description: form.description,
      );
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  if (created.error != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(created.error!), persist: false),
    );
    return;
  }

  final list = created.list!;
  ref.invalidate(listsProvider);
  ref
      .read(selectedPortfolioProvider.notifier)
      .select(PortfolioTarget(name: list.name, listId: list.id));
  messenger.showSnackBar(
    SnackBar(content: Text('List "${list.name}" dibuat'), persist: false),
  );
}

/// What the picker sheet came back with.

sealed class _PickerResult {
  const _PickerResult();
}

class _PickedTarget extends _PickerResult {
  const _PickedTarget(this.target);
  final PortfolioTarget target;
}

class _CreateListRequest extends _PickerResult {
  const _CreateListRequest();
}

class _EditListRequest extends _PickerResult {
  const _EditListRequest(this.target);
  final PortfolioTarget target;
}

class _DeleteListRequest extends _PickerResult {
  const _DeleteListRequest(this.target);
  final PortfolioTarget target;
}

/// One row of the picker: the portfolio, whether it's the default, and the
/// actions on it. The main collection isn't a list, so it can be starred but
/// not renamed or deleted.
class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.target,
    required this.selected,
    required this.isDefault,
    required this.onSelect,
    required this.onStar,
    required this.onEdit,
    required this.onDelete,
  });

  final PortfolioTarget target;
  final bool selected;
  final bool isDefault;
  final VoidCallback onSelect;
  final VoidCallback onStar;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
        child: Row(
          children: [
            if (selected) ...[
              Icon(LucideIcons.check, size: 18, color: colors.primary),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                target.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: selected
                    ? AppTypography.bodySmSemibold(colors.onSurface)
                    : AppTypography.bodySm(colors.onSurface),
              ),
            ),
            _RowAction(
              icon: isDefault ? LucideIcons.star : LucideIcons.star,
              color: isDefault ? const Color(0xFFE0A83A) : null,
              tooltip: isDefault
                  ? 'Portofolio default'
                  : 'Jadikan portofolio default',
              onPressed: onStar,
            ),
            if (onEdit != null)
              _RowAction(
                icon: LucideIcons.pencil,
                tooltip: 'Edit list',
                onPressed: onEdit!,
              ),
            if (onDelete != null)
              _RowAction(
                icon: LucideIcons.trash2,
                color: colors.error,
                tooltip: 'Hapus list',
                onPressed: onDelete!,
              ),
          ],
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 19),
      color: color ?? context.mutedForeground,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

/// `1H 7H 1B 3B 6B MAX`.

/// Asks which list to send cards to — the destination step of the Kelola
/// batch actions.
///
/// Offers a way out of the dead end a user with no lists would otherwise
/// hit, by letting them create one here.
Future<WantlistModel?> showListPicker(
  BuildContext context,
  WidgetRef ref, {
  String? excludeListId,
  String title = 'Pilih list',
}) async {
  final all = ref.read(listsProvider).valueOrNull ?? const <WantlistModel>[];
  final lists = all.where((l) => l.id != excludeListId).toList();

  final picked = await showModalBottomSheet<Object>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.h3(context.appColors.onSurface),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(_MakeList()),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Buat list'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.appColors.primary,
                  ),
                ),
              ],
            ),
          ),
          if (lists.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Text(
                'Belum ada list lain. Buat satu dulu.',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
            )
          else
            for (final list in lists)
              ListTile(
                title: Text(
                  list.name,
                  style: AppTypography.bodySm(context.appColors.onSurface),
                ),
                subtitle: Text(
                  '${list.cardCount} kartu',
                  style: AppTypography.caption(context.mutedForeground),
                ),
                onTap: () => Navigator.of(sheetContext).pop(list),
              ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (picked is WantlistModel) return picked;
  if (picked is _MakeList && context.mounted) {
    return createPortfolioList(context, ref);
  }
  return null;
}

/// The "Buat list" row's sentinel — a new list to send the cards to.
class _MakeList {}

/// Runs the "Buat List Baru" form and creates the list, returning it so the
/// caller can use it as a destination. Shared with the add-destination sheet
/// so a list made while filing cards is the same thing made anywhere else.
Future<WantlistModel?> createPortfolioList(
  BuildContext context,
  WidgetRef ref,
) async {
  final user = ref.read(authProvider).valueOrNull;
  if (user == null) return null;

  final form = await showModalBottomSheet<({String name, String description})>(
    context: context,
    useRootNavigator: true,
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
  if (form == null) return null;

  final created = await ref
      .read(portfolioRepositoryProvider)
      .createList(
        userId: user.id,
        name: form.name,
        description: form.description,
      );
  ref.invalidate(listsProvider);
  if (created.error != null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(created.error!), persist: false));
  }
  return created.list;
}
