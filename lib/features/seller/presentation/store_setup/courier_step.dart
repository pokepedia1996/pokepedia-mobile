import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/widgets/coretan_kit.dart';
import '../../../../shared/widgets/pikachu_loader.dart';
import '../../../../shared/widgets/scribble_drawing.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../../usecase/store_setup.dart';
import '../seller_couriers_page.dart';
import '../widgets/courier_service_picker.dart';
import 'store_setup_parts.dart';

/// Opens the store with [serviceIds] from either courier screen: the
/// button spins while it goes, and an error stays on the screen.
mixin _Opens<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool opening = false;
  String? openError;

  StoreSetupDraft get draft;
  ValueChanged<List<String>> get onOpened;

  /// Told while the store is opening, so the page's back button holds.
  ValueChanged<bool> get onBusy;

  Future<void> open(List<String> serviceIds) async {
    setState(() {
      opening = true;
      openError = null;
    });
    onBusy(true);
    final result = await ref
        .read(storeSetupControllerProvider)
        .open(draft, serviceIds);
    if (!mounted) return;
    onBusy(false);
    setState(() => opening = false);
    if (result.error != null) {
      setState(() => openError = result.error);
      return;
    }
    onOpened(result.warnings);
  }

  Widget? errorLine(DesignPalette palette) => openError == null
      ? null
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            openError!,
            textAlign: TextAlign.center,
            style: setupText(15, palette.error, FontWeight.w600),
          ),
        );
}

/// Step 4: how the cards travel — the recommended couriers in one tap,
/// which opens the store, or "Atur manual", which goes on to pick them one
/// service at a time.
class CourierStep extends ConsumerStatefulWidget {
  const CourierStep({
    super.key,
    required this.draft,
    required this.onManual,
    required this.onOpened,
    required this.onBusy,
  });

  final StoreSetupDraft draft;

  /// "Pilih layanan kurir": on to the list.
  final VoidCallback onManual;

  /// The store is open; with what did not take after it.
  final ValueChanged<List<String>> onOpened;
  final ValueChanged<bool> onBusy;

  @override
  ConsumerState<CourierStep> createState() => _CourierStepState();
}

class _CourierStepState extends ConsumerState<CourierStep>
    with _Opens<CourierStep> {
  @override
  StoreSetupDraft get draft => widget.draft;
  @override
  ValueChanged<List<String>> get onOpened => widget.onOpened;
  @override
  ValueChanged<bool> get onBusy => widget.onBusy;

  /// Choosing manual starts from the recommendation, ticked, so the list
  /// is a change to it rather than an empty page.
  void _chooseManual(Map<CourierBucket, List<CourierService>> catalog) {
    setState(() {
      if (draft.manualServiceIds.isEmpty) {
        draft.manualServiceIds.addAll(
          recommendedServices(catalog).map((s) => s.id),
        );
      }
      draft.manualCouriers = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final async = ref.watch(courierServicesProvider);
    final catalog = async.valueOrNull;
    final manual = draft.manualCouriers;
    final ready = catalog != null && catalog.isNotEmpty;

    return SetupStepLayout(
      content: [
        const SetupIntro(
          eyebrow: 'langkah 4 dari 4',
          first: 'Pilih cara',
          second: 'kirim kartumu.',
          sub: 'Pilih yang tersedia di lokasimu. Bisa diubah kapan saja.',
        ),
        if (catalog == null && async.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: PikachuLoader(),
          )
        else if (!ready)
          _Unavailable(onRetry: () => ref.invalidate(courierServicesProvider))
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RecommendedCard(
                catalog: catalog,
                selected: !manual,
                onTap: () => setState(() => draft.manualCouriers = false),
              ),
              const SizedBox(height: 14),
              _ManualCard(
                catalog: catalog,
                picked: draft.manualServiceIds.length,
                selected: manual,
                onTap: () => _chooseManual(catalog),
              ),
            ],
          ),
      ],
      footer: [
        ?errorLine(palette),
        if (manual)
          CoretanButton(
            label: 'Pilih layanan kurir',
            onPressed: ready ? widget.onManual : null,
          )
        else
          CoretanButton(
            label: 'Buka toko',
            leading: LucideIcons.store,
            trailing: null,
            busy: opening,
            onPressed: ready
                ? () =>
                      open([for (final s in recommendedServices(catalog)) s.id])
                : null,
          ),
      ],
    );
  }
}

/// Step 4, by hand: every service the catalog has, a card per speed,
/// ticked to start with the recommendation's.
class ManualCourierStep extends ConsumerStatefulWidget {
  const ManualCourierStep({
    super.key,
    required this.draft,
    required this.onOpened,
    required this.onBusy,
  });

  final StoreSetupDraft draft;
  final ValueChanged<List<String>> onOpened;
  final ValueChanged<bool> onBusy;

  @override
  ConsumerState<ManualCourierStep> createState() => _ManualCourierStepState();
}

class _ManualCourierStepState extends ConsumerState<ManualCourierStep>
    with _Opens<ManualCourierStep> {
  @override
  StoreSetupDraft get draft => widget.draft;
  @override
  ValueChanged<List<String>> get onOpened => widget.onOpened;
  @override
  ValueChanged<bool> get onBusy => widget.onBusy;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final catalog = ref.watch(courierServicesProvider).valueOrNull ?? const {};
    final picked = draft.manualServiceIds;

    return SetupStepLayout(
      content: [
        const SetupIntro(
          eyebrow: 'langkah 4 dari 4 · atur manual',
          first: 'Pilih layanan',
          second: 'kurir kamu.',
          sub:
              'Centang layanan yang kamu terima. Sudah kami isi dari kurir '
              'rekomendasi.',
        ),
        CourierServicePicker(
          catalog: catalog,
          selected: picked,
          enabled: !opening,
          tickIn: true,
          onChanged: (next) => setState(() {
            picked
              ..clear()
              ..addAll(next);
          }),
        ),
      ],
      footer: [
        ?errorLine(palette),
        if (picked.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Pilih minimal 1 layanan kurir.',
              textAlign: TextAlign.center,
              style: AppTypography.hand(palette.error),
            ),
          ),
        CoretanButton(
          label: 'Buka toko · ${picked.length} layanan',
          leading: LucideIcons.store,
          trailing: null,
          busy: opening,
          onPressed: picked.isEmpty ? null : () => open(picked.toList()),
        ),
      ],
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({
    required this.catalog,
    required this.selected,
    required this.onTap,
  });

  final Map<CourierBucket, List<CourierService>> catalog;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final labels = recommendedCourierLabels(catalog);
    return _Option(
      selected: selected,
      onTap: onTap,
      drawing: 'toko_truk',
      title: 'Rekomendasi',
      badge: const CoretanPill(
        label: 'Populer',
        background: Color(0xFFF4B63F),
        foreground: Color(0xFF1C1413),
      ),
      description:
          '${labels.length} kurir terpercaya, dari reguler sampai instan',
      below: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < labels.length; i++)
            CoretanReveal(
              // The chips pop in one after another.
              delay: Duration(milliseconds: 500 + 60 * i),
              duration: const Duration(milliseconds: 320),
              rise: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.codeBg,
                  border: Border.all(color: AppColors.codeLine),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  labels[i],
                  style: setupText(15, palette.ink, FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ManualCard extends StatelessWidget {
  const _ManualCard({
    required this.catalog,
    required this.picked,
    required this.selected,
    required this.onTap,
  });

  final Map<CourierBucket, List<CourierService>> catalog;
  final int picked;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final total = catalog.values.fold<int>(0, (sum, list) => sum + list.length);
    return _Option(
      selected: selected,
      onTap: onTap,
      drawing: 'toko_atur',
      title: 'Atur manual',
      description: 'Pilih sendiri dari $total layanan kurir',
      note: selected
          ? Text(
              '$picked layanan dipilih · ubah di langkah berikut',
              style: AppTypography.hand(palette.brand, size: 17),
            )
          : null,
    );
  }
}

/// A pickable sticker card: a drawn icon, what it is, and a pen ring that
/// fills when picked.
class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.onTap,
    required this.drawing,
    required this.title,
    required this.description,
    this.badge,
    this.note,
    this.below,
  });

  final bool selected;
  final VoidCallback onTap;
  final String drawing;
  final String title;
  final String description;
  final Widget? badge;
  final Widget? note;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: CoretanCard(
        selected: selected,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ScribbleDrawing(
                  drawing: drawing,
                  size: 52,
                  stepMs: 40,
                  delay: const Duration(milliseconds: 300),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: setupText(
                                19,
                                palette.ink,
                                FontWeight.w800,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            badge!,
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: setupText(15.5, palette.muted, FontWeight.w400),
                      ),
                      if (note != null) ...[const SizedBox(height: 4), note!],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                CoretanRadio(selected: selected),
              ],
            ),
            if (below != null) ...[const SizedBox(height: 12), below!],
          ],
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    return CoretanCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Daftar kurir belum bisa dimuat.',
            textAlign: TextAlign.center,
            style: setupText(16, palette.ink, FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
