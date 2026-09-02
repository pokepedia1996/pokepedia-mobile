import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/address_model.dart';
import '../usecase/address_notifier.dart';
import 'widgets/address_form_sheet.dart';

/// Ports `features/address`' address book (web's Pengaturan → Alamat tab):
/// the buyer's saved delivery addresses, with the primary one pinned to the
/// top and used as the default at checkout.
class AddressesPage extends ConsumerWidget {
  const AddressesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final addressesAsync = ref.watch(addressesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddressFormSheet(context),
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text('Tambah Alamat'),
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
      ),
      body: AppBarOverlayBody(
        child: addressesAsync.when(
          data: (addresses) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text('Alamat', style: AppTypography.h2(colors.onSurface)),
              const SizedBox(height: 4),
              Text(
                'Alamat utama dipakai sebagai tujuan pengiriman default saat '
                'checkout.',
                style: AppTypography.bodySm(context.mutedForeground),
              ),
              const SizedBox(height: 18),
              if (addresses.isEmpty)
                const EmptyState(
                  icon: LucideIcons.mapPin,
                  title: 'Belum ada alamat tersimpan',
                  description:
                      'Tambahkan alamat pengiriman supaya checkout bisa '
                      'langsung memakainya.',
                )
              else
                for (final address in addresses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AddressCard(address: address),
                  ),
            ],
          ),
          loading: () => const PikachuLoader(),
          error: (_, __) => const EmptyState(
            icon: LucideIcons.circleAlert,
            title: 'Gagal memuat alamat',
          ),
        ),
      ),
    );
  }
}

class _AddressCard extends ConsumerStatefulWidget {
  const _AddressCard({required this.address});

  final AddressModel address;

  @override
  ConsumerState<_AddressCard> createState() => _AddressCardState();
}

class _AddressCardState extends ConsumerState<_AddressCard> {
  bool _busy = false;

  Future<void> _run(Future<String?> Function() action, String success) async {
    setState(() => _busy = true);
    final error = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(error ?? success)));
    if (error == null) ref.invalidate(addressesProvider);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Hapus alamat?'),
        content: Text('"${widget.address.label}" akan dihapus permanen.'),
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
    await _run(
      () => ref
          .read(addressRepositoryProvider)
          .deleteAddress(widget.address.slug),
      'Alamat dihapus',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final address = widget.address;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(
          color: address.isPrimary
              ? colors.primary.withValues(alpha: 0.5)
              : context.borderColor,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  address.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
              ),
              if (address.isPrimary) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(
                    'Utama',
                    style: AppTypography.badge(colors.primary),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${address.contactName} · ${address.contactPhone}',
            style: AppTypography.bodySm(colors.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            address.fullAddress,
            style: AppTypography.bodySm(context.mutedForeground),
          ),
          Text(
            address.areaLine,
            style: AppTypography.caption(context.mutedForeground),
          ),
          if (address.notes != null && address.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Catatan: ${address.notes}',
              style: AppTypography.caption(context.mutedForeground),
            ),
          ],
          const SizedBox(height: 10),
          Divider(height: 1, color: context.borderColor),
          Row(
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => showAddressFormSheet(context, address: address),
                child: const Text('Ubah'),
              ),
              if (!address.isPrimary)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => ref
                              .read(addressRepositoryProvider)
                              .setPrimary(address.id),
                          'Alamat utama diperbarui',
                        ),
                  child: const Text('Jadikan utama'),
                ),
              const Spacer(),
              TextButton(
                onPressed: _busy ? null : _confirmDelete,
                child: Text(
                  'Hapus',
                  style: AppTypography.bodySmSemibold(colors.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
