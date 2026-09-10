import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/utils/image_crop.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/map_picker_sheet.dart';
import '../../../shared/widgets/pikachu_loader.dart';
import '../../../shared/widgets/transparent_app_bar.dart';
import '../../account/repository/address_repository.dart';
import '../../account/repository/models/address_model.dart';
import '../../account/usecase/address_notifier.dart';
import '../repository/models/store_profile.dart';
import '../repository/store_profile_repository.dart';
import '../usecase/store_profile_notifier.dart';

/// Ports `/seller/settings` — web's Profil Toko, section for section, with
/// its copy.
///
/// Listing Unggulan is the one section still missing: it needs a picker over
/// the seller's own listings, which is a screen of its own.
class SellerStoreProfilePage extends ConsumerWidget {
  const SellerStoreProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final async = ref.watch(storeProfileProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const TransparentAppBar(),
      body: AppBarOverlayBody(
        child: async.when(
          loading: () => const PikachuLoader(),
          error: (_, __) => EmptyState(
            icon: LucideIcons.store,
            title: 'Gagal memuat profil penjual',
            action: OutlinedButton(
              onPressed: () => ref.invalidate(storeProfileProvider),
              child: const Text('Coba lagi'),
            ),
          ),
          data: (profile) {
            if (profile == null) {
              return const EmptyState(
                icon: LucideIcons.store,
                title: 'Belum punya toko',
                description:
                    'Buka toko dulu di pokepedia.id, lalu kelola dari sini.',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text('Profil Toko', style: AppTypography.h1(colors.onSurface)),
                const SizedBox(height: 2),
                Text(
                  'Atur identitas toko, alamat pengirim, dan kurir yang kamu '
                  'terima.',
                  style: AppTypography.bodySm(context.mutedForeground),
                ),
                const SizedBox(height: 16),
                _HeroSection(profile: profile),
                const SizedBox(height: 12),
                _AboutSection(profile: profile),
                const SizedBox(height: 12),
                _PickupSection(profile: profile),
                const SizedBox(height: 12),
                _VacationSection(profile: profile),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Web's card: a bordered box with a titled header strip above the body.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.children,
    this.description,
    this.padBody = true,
  });

  final String title;
  final String? description;
  final List<Widget> children;
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final description = this.description;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodySemibold(colors.onSurface),
                ),
                if (description != null)
                  Text(
                    description,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
              ],
            ),
          ),
          if (padBody)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}

/// Save/toast plumbing shared by the sections.
mixin _SavesSection<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool saving = false;

  Future<void> runSave(Future<String?> Function() action) async {
    setState(() => saving = true);
    final error = await action();
    if (!mounted) return;
    setState(() => saving = false);
    toast(error ?? 'Tersimpan');
    if (error == null) ref.invalidate(storeProfileProvider);
  }

  void toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message), persist: false));
  }
}

/// Ports `storefront-hero-section.tsx` — banner, logo and the store name,
/// each editable in place behind a pencil.
class _HeroSection extends ConsumerStatefulWidget {
  const _HeroSection({required this.profile});

  final StoreProfile profile;

  @override
  ConsumerState<_HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends ConsumerState<_HeroSection> with _SavesSection {
  StorefrontImageKind? _uploading;
  bool _editingName = false;
  late final _name = TextEditingController(
    text: widget.profile.storeName ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Ports web's `SLUG_REGEX`.
  static final _slugPattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$');

  /// Ports `slugify`.
  String _slugify(String value) => value
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
      .replaceAll(RegExp(r'[\s_-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  Future<void> _commitName() async {
    final trimmed = _name.text.trim();
    if (trimmed == (widget.profile.storeName ?? '')) {
      setState(() => _editingName = false);
      return;
    }
    if (trimmed.length < 3) {
      toast('Nama toko minimal 3 karakter');
      return;
    }
    // The URL follows the name, unless the name can't make a usable slug —
    // then whatever is already saved stands.
    final slug = _slugify(trimmed);
    final finalSlug = slug.length >= 3
        ? slug
        : (widget.profile.storeSlug ?? '');
    if (!_slugPattern.hasMatch(finalSlug)) {
      toast('Nama toko harus mengandung huruf atau angka');
      return;
    }

    await runSave(
      () => ref
          .read(storeProfileRepositoryProvider)
          .saveStorefront(
            storeName: trimmed,
            storeSlug: finalSlug,
            tagline: widget.profile.storeTagline,
          ),
    );
    if (mounted) setState(() => _editingName = false);
  }

  Future<void> _pickImage(StorefrontImageKind kind) async {
    if (_uploading != null) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Cropped to the exact preset below; this only keeps a 40MP original
      // out of memory on the way there.
      maxWidth: 3000,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = kind);
    final bytes = await File(picked.path).readAsBytes();
    // Centre-cropped to web's preset, so a store looks the same whichever
    // client set the image.
    final cropped = cropToAspect(
      bytes,
      targetWidth: kind.width,
      targetHeight: kind.height,
    );
    if (!mounted) return;
    if (cropped == null) {
      setState(() => _uploading = null);
      toast('Gagal memproses foto, coba foto lain');
      return;
    }

    final error = await ref
        .read(storeProfileRepositoryProvider)
        .uploadStorefrontImage(
          kind: kind,
          bytes: cropped,
          previousUrl: kind == StorefrontImageKind.logo
              ? widget.profile.storeLogoUrl
              : widget.profile.storeBannerUrl,
        );
    if (!mounted) return;
    setState(() => _uploading = null);
    toast(
      error ??
          (kind == StorefrontImageKind.logo
              ? 'Logo diperbarui'
              : 'Banner diperbarui'),
    );
    if (error == null) ref.invalidate(storeProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final profile = widget.profile;
    final username = ref.watch(authProvider).valueOrNull?.username;
    final typed = _name.text.trim();
    final displayName = typed.isNotEmpty ? typed : (username ?? 'Toko kamu');
    final slug = (profile.storeSlug?.isNotEmpty ?? false)
        ? profile.storeSlug!
        : 'nama-toko';

    return _Card(
      title: 'Identitas Toko',
      description:
          'Banner, logo, dan nama yang akan dilihat pembeli di toko kamu.',
      padBody: false,
      children: [
        // 4:1, the ratio web reserves for the banner.
        AspectRatio(
          aspectRatio: 4,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (profile.storeBannerUrl != null)
                Image.network(profile.storeBannerUrl!, fit: BoxFit.cover)
              else
                Container(
                  color: colors.secondary,
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: context.borderColor, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Ketuk ikon pensil untuk unggah banner',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                  ),
                ),
              if (_uploading == StorefrontImageKind.banner)
                Container(
                  color: Colors.black45,
                  alignment: Alignment.center,
                  child: Text(
                    'Mengunggah...',
                    style: AppTypography.bodySmSemibold(Colors.white),
                  ),
                ),
              Positioned(
                right: 10,
                top: 10,
                child: _PencilButton(
                  size: 32,
                  busy: _uploading == StorefrontImageKind.banner,
                  onTap: () => _pickImage(StorefrontImageKind.banner),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.secondary,
                        border: Border.all(color: context.borderColor),
                      ),
                      child: profile.storeLogoUrl != null
                          ? Image.network(
                              profile.storeLogoUrl!,
                              fit: BoxFit.cover,
                            )
                          : Center(
                              child: Text(
                                'Logo',
                                style: AppTypography.caption(
                                  context.mutedForeground,
                                ),
                              ),
                            ),
                    ),
                    if (_uploading == StorefrontImageKind.logo)
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black45,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '...',
                          style: AppTypography.captionSemibold(Colors.white),
                        ),
                      ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: _PencilButton(
                        size: 28,
                        busy: _uploading == StorefrontImageKind.logo,
                        onTap: () => _pickImage(StorefrontImageKind.logo),
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
                    if (_editingName)
                      TextField(
                        controller: _name,
                        autofocus: true,
                        maxLength: 40,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _commitName(),
                        style: AppTypography.h3(colors.onSurface),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Misal: Toko Pikachu',
                          counterText: '',
                          suffixIcon: IconButton(
                            icon: const Icon(LucideIcons.check, size: 18),
                            onPressed: saving ? null : _commitName,
                          ),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.h3(colors.onSurface),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              LucideIcons.pencil,
                              size: 16,
                              color: context.mutedForeground,
                            ),
                            onPressed: () =>
                                setState(() => _editingName = true),
                          ),
                        ],
                      ),
                    Text(
                      'pokepedia.id/market/$slug',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(context.mutedForeground),
                    ),
                    if (profile.cityName != null)
                      Text(
                        profile.cityName!,
                        style: AppTypography.caption(context.mutedForeground),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PencilButton extends StatelessWidget {
  const _PencilButton({
    required this.size,
    required this.busy,
    required this.onTap,
  });

  final double size;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).cardColor,
      shape: CircleBorder(side: BorderSide(color: context.borderColor)),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            LucideIcons.pencil,
            size: size * 0.45,
            color: busy ? context.mutedForeground : context.appColors.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Ports `storefront-about-section.tsx`. Web commits on blur; so does this,
/// with an explicit button as the backstop on a touch keyboard.
class _AboutSection extends ConsumerStatefulWidget {
  const _AboutSection({required this.profile});

  final StoreProfile profile;

  @override
  ConsumerState<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends ConsumerState<_AboutSection>
    with _SavesSection {
  static const _maxLength = 2000;

  late final _about = TextEditingController(text: widget.profile.aboutMd ?? '');

  @override
  void initState() {
    super.initState();
    // Drives the character counter web prints under the box.
    _about.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _about.dispose();
    super.dispose();
  }

  void _commit() {
    if (_about.text.trim() == (widget.profile.aboutMd ?? '').trim()) return;
    runSave(
      () => ref.read(storeProfileRepositoryProvider).saveAbout(_about.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Tentang Toko',
      description: 'Cerita tentang toko kamu!',
      children: [
        Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) _commit();
          },
          child: TextField(
            controller: _about,
            maxLines: 6,
            maxLength: _maxLength,
            decoration: const InputDecoration(
              hintText:
                  'Beri deskripsi tentang tokomu, jenis produk yang kamu '
                  'jual, atau cerita menarik lainnya!',
              isDense: true,
              counterText: '',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_about.text.length}/$_maxLength karakter',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ),
            ElevatedButton(
              onPressed: saving ? null : _commit,
              child: Text(saving ? 'Menyimpan...' : 'Simpan'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Ports `seller-pickup-section.tsx` — the pickup address, with web's map
/// picker alongside the area dropdowns.
class _PickupSection extends ConsumerStatefulWidget {
  const _PickupSection({required this.profile});

  final StoreProfile profile;

  @override
  ConsumerState<_PickupSection> createState() => _PickupSectionState();
}

class _PickupSectionState extends ConsumerState<_PickupSection>
    with _SavesSection {
  late final _name = TextEditingController(
    text: widget.profile.contactName ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.profile.contactPhone ?? '',
  );
  late final _postal = TextEditingController(
    text: widget.profile.postalCode ?? '',
  );
  late final _address = TextEditingController(
    text: widget.profile.fullAddress ?? '',
  );
  late final _notes = TextEditingController(text: widget.profile.notes ?? '');

  AreaOption? _province;
  AreaOption? _city;
  AreaOption? _district;
  double? _latitude;
  double? _longitude;
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _postal.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The row keeps area codes, not objects; this resolves them once the
  /// bundled catalog is loaded.
  void _seed(AreaCatalog catalog) {
    if (_seeded) return;
    _seeded = true;
    final profile = widget.profile;
    if (profile.provinceId != null) {
      _province = catalog.findProvince(profile.provinceId!);
    }
    if (profile.cityId != null) _city = catalog.findRegency(profile.cityId!);
    if (profile.districtId != null) {
      _district = catalog.findDistrict(profile.districtId!);
    }
  }

  /// Opens the map, then matches what Nominatim returns against the bundled
  /// catalog.
  ///
  /// A miss leaves the dropdown alone rather than clearing a correct value:
  /// the coordinates and the street text are saved either way, and a wrong
  /// area code is worse than an unchanged one.
  Future<void> _pickOnMap(AreaCatalog catalog) async {
    final picked = await showMapPicker(
      context,
      initialLatitude: _latitude ?? widget.profile.pickupLat,
      initialLongitude: _longitude ?? widget.profile.pickupLng,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _latitude = picked.latitude;
      _longitude = picked.longitude;

      final result = picked.result;
      if (result == null) return;

      final province = _match(catalog.provinces, result.province);
      if (province != null && province.code != _province?.code) {
        _province = province;
        _city = null;
        _district = null;
      }
      final activeProvince = _province;
      if (activeProvince != null) {
        final city = _match(
          catalog.regenciesOf(activeProvince.code),
          result.city,
        );
        if (city != null && city.code != _city?.code) {
          _city = city;
          _district = null;
        }
      }
      final activeCity = _city;
      if (activeCity != null) {
        final district = _match(
          catalog.districtsOf(activeCity.code),
          result.district,
        );
        if (district != null) _district = district;
      }

      if (result.postalCode != null && _postal.text.trim().isEmpty) {
        _postal.text = result.postalCode!;
      }
      if (result.displayName != null && _address.text.trim().isEmpty) {
        _address.text = result.displayName!;
      }
    });
  }

  /// Compares on the significant part of the name: OSM says "Kota Bandung"
  /// where the catalog says "Bandung", and "Daerah Khusus Ibukota Jakarta"
  /// where it says "DKI Jakarta", so the administrative words are dropped
  /// before comparing.
  static AreaOption? _match(List<AreaOption> options, String? name) {
    if (name == null || name.isEmpty) return null;

    String normalise(String value) => value
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'\b(kota|kabupaten|kab\.?|provinsi|prov\.?|daerah|khusus|'
            r'ibukota|istimewa|administrasi|adm\.?|kecamatan|kec\.?)\b',
          ),
          '',
        )
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final needle = normalise(name);
    if (needle.isEmpty) return null;

    for (final option in options) {
      if (normalise(option.name) == needle) return option;
    }
    for (final option in options) {
      final candidate = normalise(option.name);
      if (candidate.isNotEmpty &&
          (candidate.contains(needle) || needle.contains(candidate))) {
        return option;
      }
    }
    return null;
  }

  void _save() {
    final province = _province;
    final city = _city;
    final district = _district;

    if (province == null || city == null || district == null) {
      toast('Lengkapi provinsi, kota, dan kecamatan.');
      return;
    }
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      toast('Nama dan nomor HP wajib diisi.');
      return;
    }
    if (_address.text.trim().isEmpty) {
      toast('Alamat lengkap wajib diisi.');
      return;
    }

    runSave(
      () => ref
          .read(storeProfileRepositoryProvider)
          .savePickupAddress(
            contactName: _name.text,
            contactPhone: _phone.text,
            provinceId: province.code,
            provinceName: province.name,
            cityId: city.code,
            cityName: city.name,
            districtId: district.code,
            districtName: district.name,
            postalCode: _postal.text,
            fullAddress: _address.text,
            notes: _notes.text,
            latitude: _latitude ?? widget.profile.pickupLat,
            longitude: _longitude ?? widget.profile.pickupLng,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final catalogAsync = ref.watch(areaCatalogProvider);
    final lat = _latitude ?? widget.profile.pickupLat;
    final lng = _longitude ?? widget.profile.pickupLng;

    return _Card(
      title: 'Alamat Pengirim',
      description: 'Alamat penjemputan kurir untuk setiap pesanan kamu.',
      children: [
        catalogAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          error: (_, __) => Text(
            'Gagal memuat daftar wilayah.',
            style: AppTypography.caption(colors.error),
          ),
          data: (catalog) {
            _seed(catalog);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Web leads with the map: pinning the spot fills in the rest.
                OutlinedButton.icon(
                  onPressed: saving ? null : () => _pickOnMap(catalog),
                  icon: const Icon(LucideIcons.map, size: 16),
                  label: Text(
                    lat == null
                        ? 'Pilih lokasi di peta'
                        : 'Ubah lokasi di peta',
                  ),
                ),
                if (lat != null && lng != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.mapPin,
                          size: 14,
                          color: context.mutedForeground,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${lat.toStringAsFixed(5)}, '
                          '${lng.toStringAsFixed(5)}',
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nama penerima',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Nomor HP',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                _AreaField(
                  label: 'Provinsi',
                  value: _province,
                  options: catalog.provinces,
                  onChanged: (v) => setState(() {
                    _province = v;
                    // A city from the old province would be nonsense under
                    // the new one.
                    _city = null;
                    _district = null;
                  }),
                ),
                const SizedBox(height: 10),
                _AreaField(
                  label: 'Kota/Kabupaten',
                  value: _city,
                  options: _province == null
                      ? const []
                      : catalog.regenciesOf(_province!.code),
                  onChanged: (v) => setState(() {
                    _city = v;
                    _district = null;
                  }),
                ),
                const SizedBox(height: 10),
                _AreaField(
                  label: 'Kecamatan',
                  value: _district,
                  options: _city == null
                      ? const []
                      : catalog.districtsOf(_city!.code),
                  onChanged: (v) => setState(() => _district = v),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _postal,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Kode pos',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _address,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Alamat lengkap',
            hintText: 'Nama jalan, nomor rumah, RT/RW',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(
            labelText: 'Catatan untuk kurir (opsional)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Menyimpan...' : 'Simpan Alamat'),
          ),
        ),
      ],
    );
  }
}

class _AreaField extends StatelessWidget {
  const _AreaField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final AreaOption? value;
  final List<AreaOption> options;
  final ValueChanged<AreaOption?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AreaOption>(
      initialValue: options.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(option.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: options.isEmpty ? null : onChanged,
    );
  }
}

/// Ports `toko-libur-section.tsx`, including its two states: the amber banner
/// while a vacation runs, the form when none does.
class _VacationSection extends ConsumerStatefulWidget {
  const _VacationSection({required this.profile});

  final StoreProfile profile;

  @override
  ConsumerState<_VacationSection> createState() => _VacationSectionState();
}

class _VacationSectionState extends ConsumerState<_VacationSection>
    with _SavesSection {
  VacationMode _mode = VacationMode.soft;
  int _days = 7;
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final amber = context.appSemantic.condMp;
    final profile = widget.profile;

    if (profile.onVacation) {
      final hard = profile.vacationMode == 'hard';
      return _Card(
        title: 'Toko Libur',
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: amber.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    hard ? 'Toko sedang dipause' : 'Toko dalam mode libur',
                    style: AppTypography.badge(amber),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hard
                      ? 'Listing kamu disembunyikan dan pembeli tidak bisa '
                            'checkout.'
                      : 'Listing masih tampil, pembeli bisa checkout, tapi '
                            'pengiriman tertunda.',
                  style: AppTypography.caption(colors.onSurface),
                ),
                if (profile.vacationUntil != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Berakhir: ${formatShortDateId(profile.vacationUntil!)}',
                      style: AppTypography.caption(colors.onSurface),
                    ),
                  ),
                if (profile.vacationMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Pesan: ${profile.vacationMessage}',
                      style: AppTypography.caption(colors.onSurface),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: saving
                  ? null
                  : () => runSave(
                      () => ref
                          .read(storeProfileRepositoryProvider)
                          .saveVacation(),
                    ),
              child: Text(saving ? 'Menyimpan...' : 'Akhiri Libur'),
            ),
          ),
        ],
      );
    }

    // The server caps soft at 15 days and hard at 30; the slider stops in the
    // same place rather than offering a value it would reject.
    final maxDays = _mode.maxDays;
    final days = _days.clamp(1, maxDays);
    final until = DateTime.now().add(Duration(days: days));

    return _Card(
      title: 'Toko Libur',
      children: [
        Text(
          'Aktifkan libur saat kamu tidak bisa melayani pesanan. Pesanan yang '
          'masuk sebelum libur tetap harus dikirim.',
          style: AppTypography.bodySm(context.mutedForeground),
        ),
        const SizedBox(height: 12),
        Text(
          'Mode libur',
          style: AppTypography.captionSemibold(colors.onSurface),
        ),
        const SizedBox(height: 6),
        for (final mode in VacationMode.values) ...[
          _ModeTile(
            mode: mode,
            selected: _mode == mode,
            onTap: saving
                ? null
                : () => setState(() {
                    _mode = mode;
                    if (_days > mode.maxDays) _days = mode.maxDays;
                  }),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Text(
          'Durasi libur',
          style: AppTypography.captionSemibold(colors.onSurface),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: days.toDouble(),
                min: 1,
                max: maxDays.toDouble(),
                divisions: maxDays - 1,
                label: '$days hari',
                onChanged: saving
                    ? null
                    : (v) => setState(() => _days = v.round()),
              ),
            ),
            SizedBox(
              width: 62,
              child: Text(
                '$days hari',
                textAlign: TextAlign.right,
                style: AppTypography.bodySmSemibold(colors.onSurface),
              ),
            ),
          ],
        ),
        Text(
          'Berakhir: ${formatShortDateId(until)}',
          style: AppTypography.caption(context.mutedForeground),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            style: AppTypography.captionSemibold(colors.onSurface),
            children: [
              const TextSpan(text: 'Pesan untuk pembeli '),
              TextSpan(
                text: '(opsional)',
                style: AppTypography.caption(context.mutedForeground),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _message,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: 'Contoh: Sedang mudik Lebaran, kembali tgl 15',
            isDense: true,
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton(
            onPressed: saving
                ? null
                : () => runSave(
                    () => ref
                        .read(storeProfileRepositoryProvider)
                        .saveVacation(
                          mode: _mode,
                          days: days,
                          message: _message.text,
                        ),
                  ),
            child: Text(saving ? 'Menyimpan...' : 'Aktifkan Libur'),
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final VacationMode mode;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? colors.primary : context.borderColor,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? LucideIcons.circleDot : LucideIcons.circle,
              size: 18,
              color: selected ? colors.primary : context.mutedForeground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.title,
                    style: AppTypography.bodySmSemibold(colors.onSurface),
                  ),
                  Text(
                    mode.description,
                    style: AppTypography.caption(context.mutedForeground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
