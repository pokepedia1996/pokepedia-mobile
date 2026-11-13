import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/utils/id_phone.dart';
import '../../../../shared/widgets/coretan_kit.dart';
import '../../../../shared/widgets/scribble_drawing.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../../usecase/store_setup.dart';
import '../seller_couriers_page.dart';
import '../widgets/add_listing_sheet.dart';
import 'store_setup_parts.dart';

/// The store is open: the stall with its BUKA! sign, confetti, the store as
/// buyers will see it, what was set up — ticked off one by one — and the
/// way to a first listing.
class StoreReadyStep extends ConsumerWidget {
  const StoreReadyStep({
    super.key,
    required this.draft,
    required this.warnings,
    required this.onClose,
  });

  final StoreSetupDraft draft;

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
    final palette = DesignPalette.of(context);
    final catalog = ref.watch(courierServicesProvider).valueOrNull;
    final phone = draft.phone;
    final (courierTitle, courierLine) = _couriers(catalog);

    final rows = [
      draft.profileSet
          ? ('Profil toko diatur', 'Nama, foto & banner tersimpan')
          : (
              'Profil toko pakai default',
              'Nama toko: ${draft.storeName} · bisa diubah nanti',
            ),
      ('Nomor HP terverifikasi', phone == null ? '' : maskIdPhone(phone)),
      (
        'Alamat pickup tersimpan',
        [
          draft.street,
          draft.district?.name,
          draft.city?.name,
        ].whereType<String>().where((s) => s.isNotEmpty).join(', '),
      ),
      (courierTitle, courierLine),
    ];

    return Stack(
      children: [
        SetupStepLayout(
          content: [
            // No step header above this one: the close button has the top
            // of the page to itself.
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: CoretanIconButton(
                  icon: LucideIcons.x,
                  label: 'Tutup',
                  onPressed: onClose,
                ),
              ),
            ),
            SizedBox(
              height: setupSize(250),
              child: const ScribbleDrawing(drawing: 'toko_lapakBuka'),
            ),
            const SizedBox(height: 12),
            const CoretanEyebrow('selamat!', size: 21, center: true),
            const SizedBox(height: 8),
            SetupHeadline(
              first: 'Tokomu',
              second: 'sudah buka!',
              palette: palette,
              size: 40,
              lineHeight: 42,
              center: true,
            ),
            const SizedBox(height: 10),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  'Sekarang kartumu bisa dibeli kolektor di seluruh '
                  'Indonesia.',
                  textAlign: TextAlign.center,
                  style: setupText(18, palette.muted, FontWeight.w400, 1.4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _StoreCard(draft: draft),
            const SizedBox(height: 14),
            SetupCard(
              rows: [
                for (var i = 0; i < rows.length; i++)
                  SetupChecklistRow(
                    icon: _DoneTick(index: i),
                    title: rows[i].$1,
                    subtitle: rows[i].$2,
                    meta: _DoneNote(index: i),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.circleAlert,
                          size: 15,
                          color: palette.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$warning Atur lagi dari Pengaturan Toko.',
                            style: setupText(14, palette.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          footer: [
            CoretanButton(
              label: 'Jual kartu pertama',
              leading: LucideIcons.plus,
              trailing: null,
              onPressed: () => _sellFirst(context),
            ),
          ],
        ),
        const Positioned.fill(child: CoretanConfetti()),
      ],
    );
  }

  /// The courier row: "6 kurir aktif" and their names for the
  /// recommendation; by hand, the services counted and the first five
  /// couriers named.
  (String, String) _couriers(
    Map<CourierBucket, List<CourierService>>? catalog,
  ) {
    if (catalog == null) return ('Kurir aktif', '');
    if (!draft.manualCouriers) {
      final labels = recommendedCourierLabels(catalog);
      return ('${labels.length} kurir aktif', labels.join(', '));
    }
    final names = <String>{};
    for (final services in catalog.values) {
      for (final service in services) {
        if (draft.manualServiceIds.contains(service.id)) {
          names.add(service.courierName);
        }
      }
    }
    final shown = names.take(5).join(', ');
    final rest = names.length - 5;
    return (
      '${draft.manualServiceIds.length} layanan kurir aktif',
      rest > 0 ? '$shown +$rest lainnya' : shown,
    );
  }
}

/// When the [index]th row of the summary is ticked: from 1 s after the
/// screen arrives, a quarter second apart.
Duration _tickAt(int index) => Duration(milliseconds: 1000 + 260 * index);

/// A red pen tick, drawn in on its turn.
class _DoneTick extends StatelessWidget {
  const _DoneTick({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ScribbleDrawing(
      drawing: 'icon_chkOn',
      size: 32,
      stepMs: 40,
      delay: _tickAt(index),
      idle: false,
    );
  }
}

/// "selesai", in green hand, a moment after its row's tick.
class _DoneNote extends StatefulWidget {
  const _DoneNote({required this.index});

  final int index;

  @override
  State<_DoneNote> createState() => _DoneNoteState();
}

class _DoneNoteState extends State<_DoneNote> {
  bool _shown = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown || _timer != null) return;
    if (coretanReduceMotion(context)) {
      _shown = true;
      return;
    }
    _timer = Timer(
      _tickAt(widget.index) + const Duration(milliseconds: 180),
      () {
        if (mounted) setState(() => _shown = true);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      child: Text(
        'selesai',
        style: AppTypography.hand(palette.successText, size: 19),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  const _StoreCard({required this.draft});

  final StoreSetupDraft draft;

  /// "Binder Mulyana" → "BM".
  String get _initials {
    final words = draft.storeName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final banner = draft.banner;
    final logo = draft.logo;
    return CoretanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: banner != null
                ? Image.memory(banner, fit: BoxFit.cover)
                : const CoretanBackground(
                    tile: coretanTileRed,
                    color: Color(0xFFAC403A),
                    child: SizedBox.expand(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 52,
                  child: logo != null
                      ? ClipOval(child: Image.memory(logo, fit: BoxFit.cover))
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            const ScribbleDrawing(
                              drawing: 'toko_avBM',
                              size: 52,
                              idle: false,
                            ),
                            Text(
                              _initials,
                              style: setupText(
                                19,
                                AppColors.black,
                                FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.storeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: setupHeading(21, palette.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'oleh @${draft.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: setupText(15, palette.muted),
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
