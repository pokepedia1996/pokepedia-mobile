import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../features/orders/repository/models/seller_order_detail.dart';
import '../../repository/shipment_repository.dart';

/// Opens the dispatch form for an order that has been paid but not shipped.
/// Resolves true when the shipment was arranged.
Future<bool?> showDispatchSheet(
  BuildContext context, {
  required String shipmentSlug,
  required SellerOrderDetail detail,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _DispatchSheet(shipmentSlug: shipmentSlug, detail: detail),
  );
}

enum _DispatchChoice { pickup, manual }

/// Ports the dispatch half of `shipment-actions.tsx`: hand the parcel to a
/// courier who comes for it, or drop it off yourself and file the resi.
class _DispatchSheet extends ConsumerStatefulWidget {
  const _DispatchSheet({required this.shipmentSlug, required this.detail});

  final String shipmentSlug;
  final SellerOrderDetail detail;

  @override
  ConsumerState<_DispatchSheet> createState() => _DispatchSheetState();
}

class _DispatchSheetState extends ConsumerState<_DispatchSheet> {
  late final TextEditingController _itemName;
  late final TextEditingController _note;
  late final TextEditingController _resi;
  late _DispatchChoice _choice;
  String? _courierCode;
  bool _submitting = false;
  String? _error;

  bool get _allowsPickup => widget.detail.allowsPickup;
  bool get _allowsManual => widget.detail.allowsManualResi;

  @override
  void initState() {
    super.initState();
    _itemName = TextEditingController();
    _note = TextEditingController();
    _resi = TextEditingController();
    // Web's `defaultChoice`: pickup unless the courier refuses it.
    _choice = _allowsPickup || !_allowsManual
        ? _DispatchChoice.pickup
        : _DispatchChoice.manual;
  }

  @override
  void dispose() {
    _itemName.dispose();
    _note.dispose();
    _resi.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final repository = ref.read(shipmentRepositoryProvider);
    setState(() {
      _submitting = true;
      _error = null;
    });

    final String? error;
    if (_choice == _DispatchChoice.manual) {
      final resi = _resi.text.trim().toUpperCase();
      final courier = _courierCode;
      if (resi.length < 4) {
        setState(() {
          _submitting = false;
          _error = 'Masukkan nomor resi yang valid';
        });
        return;
      }
      if (courier == null) {
        setState(() {
          _submitting = false;
          _error = 'Pilih kurir terlebih dahulu';
        });
        return;
      }
      error = await repository.dispatchManual(
        shipmentSlug: widget.shipmentSlug,
        trackingNumber: resi,
        courierCode: courier,
      );
    } else {
      error = await repository.dispatchPickup(
        shipmentSlug: widget.shipmentSlug,
        itemName: _itemName.text.trim(),
        note: _note.text.trim(),
      );
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _choice == _DispatchChoice.manual
                ? 'Resi tersimpan. Status akan diperbarui otomatis.'
                : 'Pengiriman dijadwalkan',
          ),
        ),
      );
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (_choice == _DispatchChoice.manual) {
      return _resi.text.trim().length >= 4 && _courierCode != null;
    }
    return _itemName.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Atur Pengiriman',
                    style: AppTypography.h3(colors.onSurface),
                  ),
                ),
                IconButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(LucideIcons.x, size: 20),
                ),
              ],
            ),
            Text(
              _allowsManual
                  ? 'Pilih dijemput kurir, atau antar sendiri lalu isi nomor '
                        'resi dari counter.'
                  : 'Kurir instan hanya menjemput ke lokasi kamu dan tidak '
                        'bisa memakai resi manual.',
              style: AppTypography.bodySm(context.mutedForeground),
            ),
            const SizedBox(height: 12),
            // Web's amber "Penting" block. Choosing pickup and then walking
            // the parcel to a counter is the mistake this prevents, and it
            // costs the seller the shipment — worth saying before the choice,
            // not after.
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.appSemantic.condMp.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: context.appSemantic.condMp.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.circleAlert,
                    size: 14,
                    color: context.appSemantic.condMp,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: AppTypography.caption(
                          context.appColors.onSurface,
                        ),
                        children: [
                          TextSpan(
                            text: 'Penting: ',
                            style: AppTypography.captionSemibold(
                              context.appColors.onSurface,
                            ),
                          ),
                          TextSpan(
                            text: _allowsManual
                                ? 'Jika memilih Pickup oleh kurir, paket tidak '
                                      'bisa diantar sendiri ke counter kurir. '
                                      'Tunggu kurir datang menjemput. Jika '
                                      'ingin drop off sendiri, gunakan opsi '
                                      'kirim sendiri dan pesan resi langsung '
                                      'di counter kurir secara offline.'
                                : 'Kurir instan hanya menjemput ke lokasi kamu '
                                      'dan tidak bisa memakai resi manual. '
                                      'Pesan kurir dari halaman ini, lalu '
                                      'siapkan paket sebelum driver datang.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_allowsPickup)
              _ChoiceCard(
                icon: LucideIcons.truck,
                label: 'Pickup oleh kurir',
                hint: 'Kurir datang ambil paket di lokasi kamu.',
                selected: _choice == _DispatchChoice.pickup,
                onTap: _submitting
                    ? null
                    : () => setState(() => _choice = _DispatchChoice.pickup),
              ),
            if (_allowsManual)
              _ChoiceCard(
                icon: LucideIcons.fileText,
                label: 'Kirim sendiri (input resi manual)',
                hint: 'Saya sudah punya nomor resi dari kurir.',
                selected: _choice == _DispatchChoice.manual,
                onTap: _submitting
                    ? null
                    : () => setState(() => _choice = _DispatchChoice.manual),
              ),
            const SizedBox(height: 14),
            if (_choice == _DispatchChoice.pickup) ...[
              TextField(
                controller: _itemName,
                enabled: !_submitting,
                maxLength: 150,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nama barang',
                  hintText: 'Mainan, puzzle, aksesoris, dll.',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 6),
              _Warning(
                text:
                    'Hindari menyebut nama yang mengandung unsur kartu atau '
                    'Pokémon agar mengurangi risiko kurir mencuri paket.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                enabled: !_submitting,
                maxLength: 250,
                decoration: const InputDecoration(
                  labelText: 'Catatan untuk kurir',
                  hintText: 'Contoh: Mohon dijaga, jangan dibanting',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Opsional. Kurir menjemput sesuai jadwal mereka (1-2 hari '
                'kerja) — pastikan paket sudah siap.',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ] else ...[
              ref
                  .watch(manualCouriersProvider)
                  .when(
                    data: (couriers) => DropdownButtonFormField<String>(
                      initialValue: _courierCode,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Kurir'),
                      hint: const Text('Pilih kurir'),
                      items: [
                        for (final courier in couriers)
                          DropdownMenuItem(
                            value: courier.code,
                            child: Text(courier.name),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _courierCode = value),
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                    error: (_, __) => Text(
                      'Daftar kurir gagal dimuat. Coba lagi sebentar.',
                      style: AppTypography.caption(colors.error),
                    ),
                  ),
              const SizedBox(height: 12),
              TextField(
                controller: _resi,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                  LengthLimitingTextInputFormatter(50),
                ],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nomor resi',
                  hintText: 'mis. JX1234567890',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Huruf, angka, dan tanda strip saja.',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTypography.caption(colors.error)),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: _submitting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onPrimary,
                      ),
                    )
                  : Text(
                      _choice == _DispatchChoice.manual
                          ? 'Simpan resi'
                          : 'Konfirmasi pengiriman',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border.all(
              color: selected ? colors.primary : context.borderColor,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? colors.primary : context.mutedForeground,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.bodySmSemibold(colors.onSurface),
                    ),
                    Text(
                      hint,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(LucideIcons.check, size: 16, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final gold = context.appSemantic.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.triangleAlert, size: 14, color: gold),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppTypography.caption(gold))),
        ],
      ),
    );
  }
}
