/// Courier naming and tracking links, ported from
/// `lib/shipping/biteship/courier-display.ts` and
/// `lib/shipping/core/tracking-url.ts`.
library;

/// `COURIER_CODE_ALIASES` — Biteship answers with `id` for ID Express, but
/// the tracking table is keyed on the full name.
const _aliases = <String, String>{'id': 'idexpress'};

/// `normalizeCourierCode`.
String? normalizeCourierCode(String? raw) {
  if (raw == null) return null;
  final key = raw.trim().toLowerCase();
  if (key.isEmpty) return null;
  return _aliases[key] ?? key;
}

/// `COURIER_DISPLAY_NAME`, verbatim.
///
/// The column holds Biteship's codes; these are the names people recognise.
/// Kept identical to the site's table — a courier called "J&T Express" in one
/// place and "J&T" in the other is the kind of difference a buyer reads as
/// two different couriers.
const courierDisplayNames = <String, String>{
  'jne': 'JNE',
  'jnt': 'J&T Express',
  'sicepat': 'SiCepat',
  'anteraja': 'AnterAja',
  'pos': 'Pos Indonesia',
  'tiki': 'TIKI',
  'ninja': 'Ninja Xpress',
  'id': 'ID Express',
  'sap': 'SAP Express',
  'lion': 'Lion Parcel',
  'gojek': 'Gojek',
  'grab': 'Grab',
  'lalamove': 'Lalamove',
  'borzo': 'Borzo',
  'mrspeedy': 'Borzo (Mr. Speedy)',
  'deliveree': 'Deliveree',
};

/// `courierDisplayName` — falls back to the bare code upper-cased, as web
/// does, so an unmapped courier still prints as something.
String? courierDisplayName(String? code) {
  if (code == null) return null;
  final normalized = code.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  return courierDisplayNames[normalized] ?? code.toUpperCase();
}

/// How a courier's tracking page can be reached.
///
/// [direct] means the resi can be put straight in the URL; [manual] means the
/// courier only offers a landing page and the buyer has to paste it there.
enum TrackingMode { direct, manual }

typedef TrackingResolution = ({String url, TrackingMode mode});

/// Where the buyer can look the parcel up. Only SAP takes the resi in its
/// URL; everything else lands on a form, and anything unknown falls through
/// to cekresi, which covers all of them.
const _universalTracker = 'https://cekresi.com/';

const _directTemplates = <String, String>{
  'sap': 'https://www.sapx.id/id/cek-awb/{awb}',
};

const _landingPages = <String, String>{
  'jne': 'https://www.jne.co.id/tracking-package',
  'jnt': 'https://jet.co.id/track',
  'sicepat': 'https://www.sicepat.com/checkAwb',
  'anteraja': 'https://anteraja.id/tracking',
  'ninja': 'https://www.ninjaxpress.co/id-id/tracking',
  'pos': 'https://www.posindonesia.co.id/id/tracking',
  'gojek': 'https://www.gojek.com/en-id/gosend',
  'grab': 'https://www.grab.com/id/express/',
  'idexpress': 'https://idexpress.com/lacak-paket',
  'lion': 'https://lionparcel.com/track/stt',
  'tiki': 'https://www.tiki.id/id/tracking',
  'rpx': 'https://www.rpx.co.id/tracking',
  'paxel': 'https://paxel.co/id/lacak-pengiriman',
};

/// `getTrackingUrl`.
TrackingResolution getTrackingUrl(String? courierCode, String? awb) {
  final code = normalizeCourierCode(courierCode);
  if (code == null) {
    return (url: _universalTracker, mode: TrackingMode.manual);
  }

  final template = _directTemplates[code];
  if (template != null) {
    final resi = awb?.trim();
    if (resi == null || resi.isEmpty) {
      return (url: _universalTracker, mode: TrackingMode.manual);
    }
    return (
      url: template.replaceAll('{awb}', Uri.encodeComponent(resi)),
      mode: TrackingMode.direct,
    );
  }

  final landing = _landingPages[code];
  if (landing == null) {
    return (url: _universalTracker, mode: TrackingMode.manual);
  }
  return (url: landing, mode: TrackingMode.manual);
}
