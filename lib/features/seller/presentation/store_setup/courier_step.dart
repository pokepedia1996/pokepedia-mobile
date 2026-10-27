import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/design_palette.dart';
import '../../../../shared/widgets/pikachu_loader.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../../usecase/store_setup.dart';
import '../seller_couriers_page.dart';
import 'store_setup_parts.dart';

/// Step 4: how the cards travel — the recommended couriers in one tap, or
/// any of the catalog's services by hand. "Buka toko" opens the store.
class CourierStep extends ConsumerStatefulWidget {
  const CourierStep({
    super.key,
    required this.draft,
    required this.palette,
    required this.onBack,
    required this.onOpened,
  });

  final StoreSetupDraft draft;
  final DesignPalette palette;
  final VoidCallback onBack;

  /// The store is open; with what did not take after it.
  final ValueChanged<List<String>> onOpened;

  @override
  ConsumerState<CourierStep> createState() => _CourierStepState();
}

class _CourierStepState extends ConsumerState<CourierStep> {
  bool _opening = false;
  String? _error;

  StoreSetupDraft get _draft => widget.draft;

  List<String> _serviceIds(Map<CourierBucket, List<CourierService>> catalog) =>
      _draft.manualCouriers
      ? _draft.manualServiceIds.toList()
      : [for (final s in recommendedServices(catalog)) s.id];

  Future<void> _open(List<String> serviceIds) async {
    setState(() {
      _opening = true;
      _error = null;
    });
    final result = await ref
        .read(storeSetupControllerProvider)
        .open(_draft, serviceIds);
    if (!mounted) return;
    setState(() => _opening = false);
    if (result.error != null) {
      setState(() => _error = result.error);
      return;
    }
    widget.onOpened(result.warnings);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final async = ref.watch(courierServicesProvider);
    final catalog = async.valueOrNull;
    final serviceIds = catalog == null
        ? const <String>[]
        : _serviceIds(catalog);

    return SetupStepLayout(
      palette: palette,
      content: [
        SetupProgress(
          step: 3,
          total: 4,
          palette: palette,
          onBack: _opening ? null : widget.onBack,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(0, setupSize(28), 0, setupSize(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SetupHeadline(
                first: 'Pilih cara',
                second: 'kirim kartumu.',
                palette: palette,
                size: 38,
                lineHeight: 42,
              ),
              const SizedBox(height: 12),
              Text(
                'Pilih yang tersedia di lokasimu. Bisa diubah kapan saja.',
                style: setupText(16, palette.muted),
              ),
            ],
          ),
        ),
        if (catalog == null && async.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: PikachuLoader(),
          )
        else if (catalog == null || catalog.isEmpty)
          _Unavailable(
            palette: palette,
            onRetry: () => ref.invalidate(courierServicesProvider),
          )
        else ...[
          _RecommendedCard(
            catalog: catalog,
            selected: !_draft.manualCouriers,
            palette: palette,
            onTap: () => setState(() => _draft.manualCouriers = false),
          ),
          const SizedBox(height: 10),
          _ManualCard(
            catalog: catalog,
            draft: _draft,
            selected: _draft.manualCouriers,
            palette: palette,
            onTap: () => setState(() {
              // Opening the list starts from the recommendation, ticked,
              // so "manual" is a change to it rather than an empty page.
              if (!_draft.manualCouriers && _draft.manualServiceIds.isEmpty) {
                _draft.manualServiceIds.addAll(
                  recommendedServices(catalog).map((s) => s.id),
                );
              }
              _draft.manualCouriers = true;
            }),
            onToggle: (id) => setState(() {
              if (!_draft.manualServiceIds.remove(id)) {
                _draft.manualServiceIds.add(id);
              }
            }),
          ),
        ],
      ],
      footer: [
        if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: setupText(13, palette.error, FontWeight.w500),
          ),
          const SizedBox(height: 12),
        ],
        SetupPrimaryButton(
          label: 'Buka toko',
          icon: LucideIcons.store,
          palette: palette,
          background: palette.successText,
          busy: _opening,
          onPressed: serviceIds.isEmpty || _opening
              ? null
              : () => _open(serviceIds),
        ),
      ],
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({
    required this.catalog,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final Map<CourierBucket, List<CourierService>> catalog;
  final bool selected;
  final DesignPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final labels = recommendedCourierLabels(catalog);
    return _OptionShell(
      selected: selected,
      palette: palette,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OptionRow(
            icon: LucideIcons.sparkles,
            title: 'Rekomendasi',
            badge: 'Populer',
            description:
                '${labels.length} kurir terpercaya, dari reguler sampai instan',
            selected: selected,
            palette: palette,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final label in labels)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: palette.background,
                      border: Border.all(color: palette.border),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      style: setupText(12, palette.ink, FontWeight.w600),
                    ),
                  ),
              ],
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
    required this.draft,
    required this.selected,
    required this.palette,
    required this.onTap,
    required this.onToggle,
  });

  final Map<CourierBucket, List<CourierService>> catalog;
  final StoreSetupDraft draft;
  final bool selected;
  final DesignPalette palette;
  final VoidCallback onTap;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final total = catalog.values.fold<int>(0, (sum, list) => sum + list.length);
    return _OptionShell(
      selected: selected,
      palette: palette,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OptionRow(
            icon: LucideIcons.slidersHorizontal,
            title: 'Atur manual',
            description: selected
                ? '${draft.manualServiceIds.length} dari $total layanan dipilih'
                : 'Pilih sendiri dari $total layanan kurir',
            selected: selected,
            palette: palette,
          ),
          if (selected)
            for (final bucket in CourierBucket.values)
              if (catalog[bucket]?.isNotEmpty ?? false) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Text(
                    bucket.label,
                    style: setupText(12, palette.muted, FontWeight.w700),
                  ),
                ),
                for (final service in catalog[bucket]!)
                  CheckboxListTile(
                    value: draft.manualServiceIds.contains(service.id),
                    onChanged: (_) => onToggle(service.id),
                    dense: true,
                    activeColor: palette.brand,
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: Text(
                      '${service.courierName} ${service.serviceName}',
                      style: setupText(14, palette.ink, FontWeight.w600),
                    ),
                    subtitle: service.duration.isEmpty
                        ? null
                        : Text(
                            service.duration,
                            style: setupText(12, palette.muted),
                          ),
                  ),
                const SizedBox(height: 8),
              ],
        ],
      ),
    );
  }
}

/// A selectable card: the brand outline when picked.
class _OptionShell extends StatelessWidget {
  const _OptionShell({
    required this.selected,
    required this.palette,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final DesignPalette palette;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? palette.brand : palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: child),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.palette,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final DesignPalette palette;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? palette.brandSoft : palette.chip,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 22,
              color: selected ? palette.brand : palette.ink,
            ),
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
                        style: setupText(16, palette.ink, FontWeight.w600),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.brand,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge!,
                          style: setupText(
                            11,
                            palette.ctaForeground,
                            FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(description, style: setupText(13, palette.muted)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SetupCheckIndicator(selected: selected, palette: palette),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.palette, required this.onRetry});

  final DesignPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            'Daftar kurir belum bisa dimuat.',
            textAlign: TextAlign.center,
            style: setupText(14, palette.ink, FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
