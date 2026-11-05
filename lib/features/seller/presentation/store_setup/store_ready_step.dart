import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/utils/id_phone.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../../usecase/store_setup.dart';
import '../seller_couriers_page.dart';
import '../widgets/add_listing_sheet.dart';
import 'store_setup_parts.dart';

/// The store is open: what it looks like, what was set up, and the way to
/// a first listing.
class StoreReadyStep extends ConsumerWidget {
  const StoreReadyStep({
    super.key,
    required this.draft,
    required this.palette,
    required this.warnings,
    required this.onClose,
  });

  final StoreSetupDraft draft;
  final DesignPalette palette;

  /// What opening left undone — a picture that didn't upload — for the
  /// seller to redo from the store's settings.
  final List<String> warnings;
  final VoidCallback onClose;

  /// "Jual kartu pertama": the same picker "Tambah listing" opens, and then
  /// the drafts it made.
  Future<void> _sellFirst(BuildContext context) async {
    final added = await showAddListingSheet(context);
    if (!context.mounted) return;
    if (added == true) {
      context.go('${Routes.sellerProducts}?tab=draft');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(courierServicesProvider).valueOrNull;
    final couriers = _courierNames(catalog);
    final phone = draft.phone;

    return SetupStepLayout(
      palette: palette,
      content: [
        Align(
          alignment: Alignment.centerRight,
          child: SetupCircleButton(
            icon: LucideIcons.x,
            label: 'Tutup',
            onPressed: onClose,
            palette: palette,
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: setupSize(88),
            height: setupSize(88),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.successSoft.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Container(
              width: setupSize(64),
              height: setupSize(64),
              decoration: BoxDecoration(
                color: palette.successSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.check,
                size: 30,
                color: palette.successText,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SetupHeadline(
          first: 'Tokomu',
          second: 'sudah buka!',
          palette: palette,
          size: 40,
          lineHeight: 44,
          center: true,
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              'Sekarang kartumu bisa dibeli kolektor di seluruh Indonesia.',
              textAlign: TextAlign.center,
              style: setupText(16, palette.muted),
            ),
          ),
        ),
        const SizedBox(height: 20),
        _StoreCard(draft: draft, palette: palette),
        const SizedBox(height: 12),
        SetupCard(
          palette: palette,
          rows: [
            SetupChecklistRow(
              icon: LucideIcons.store,
              title: draft.profileSet ? 'Profil toko diatur' : 'Profil toko',
              subtitle: draft.profileSet
                  ? 'Nama, foto & banner tersimpan'
                  : 'Pakai username · atur di Pengaturan Toko',
              meta: draft.profileSet ? 'Selesai' : 'Nanti',
              state: draft.profileSet
                  ? SetupRowState.done
                  : SetupRowState.optional,
              palette: palette,
            ),
            SetupChecklistRow(
              icon: LucideIcons.smartphone,
              title: 'Nomor HP terverifikasi',
              subtitle: phone == null ? '' : maskIdPhone(phone),
              meta: 'Selesai',
              state: SetupRowState.done,
              palette: palette,
            ),
            SetupChecklistRow(
              icon: LucideIcons.mapPin,
              title: 'Alamat pickup tersimpan',
              subtitle: [
                draft.street,
                draft.district?.name,
                draft.city?.name,
              ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
              meta: 'Selesai',
              state: SetupRowState.done,
              palette: palette,
            ),
            SetupChecklistRow(
              icon: LucideIcons.truck,
              title: couriers.isEmpty
                  ? 'Kurir aktif'
                  : '${couriers.length} kurir aktif',
              subtitle: couriers.join(', '),
              meta: 'Selesai',
              state: SetupRowState.done,
              palette: palette,
            ),
          ],
        ),
        for (final warning in warnings) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(LucideIcons.circleAlert, size: 14, color: palette.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$warning Atur lagi dari Pengaturan Toko.',
                  style: setupText(12, palette.muted),
                ),
              ),
            ],
          ),
        ],
      ],
      footer: [
        SetupPrimaryButton(
          label: 'Jual kartu pertama',
          icon: LucideIcons.plus,
          palette: palette,
          onPressed: () => _sellFirst(context),
        ),
      ],
    );
  }

  /// The couriers the store ships with, by name, in the catalog's order.
  List<String> _courierNames(
    Map<CourierBucket, List<CourierService>>? catalog,
  ) {
    if (catalog == null) return const [];
    if (!draft.manualCouriers) return recommendedCourierLabels(catalog);
    final names = <String>{};
    for (final services in catalog.values) {
      for (final service in services) {
        if (draft.manualServiceIds.contains(service.id)) {
          names.add(service.courierName);
        }
      }
    }
    return names.toList();
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.draft, required this.palette});

  final StoreSetupDraft draft;
  final DesignPalette palette;

  /// "Binder Mulyana" → "BM".
  String get _initials {
    final words = draft.storeName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
    return letters;
  }

  @override
  Widget build(BuildContext context) {
    final banner = draft.banner;
    final logo = draft.logo;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: banner != null
                ? Image.memory(banner, fit: BoxFit.cover)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [palette.brandSoft, const Color(0xFFFDF1D8)],
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: palette.brandSoft,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.surface, width: 3),
                  ),
                  child: logo != null
                      ? Image.memory(logo, fit: BoxFit.cover)
                      : Text(
                          _initials,
                          style: setupText(17, palette.brand, FontWeight.w700),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: setupText(16, palette.ink, FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.userRound,
                            size: 12,
                            color: palette.muted,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'oleh @${draft.username}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: setupText(13, palette.muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SetupPill(
                  label: 'Aktif',
                  background: palette.successSoft,
                  foreground: palette.successText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
