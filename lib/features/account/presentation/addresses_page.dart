import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../seller/presentation/seller_store_profile_page.dart'
    show SellerPickupCard;
import '../../settings/presentation/settings_page.dart' show SettingsSection;
import '../repository/models/address_model.dart';
import '../usecase/address_notifier.dart';
import 'widgets/address_form_sheet.dart';

/// Ports web's Pengaturan → Alamat tab: `SettingsAddressBook` over
/// `SellerPickupCard`. Each is one `SettingsSection`-style card, the same
/// `bg-secondary/30` panel the settings page uses, so the two pages read as
/// one surface.
class AddressesPage extends ConsumerWidget {
  const AddressesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(addressesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            SettingsSection(
              title: 'Alamat Pengiriman',
              description:
                  'Kelola alamat tujuan pengiriman pembelian kartu kamu.',
              children: [
                addressesAsync.when(
                  data: (addresses) => _AddressBook(addresses: addresses),
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  error: (_, __) => const EmptyState(
                    icon: LucideIcons.circleAlert,
                    title: 'Gagal memuat alamat',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SellerPickupCard(),
          ],
        ),
      ),
    );
  }
}

/// Ports `AddressList` in "manage" mode: a search box once there is enough
/// to search, the dashed add button, then the rows.
class _AddressBook extends StatefulWidget {
  const _AddressBook({required this.addresses});

  final List<AddressModel> addresses;

  @override
  State<_AddressBook> createState() => _AddressBookState();
}

class _AddressBookState extends State<_AddressBook> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AddressModel> get _filtered {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.addresses;
    return widget.addresses.where((a) {
      return a.label.toLowerCase().contains(query) ||
          a.contactName.toLowerCase().contains(query) ||
          a.cityName.toLowerCase().contains(query) ||
          a.district.toLowerCase().contains(query) ||
          a.fullAddress.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final addresses = widget.addresses;
    final filtered = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Web only offers the search once there is a list worth filtering.
        if (addresses.isNotEmpty) ...[
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Cari nama, kota, atau kecamatan',
              prefixIcon: Icon(LucideIcons.search, size: 16),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _AddAddressButton(onTap: () => showAddressFormSheet(context)),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          _DashedPanel(
            child: Text(
              addresses.isEmpty
                  ? 'Belum ada alamat tersimpan'
                  : 'Tidak ada alamat cocok',
              textAlign: TextAlign.center,
              style: AppTypography.bodySm(context.mutedForeground),
            ),
          )
        else
          for (final address in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AddressCard(address: address),
            ),
      ],
    );
  }
}

/// Web's `border-2 border-dashed border-primary/40 bg-primary/5` call to
/// action. Flutter has no dashed border, so [_DashedBorderPainter] draws it.
class _AddAddressButton extends StatelessWidget {
  const _AddAddressButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _DashedPanel(
      color: colors.primary.withValues(alpha: 0.4),
      fill: colors.primary.withValues(alpha: 0.05),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.plus, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Text(
            'Tambah Alamat Baru',
            style: AppTypography.bodySmSemibold(colors.primary),
          ),
        ],
      ),
    );
  }
}

/// A dashed-outline panel — the add button and the empty state both use it,
/// as they do on the web.
class _DashedPanel extends StatelessWidget {
  const _DashedPanel({
    required this.child,
    this.color,
    this.fill,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
  });

  final Widget child;
  final Color? color;
  final Color? fill;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color ?? context.borderColor,
        radius: AppRadius.lg,
        fill: fill,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.radius,
    this.fill,
  });

  final Color color;
  final double radius;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    final background = fill;
    if (background != null) {
      canvas.drawRRect(rect, Paint()..color = background);
    }

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Walk the rounded rect, drawing 5px on and 4px off.
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), stroke);
        distance = next + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.fill != fill || old.radius != radius;
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
