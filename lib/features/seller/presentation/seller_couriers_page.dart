import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/coretan_kit.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../repository/models/store_profile.dart';
import '../repository/store_profile_repository.dart';
import '../usecase/store_profile_notifier.dart';
import 'widgets/courier_service_picker.dart';

/// Ports `COURIER_BUCKET_ORDER` / `COURIER_BUCKET_LABEL`.
enum CourierBucket {
  instant('instant', 'Instan (1–3 jam)'),
  sameDay('same_day', 'Same Day (4–12 jam)'),
  overnight('overnight', 'Overnight (besok sampai)'),
  reguler('reguler', 'Reguler');

  const CourierBucket(this.raw, this.label);

  final String raw;
  final String label;

  static CourierBucket fromRaw(String raw) => switch (raw) {
    'instant' => CourierBucket.instant,
    'same_day' => CourierBucket.sameDay,
    'overnight' => CourierBucket.overnight,
    _ => CourierBucket.reguler,
  };
}

/// One row of `/api/biteship/services`.
class CourierService {
  const CourierService({
    required this.id,
    required this.courierName,
    required this.serviceName,
    required this.duration,
  });

  factory CourierService.fromJson(Map<String, dynamic> json) {
    final range = json['durationRange'] as String? ?? '';
    final unit = json['durationUnit'] as String? ?? '';
    return CourierService(
      id: json['id'] as String? ?? '',
      courierName:
          json['courierName'] as String? ??
          json['courierCode'] as String? ??
          '',
      serviceName:
          json['serviceName'] as String? ??
          json['serviceCode'] as String? ??
          '',
      duration: courierDurationLabel(range, unit),
    );
  }

  final String id;
  final String courierName;
  final String serviceName;

  /// How long it takes, in Indonesian: "1–3 jam", "2–3 hari", "besok".
  final String duration;
}

/// Biteship's `durationRange` and `durationUnit` ("1 - 3", "hours") as a
/// seller reads them: "1–3 jam". A single day is "besok" — next-day is
/// what it means, and "1 hari" reads as a day's wait.
String courierDurationLabel(String range, String unit) {
  final span = range.trim().replaceAll(RegExp(r'\s*-\s*'), '–');
  if (span.isEmpty) return '';
  final u = unit.trim().toLowerCase();
  final days = u.startsWith('day');
  if (days && (span == '1' || span == '1–1')) return 'besok';
  final word = days
      ? 'hari'
      : u.startsWith('hour')
      ? 'jam'
      : u;
  return [span, word].where((p) => p.isNotEmpty).join(' ');
}

/// The courier catalogue behind `/api/biteship/services`.
///
/// The one part of Toko that can't come straight from Postgres: the list is
/// Biteship's, and the key that reads it is server-side. The page degrades to
/// an explanation rather than an empty checklist when that route can't be
/// reached — the seller's saved choices are still shown either way.
final courierServicesProvider =
    FutureProvider<Map<CourierBucket, List<CourierService>>>((ref) async {
      final response = await ref
          .read(pokepediaApiProvider)
          .get('/api/biteship/services');
      final groups = response['groups'];
      if (groups is! Map) return const {};

      final out = <CourierBucket, List<CourierService>>{};
      for (final entry in groups.entries) {
        final bucket = CourierBucket.fromRaw(entry.key as String);
        final items = entry.value;
        if (items is! List) continue;
        out[bucket] = items
            .whereType<Map<String, dynamic>>()
            .map(CourierService.fromJson)
            .where((s) => s.id.isNotEmpty)
            .toList();
      }
      return out;
    });

/// Ports `/seller/couriers`.
class SellerCouriersPage extends ConsumerStatefulWidget {
  const SellerCouriersPage({super.key});

  @override
  ConsumerState<SellerCouriersPage> createState() => _SellerCouriersPageState();
}

class _SellerCouriersPageState extends ConsumerState<SellerCouriersPage> {
  Set<String>? _selected;
  bool _saving = false;

  /// Seeded from the profile once. An empty stored list means the seller has
  /// never chosen, which web reads as "accept everything" — so the boxes
  /// start ticked rather than blank.
  void _seed(StoreProfile profile, Iterable<String> allIds) {
    if (_selected != null) return;
    _selected = profile.acceptedCourierServices.isEmpty
        ? allIds.toSet()
        : profile.acceptedCourierServices.toSet();
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) return;

    setState(() => _saving = true);
    final error = await ref
        .read(storeProfileRepositoryProvider)
        .saveCouriers(selected.toList());
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(error ?? 'Kurir tersimpan'), persist: false),
      );
    if (error == null) ref.invalidate(storeProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final profileAsync = ref.watch(storeProfileProvider);
    final servicesAsync = ref.watch(courierServicesProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: profileAsync.when(
          loading: () => const PikachuLoader(),
          error: (_, __) => EmptyState(
            icon: LucideIcons.truck,
            title: 'Gagal memuat pengaturan kurir',
            action: OutlinedButton(
              onPressed: () => ref.invalidate(storeProfileProvider),
              child: const Text('Coba lagi'),
            ),
          ),
          data: (profile) {
            if (profile == null) {
              return const Center(
                child: EmptyState(
                  icon: LucideIcons.store,
                  title: 'Belum punya toko',
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text('Kurir', style: AppTypography.h1(colors.onSurface)),
                const SizedBox(height: 4),
                Text(
                  'Centang layanan yang kamu terima untuk pengiriman '
                  'pesanan.',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
                const SizedBox(height: 16),
                servicesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: PikachuLoader(),
                  ),
                  error: (error, _) => _Unavailable(
                    profile: profile,
                    message: error is ApiUnreachableException
                        ? error.message
                        : 'Daftar layanan kurir sedang tidak bisa dimuat.',
                    onRetry: () => ref.invalidate(courierServicesProvider),
                  ),
                  data: (groups) => _picker(profile, groups),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _picker(
    StoreProfile profile,
    Map<CourierBucket, List<CourierService>> groups,
  ) {
    final allIds = groups.values.expand((s) => s).map((s) => s.id).toList();
    if (allIds.isEmpty) {
      return _Unavailable(
        profile: profile,
        message: 'Belum ada layanan kurir yang tersedia.',
        onRetry: () => ref.invalidate(courierServicesProvider),
      );
    }
    _seed(profile, allIds);
    final selected = _selected!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CourierServicePicker(
          catalog: groups,
          selected: selected,
          enabled: !_saving,
          onChanged: (next) => setState(() => _selected = next),
        ),
        const SizedBox(height: 4),
        // The server refuses an empty list too, so the button says why
        // instead of posting a request that will bounce.
        if (selected.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Pilih minimal 1 layanan kurir.',
              style: AppTypography.hand(context.appColors.error),
            ),
          ),
        CoretanButton(
          label: 'Simpan',
          trailing: null,
          busy: _saving,
          onPressed: selected.isEmpty ? null : _save,
        ),
      ],
    );
  }
}

/// What the seller sees when the catalogue can't be fetched. Their saved
/// choices are still worth showing — that's the setting that's in force.
class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.profile,
    required this.message,
    required this.onRetry,
  });

  final StoreProfile profile;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final saved = profile.acceptedCourierServices;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.cloudOff, size: 18, color: colors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: AppTypography.bodySm(colors.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            saved.isEmpty
                ? 'Saat ini tokomu menerima semua layanan kurir.'
                : 'Saat ini tokomu menerima ${saved.length} layanan kurir.',
            style: AppTypography.caption(context.mutedForeground),
          ),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}
