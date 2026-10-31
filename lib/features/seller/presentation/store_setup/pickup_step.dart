import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/design_palette.dart';
import '../../../../shared/utils/geocode.dart';
import '../../../../shared/utils/id_phone.dart';
import '../../../../shared/widgets/setup_kit.dart';
import '../../../account/presentation/widgets/address_form_sheet.dart';
import '../../../account/repository/address_repository.dart';
import '../../../account/repository/models/address_model.dart';
import '../../../account/usecase/address_notifier.dart';
import '../../usecase/store_setup.dart';
import 'store_setup_parts.dart';

/// Monas: where the map opens before anything is known.
const _defaultCenter = LatLng(-6.1754, 106.8272);

/// Finds where the device is. A provider so tests can stand in for GPS.
final currentLocationProvider = Provider<Future<LatLng> Function()>(
  (ref) => _deviceLocation,
);

/// Nominatim, both ways. A provider so tests can answer for it.
final pickupGeocoderProvider =
    Provider<
      ({
        Future<GeocodeResult> Function(double lat, double lng) reverse,
        Future<List<PlaceResult>> Function(String query) search,
      })
    >((ref) => (reverse: reverseGeocode, search: searchPlace));

/// Thrown with what to tell the user when the location can't be had.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);
  final String message;
}

Future<LatLng> _deviceLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationUnavailable('Nyalakan lokasi (GPS) di HP-mu dulu.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw const LocationUnavailable(
      'Izin lokasi ditolak. Cari alamatmu atau geser peta.',
    );
  }
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 15),
    ),
  );
  return LatLng(position.latitude, position.longitude);
}

/// Step 3: where the courier picks up — a pin on the map, the address it
/// resolves to, a landmark, and the option to ship purchases there too.
class PickupStep extends ConsumerStatefulWidget {
  const PickupStep({
    super.key,
    required this.draft,
    required this.palette,
    required this.onBack,
    required this.onNext,
  });

  final StoreSetupDraft draft;
  final DesignPalette palette;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  ConsumerState<PickupStep> createState() => _PickupStepState();
}

class _PickupStepState extends ConsumerState<PickupStep> {
  final _map = MapController();
  final _search = TextEditingController();
  late final _landmark = TextEditingController(text: widget.draft.landmark);

  late LatLng _center = widget.draft.latitude != null
      ? LatLng(widget.draft.latitude!, widget.draft.longitude!)
      : _defaultCenter;

  /// The pin has been put somewhere, not just sitting on the default.
  late bool _placed = widget.draft.latitude != null;
  bool _resolving = false;
  bool _searching = false;
  bool _locating = false;
  List<PlaceResult> _results = const [];
  Timer? _settle;

  /// Fires a search once typing has stopped for [_typingPause].
  Timer? _typing;

  /// The last query sent, so a pause on the same text asks nothing new.
  String _lastQuery = '';

  /// Bumped per search; a reply that comes back after a newer one was sent
  /// is dropped rather than replacing fresher results.
  int _searchSeq = 0;

  /// Long on purpose: Nominatim's policy forbids per-keystroke search, so
  /// this only goes out once the seller has clearly finished typing.
  static const _typingPause = Duration(seconds: 2);
  static const _minQueryLength = 3;

  /// A finger is on the map: the page holds still so the drag pans it.
  bool _onMap = false;

  StoreSetupDraft get _draft => widget.draft;

  @override
  void dispose() {
    _settle?.cancel();
    _typing?.cancel();
    _search.dispose();
    _landmark.dispose();
    super.dispose();
  }

  /// Reverse-geocodes once the map stops: Nominatim rate-limits, and a
  /// lookup per frame of a drag would be thrown away immediately anyway.
  void _onMoved(MapCamera camera, bool hasGesture) {
    if (!hasGesture) return;
    _center = camera.center;
    _placed = true;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _resolve(_center);
    });
  }

  void _moveTo(LatLng point, {GeocodeResult? known}) {
    _map.move(point, 17);
    _center = point;
    _placed = true;
    if (known != null) {
      _apply(point, known);
    } else {
      _resolve(point);
    }
  }

  Future<void> _resolve(LatLng point) async {
    setState(() => _resolving = true);
    final result = await ref
        .read(pickupGeocoderProvider)
        .reverse(point.latitude, point.longitude);
    if (!mounted) return;
    _apply(point, result);
  }

  /// Takes what the geocoder knows about [point], matched against the
  /// bundled area catalog. A level that doesn't match is left empty for
  /// "Ubah" rather than guessed: a wrong district code sends the courier to
  /// the wrong place.
  void _apply(LatLng point, GeocodeResult result) {
    final catalog = ref.read(areaCatalogProvider).valueOrNull;
    setState(() {
      _resolving = false;
      _draft
        ..latitude = point.latitude
        ..longitude = point.longitude;
      if (catalog != null) {
        final area = resolveArea(catalog, result);
        _draft
          ..province = area.province
          ..city = area.city
          ..district = area.district;
      }
      _draft
        ..postalCode = result.postalCode ?? ''
        ..street = result.street ?? _firstPart(result.displayName) ?? '';
    });
  }

  /// "Jalan Ijen, Klojen, Malang, …" → "Jalan Ijen".
  static String? _firstPart(String? displayName) {
    final first = displayName?.split(',').first.trim();
    return first == null || first.isEmpty ? null : first;
  }

  /// A search is on its way: typing has paused, or is about to. The
  /// spinner shows from the keystroke on, so the wait reads as working.
  bool _pending = false;

  void _onTyped(String text) {
    _typing?.cancel();
    final query = text.trim();
    if (query.length < _minQueryLength || query == _lastQuery) {
      setState(() {
        _pending = false;
        if (query.length < _minQueryLength) _results = const [];
      });
      return;
    }
    setState(() => _pending = true);
    _typing = Timer(_typingPause, () {
      if (mounted) _runSearch(typed: true);
    });
  }

  /// [typed]: started by the pause after typing rather than by Enter. It
  /// leaves the keyboard up and always lists the results, since jumping
  /// the map while the seller may still be typing would be a surprise.
  Future<void> _runSearch({bool typed = false}) async {
    _typing?.cancel();
    final query = _search.text.trim();
    if (query.isEmpty) return;
    if (typed && (query.length < _minQueryLength || query == _lastQuery)) {
      setState(() => _pending = false);
      return;
    }
    _lastQuery = query;
    if (!typed) FocusManager.instance.primaryFocus?.unfocus();
    final seq = ++_searchSeq;
    setState(() {
      _pending = false;
      _searching = true;
    });
    final results = await ref.read(pickupGeocoderProvider).search(query);
    if (!mounted || seq != _searchSeq) return;
    setState(() => _searching = false);
    if (results.isEmpty) {
      setState(() => _results = const []);
      _toast('Lokasi tidak ditemukan. Coba kata lain.');
      return;
    }
    if (results.length == 1 && !typed) {
      _pickResult(results.single);
    } else {
      setState(() => _results = results);
    }
  }

  void _pickResult(PlaceResult place) {
    _typing?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _results = const []);
    _moveTo(LatLng(place.latitude, place.longitude), known: place);
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final here = await ref.read(currentLocationProvider)();
      if (mounted) _moveTo(here);
    } on LocationUnavailable catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Lokasimu belum terbaca. Coba lagi atau geser peta.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit() async {
    final catalog = ref.read(areaCatalogProvider).valueOrNull;
    if (catalog == null) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _AddressEditSheet(draft: _draft, catalog: catalog),
    );
    if (changed == true && mounted) setState(() {});
  }

  void _save() {
    _draft.landmark = _landmark.text.trim();
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    // Loaded here so it is ready by the time the map first settles.
    ref.watch(areaCatalogProvider);
    final addresses = ref.watch(addressesProvider);
    // Offered only to someone with no delivery address yet: a second copy
    // of an address they already have would just be a duplicate to delete.
    final offerShipping = addresses.valueOrNull?.isEmpty ?? false;
    if (!offerShipping && addresses.hasValue) _draft.alsoShipping = false;

    return SetupStepLayout(
      palette: palette,
      physics: _onMap ? const NeverScrollableScrollPhysics() : null,
      content: [
        SetupProgress(
          step: 2,
          total: 4,
          palette: palette,
          onBack: widget.onBack,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(0, setupSize(28), 0, setupSize(20)),
          child: SetupHeadline(
            first: 'Kartu dijemput',
            second: 'dari mana?',
            palette: palette,
            size: 38,
            lineHeight: 42,
          ),
        ),
        _mapCard(palette),
        const SizedBox(height: 12),
        _addressCard(palette),
        if (offerShipping)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
            child: InkWell(
              onTap: () =>
                  setState(() => _draft.alsoShipping = !_draft.alsoShipping),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _draft.alsoShipping
                          ? palette.brand
                          : Colors.transparent,
                      border: Border.all(
                        color: _draft.alsoShipping
                            ? palette.brand
                            : palette.border,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: _draft.alsoShipping
                        ? Icon(
                            LucideIcons.check,
                            size: 14,
                            color: palette.ctaForeground,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pakai juga sebagai alamat pengiriman',
                          style: setupText(14, palette.ink, FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Alamat belanjamu langsung beres sekalian.',
                          style: setupText(12, palette.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      footer: [
        SetupPrimaryButton(
          label: 'Simpan alamat',
          palette: palette,
          onPressed: _draft.pickupReady && !_resolving ? _save : null,
        ),
      ],
    );
  }

  Widget _mapCard(DesignPalette palette) {
    final shadow = BoxShadow(
      color: palette.ink.withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    );
    return Listener(
      onPointerDown: (_) => setState(() => _onMap = true),
      onPointerUp: (_) => setState(() => _onMap = false),
      onPointerCancel: (_) => setState(() => _onMap = false),
      child: Container(
        height: setupSize(312),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: palette.chip,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _placed ? 17 : 12,
                onPositionChanged: _onMoved,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  // OSM's tile policy requires an identifying agent.
                  userAgentPackageName: 'id.pokepedia.mobile',
                ),
              ],
            ),
            // The pin stays at the centre and the map moves under it,
            // steadier on a phone than dragging a marker under a fingertip.
            IgnorePointer(
              child: Center(
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: palette.brand.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 36),
                        child: Icon(
                          LucideIcons.mapPin,
                          size: 40,
                          color: palette.brand,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Column(
                children: [
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      border: Border.all(color: palette.border),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [shadow],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.search,
                          size: 16,
                          color: palette.muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            textInputAction: TextInputAction.search,
                            // Nominatim forbids searching per keystroke: a
                            // search goes out after a long pause in typing,
                            // or at once on Enter.
                            onChanged: _onTyped,
                            onSubmitted: (_) => _runSearch(),
                            cursorColor: palette.brand,
                            style: setupText(14, palette.ink),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              hintText: 'Cari jalan, gedung, atau kecamatan',
                              hintStyle: setupText(14, palette.muted),
                            ),
                          ),
                        ),
                        if (_searching || _pending)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.brand,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_results.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        color: palette.surface,
                        border: Border.all(color: palette.border),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [shadow],
                      ),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        children: [
                          for (final place in _results)
                            InkWell(
                              onTap: () => _pickResult(place),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Text(
                                  place.displayName ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: setupText(13, palette.ink),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Material(
                color: palette.surface,
                shape: StadiumBorder(side: BorderSide(color: palette.border)),
                elevation: 2,
                shadowColor: palette.ink.withValues(alpha: 0.2),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _locate,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _locating
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: palette.brand,
                                ),
                              )
                            : Icon(
                                LucideIcons.locateFixed,
                                size: 16,
                                color: palette.brand,
                              ),
                        const SizedBox(width: 6),
                        Text(
                          'Pakai lokasiku',
                          style: setupText(13, palette.ink, FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addressCard(DesignPalette palette) {
    final draft = _draft;
    final hasStreet = draft.street.trim().isNotEmpty;
    final areaMissing =
        _placed &&
        !_resolving &&
        (draft.province == null ||
            draft.city == null ||
            draft.district == null);
    // Province and city usually resolve; the kecamatan is the level OSM
    // most often lacks, and naming it says exactly what "Ubah" is for.
    final onlyDistrictMissing =
        areaMissing && draft.province != null && draft.city != null;
    final phone = draft.phone;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: palette.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.mapPin, size: 18, color: palette.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _resolving
                          ? 'Mencari alamat...'
                          : hasStreet
                          ? draft.street
                          : 'Geser peta ke titik jemput',
                      style: setupText(16, palette.ink, FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      onlyDistrictMissing
                          ? '${draft.city!.name}, ${draft.province!.name}. '
                                'Pilih kecamatan lewat Ubah.'
                          : areaMissing
                          ? 'Wilayahnya belum terbaca. Lengkapi lewat Ubah.'
                          : draft.areaLine.isNotEmpty
                          ? draft.areaLine
                          : 'Atau cari alamatmu di atas peta.',
                      style: setupText(
                        13,
                        areaMissing ? palette.error : palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _edit,
                style: TextButton.styleFrom(
                  foregroundColor: palette.brand,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                ),
                child: Text(
                  'Ubah',
                  style: setupText(13, palette.brand, FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Who the courier asks for: the account and its verified number.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.chip,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.userRound, size: 18, color: palette.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          draft.username,
                          if (phone != null) formatIdPhone(phone),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: setupText(14, palette.ink, FontWeight.w600),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        'Nama & nomor penerima kurir',
                        style: setupText(12, palette.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SetupPill(
                  label: 'Otomatis',
                  icon: LucideIcons.sparkles,
                  background: palette.successSoft,
                  foreground: palette.successText,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Patokan / detail (opsional)',
            style: setupText(13, palette.ink, FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.background,
              border: Border.all(color: palette.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.flag, size: 16, color: palette.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _landmark,
                    onChanged: (v) => _draft.landmark = v,
                    maxLength: 120,
                    cursorColor: palette.brand,
                    style: setupText(14, palette.ink),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintText: 'Rumah pagar hitam',
                      hintStyle: setupText(14, palette.muted),
                    ),
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

/// "Ubah": the address by hand, for when the map's reading is wrong or
/// incomplete — the street, the three area levels, the postal code.
class _AddressEditSheet extends StatefulWidget {
  const _AddressEditSheet({required this.draft, required this.catalog});

  final StoreSetupDraft draft;
  final AreaCatalog catalog;

  @override
  State<_AddressEditSheet> createState() => _AddressEditSheetState();
}

class _AddressEditSheetState extends State<_AddressEditSheet> {
  late final _street = TextEditingController(text: widget.draft.street);
  late final _postal = TextEditingController(text: widget.draft.postalCode);
  late AreaOption? _province = widget.draft.province;
  late AreaOption? _city = widget.draft.city;
  late AreaOption? _district = widget.draft.district;

  @override
  void dispose() {
    _street.dispose();
    _postal.dispose();
    super.dispose();
  }

  bool get _complete =>
      _street.text.trim().isNotEmpty &&
      _province != null &&
      _city != null &&
      _district != null;

  void _apply() {
    widget.draft
      ..street = _street.text.trim()
      ..postalCode = _postal.text.trim()
      ..province = _province
      ..city = _city
      ..district = _district;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = DesignPalette.of(context);
    final catalog = widget.catalog;
    final province = _province;
    final city = _city;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Alamat pickup', style: setupHeading(22, palette.ink)),
              const SizedBox(height: 16),
              TextField(
                controller: _street,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Alamat lengkap',
                  hintText: 'Jl. Ijen No. 25',
                ),
              ),
              const SizedBox(height: 12),
              AreaField(
                label: 'Provinsi',
                value: province,
                options: catalog.provinces,
                onSelected: (p) => setState(() {
                  if (p.code != _province?.code) {
                    _city = null;
                    _district = null;
                  }
                  _province = p;
                }),
              ),
              const SizedBox(height: 12),
              AreaField(
                label: 'Kota/Kabupaten',
                value: city,
                enabled: province != null,
                options: province == null
                    ? const []
                    : catalog.regenciesOf(province.code),
                onSelected: (c) => setState(() {
                  if (c.code != _city?.code) _district = null;
                  _city = c;
                }),
              ),
              const SizedBox(height: 12),
              AreaField(
                label: 'Kecamatan',
                value: _district,
                enabled: city != null,
                options: city == null
                    ? const []
                    : catalog.districtsOf(city.code),
                onSelected: (d) => setState(() => _district = d),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _postal,
                keyboardType: TextInputType.number,
                maxLength: 5,
                decoration: const InputDecoration(
                  labelText: 'Kode pos',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 20),
              SetupPrimaryButton(
                label: 'Pakai alamat ini',
                palette: palette,
                onPressed: _complete ? _apply : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
