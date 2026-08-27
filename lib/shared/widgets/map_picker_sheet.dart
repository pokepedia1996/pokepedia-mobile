import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_radius.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../utils/geocode.dart';

/// What the picker hands back: where the pin ended up, and whatever Nominatim
/// knows about that point.
class PickedLocation {
  const PickedLocation({
    required this.latitude,
    required this.longitude,
    this.result,
  });

  final double latitude;
  final double longitude;
  final GeocodeResult? result;
}

/// Ports `features/address/components/map-picker.tsx` — drop a pin, search a
/// place, and read back the address there.
///
/// Same tiles and same geocoder as web (OpenStreetMap + Nominatim), so no API
/// key is involved and nothing new has to be provisioned to ship it.
Future<PickedLocation?> showMapPicker(
  BuildContext context, {
  double? initialLatitude,
  double? initialLongitude,
}) {
  return showModalBottomSheet<PickedLocation>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _MapPickerSheet(
      initialLatitude: initialLatitude,
      initialLongitude: initialLongitude,
    ),
  );
}

/// Monas. Where the map opens when the seller has never set a point.
const _defaultCenter = LatLng(-6.1754, 106.8272);

class _MapPickerSheet extends StatefulWidget {
  const _MapPickerSheet({this.initialLatitude, this.initialLongitude});

  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<_MapPickerSheet> createState() => _MapPickerSheetState();
}

class _MapPickerSheetState extends State<_MapPickerSheet> {
  final _controller = MapController();
  final _search = TextEditingController();

  late LatLng _center =
      widget.initialLatitude != null && widget.initialLongitude != null
      ? LatLng(widget.initialLatitude!, widget.initialLongitude!)
      : _defaultCenter;

  GeocodeResult? _address;
  bool _resolving = false;
  bool _searching = false;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    // Name the point the map opens on, so the sheet isn't blank before the
    // first drag.
    _resolve(_center);
  }

  @override
  void dispose() {
    _settle?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Reverse-geocodes after the map stops moving. Nominatim rate-limits, and
  /// a lookup per frame of a drag would both break the policy and be thrown
  /// away immediately.
  void _onMoved(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _resolve(_center);
    });
  }

  Future<void> _resolve(LatLng point) async {
    setState(() => _resolving = true);
    final result = await reverseGeocode(point.latitude, point.longitude);
    if (!mounted) return;
    setState(() {
      _address = result;
      _resolving = false;
    });
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.isEmpty || _searching) return;

    setState(() => _searching = true);
    final results = await searchPlace(query);
    if (!mounted) return;
    setState(() => _searching = false);

    if (results.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Lokasi tidak ditemukan.'),
            persist: false,
          ),
        );
      return;
    }

    final first = results.first;
    final target = LatLng(first.latitude, first.longitude);
    _controller.move(target, 16);
    setState(() {
      _center = target;
      _address = first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final address = _address;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pilih Lokasi',
                      style: AppTypography.h3(colors.onSurface),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Cari alamat atau nama tempat',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          onPressed: _runSearch,
                        ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  FlutterMap(
                    mapController: _controller,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 16,
                      onPositionChanged: _onMoved,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        // OSM's tile policy requires an identifying agent.
                        userAgentPackageName: 'id.pokepedia.mobile',
                      ),
                    ],
                  ),
                  // The pin is fixed to the centre of the viewport and the
                  // map moves under it, which is steadier on a phone than
                  // dragging a marker with a fingertip over it.
                  IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: colors.primary,
                        shadows: const [
                          Shadow(blurRadius: 6, color: Colors.black26),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: context.mutedForeground,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _resolving
                              ? 'Mencari alamat...'
                              : address?.displayName ??
                                    'Geser peta untuk menandai lokasi',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption(context.mutedForeground),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(
                      PickedLocation(
                        latitude: _center.latitude,
                        longitude: _center.longitude,
                        result: address,
                      ),
                    ),
                    child: const Text('Gunakan lokasi ini'),
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
