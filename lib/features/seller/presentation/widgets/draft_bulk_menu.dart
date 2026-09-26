import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../repository/seller_listings_repository.dart';
import '../../usecase/seller_listings_notifier.dart';
import 'seller_switch.dart';

/// The button beside the draft search box, and the menu it drops.
///
/// Every row in it speaks for the whole pile rather than one draft. That is
/// the point of it: setting "Perpanjang otomatis" on forty drafts one switch
/// at a time is forty taps to say one thing, and the thing being said is
/// identical every time.
class DraftBulkMenu extends ConsumerStatefulWidget {
  const DraftBulkMenu({super.key, required this.onChanged});

  /// Called once a write lands, so the list behind the menu can re-read.
  final VoidCallback onChanged;

  @override
  ConsumerState<DraftBulkMenu> createState() => _DraftBulkMenuState();
}

class _DraftBulkMenuState extends ConsumerState<DraftBulkMenu> {
  bool _busy = false;

  Future<void> _applyToAll({bool? autoRelist, bool? acceptsOffers}) async {
    if (_busy) return;
    setState(() => _busy = true);

    final error = await ref
        .read(sellerListingsRepositoryProvider)
        .updateAllDrafts(autoRelist: autoRelist, acceptsOffers: acceptsOffers);

    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) widget.onChanged();

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(error ?? 'Diterapkan ke semua listing'),
          persist: false,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final drafts = ref.watch(sellerDraftsProvider).valueOrNull ?? const [];

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
        _SelectAllRow(count: drafts.length),
        const Divider(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'TERAPKAN KE SEMUA LISTING',
            style: AppTypography.overline(context.mutedForeground),
          ),
        ),
        _BulkSwitchRow(
          icon: LucideIcons.refreshCw,
          label: 'Perpanjang otomatis',
          // The switch reads the pile: on only when every draft has it, so
          // a mixed set shows off and one tap makes it true of all of them.
          value: drafts.isNotEmpty && drafts.every((d) => d.autoRelist),
          enabled: drafts.isNotEmpty && !_busy,
          onChanged: (v) => _applyToAll(autoRelist: v),
        ),
        _BulkSwitchRow(
          icon: LucideIcons.handCoins,
          label: 'Terima penawaran',
          value: drafts.isNotEmpty && drafts.every((d) => d.acceptsOffers),
          enabled: drafts.isNotEmpty && !_busy,
          onChanged: (v) => _applyToAll(acceptsOffers: v),
        ),
        _MarketPriceRow(
          enabled: drafts.isNotEmpty && !_busy,
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
  const _SelectAllRow({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          Icon(LucideIcons.square, size: 22, color: colors.onSurface),
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
