import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../repository/models/seller_listing.dart';
import '../../repository/seller_listings_repository.dart';
import '../../usecase/seller_listings_notifier.dart';
import 'seller_switch.dart';

/// The button beside the draft search box, and the menu it drops.
///
/// Every row in it speaks for a set of drafts rather than one. That is the
/// point of it: setting "Perpanjang otomatis" on forty drafts one switch at
/// a time is forty taps to say one thing, and the thing being said is
/// identical every time.
///
/// The set is whatever is ticked. It used to be "all of them", which made
/// the tick boxes on the cards beside it mean nothing here — and left no way
/// to say the thing about half the pile.
class DraftBulkMenu extends ConsumerStatefulWidget {
  const DraftBulkMenu({super.key, required this.onChanged});

  /// Called once a write lands, so the list behind the menu can re-read.
  final VoidCallback onChanged;

  @override
  ConsumerState<DraftBulkMenu> createState() => _DraftBulkMenuState();
}

class _DraftBulkMenuState extends ConsumerState<DraftBulkMenu> {
  bool _busy = false;

  Future<void> _applyToSelected({bool? autoRelist, bool? acceptsOffers}) async {
    if (_busy) return;
    final ids = ref.read(draftSelectionProvider).toList();
    if (ids.isEmpty) return;
    setState(() => _busy = true);

    final error = await ref
        .read(sellerListingsRepositoryProvider)
        .updateDrafts(
          ids: ids,
          autoRelist: autoRelist,
          acceptsOffers: acceptsOffers,
        );

    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) widget.onChanged();

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(error ?? 'Diterapkan ke ${ids.length} listing'),
          persist: false,
        ),
      );
  }

  /// Ticks every draft on screen, or clears them if they already are.
  ///
  /// Scoped to the filtered list rather than the table: the count beside the
  /// row is what the seller can see, and a tap that quietly also took the
  /// drafts behind an active filter would apply the next switch to rows they
  /// are not looking at.
  void _toggleSelectAll(List<SellerDraft> visible) {
    final selection = ref.read(draftSelectionProvider);
    final ids = visible.map((d) => d.id).toSet();
    final allTicked = ids.isNotEmpty && ids.every(selection.contains);
    ref.read(draftSelectionProvider.notifier).state = allTicked
        ? selection.difference(ids)
        : selection.union(ids);
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(visibleDraftsProvider);
    final selection = ref.watch(draftSelectionProvider);
    // The switches read the drafts they are about to write to, so a set that
    // already has the flag shows it on.
    final chosen = [
      for (final draft
          in ref.watch(sellerDraftsProvider).valueOrNull ??
              const <SellerDraft>[])
        if (selection.contains(draft.id)) draft,
    ];
    final visibleIds = visible.map((d) => d.id).toSet();
    final ready = chosen.isNotEmpty && !_busy;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Theme.of(context).cardColor),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
      ),
      builder: (context, controller, _) => _MenuButton(
        open: controller.isOpen,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        _SelectAllRow(
          count: visible.length,
          // Three states, as a checkbox over a list has to have: every one
          // ticked, some of them, or none.
          value: visibleIds.isNotEmpty && visibleIds.every(selection.contains),
          partial: visibleIds.any(selection.contains),
          onTap: visible.isEmpty ? null : () => _toggleSelectAll(visible),
        ),
        const Divider(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'TERAPKAN KE LISTING TERPILIH',
            style: AppTypography.overline(context.mutedForeground),
          ),
        ),
        _BulkSwitchRow(
          icon: LucideIcons.refreshCw,
          label: 'Perpanjang otomatis',
          // On only when every chosen draft has it, so a mixed set shows off
          // and one tap makes it true of all of them.
          value: chosen.isNotEmpty && chosen.every((d) => d.autoRelist),
          enabled: ready,
          onChanged: (v) => _applyToSelected(autoRelist: v),
        ),
        _BulkSwitchRow(
          icon: LucideIcons.handCoins,
          label: 'Terima penawaran',
          value: chosen.isNotEmpty && chosen.every((d) => d.acceptsOffers),
          enabled: ready,
          onChanged: (v) => _applyToSelected(acceptsOffers: v),
        ),
        _MarketPriceRow(
          enabled: ready,
          onTap: () {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Harga pasar belum tersedia'),
                  persist: false,
                ),
              );
          },
        ),
      ],
    );
  }
}

/// The square button itself. Dark while the menu is down, so the menu reads
/// as belonging to it rather than floating loose over the list.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Semantics(
      button: true,
      label: 'Tindakan massal listing',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: open ? colors.onSurface : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: context.borderColor),
          ),
          child: Icon(
            LucideIcons.listChecks,
            size: 18,
            color: open ? Theme.of(context).cardColor : colors.onSurface,
          ),
        ),
      ),
    );
  }
}

/// "Pilih semua listing", with how many that is.
class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({
    required this.count,
    required this.value,
    required this.partial,
    required this.onTap,
  });

  final int count;

  /// Every visible draft is ticked.
  final bool value;

  /// At least one is — which with [value] false is the half-ticked state.
  final bool partial;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            Icon(
              value
                  ? LucideIcons.squareCheck
                  : partial
                  ? LucideIcons.squareMinus
                  : LucideIcons.square,
              size: 22,
              color: value || partial ? colors.primary : colors.onSurface,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Pilih semua listing',
                style: AppTypography.bodySemibold(colors.onSurface),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: context.mutedForeground.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '$count',
                style: AppTypography.captionSemibold(context.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One "apply to everything" switch.
class _BulkSwitchRow extends StatelessWidget {
  const _BulkSwitchRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          _RowIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: AppTypography.body(colors.onSurface)),
          ),
          SellerSwitch(value: value, onChanged: enabled ? onChanged : null),
        ],
      ),
    );
  }
}

/// "Gunakan harga pasar" — a step rather than a switch, so it keeps the
/// chevron the others don't have.
class _MarketPriceRow extends StatelessWidget {
  const _MarketPriceRow({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = context.mutedForeground;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            const _RowIcon(icon: LucideIcons.sparkles),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Gunakan harga pasar',
                style: AppTypography.body(enabled ? colors.onSurface : muted),
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: muted),
          ],
        ),
      ),
    );
  }
}

/// The rounded tile every menu row's icon sits in.
class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: context.mutedForeground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, size: 18, color: context.appColors.onSurface),
    );
  }
}
