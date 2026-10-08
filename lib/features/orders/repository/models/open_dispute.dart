import 'dart:typed_data';

import '../../utils/dispute_reasons.dart';

/// A photo picked as dispute evidence, held in memory until the basket is
/// submitted — web's `PickedPhoto`.
class DisputeEvidencePhoto {
  const DisputeEvidencePhoto({
    required this.bytes,
    required this.contentType,
    required this.extension,
  });

  final Uint8List bytes;
  final String contentType;
  final String extension;
}

/// One entry of `POST /api/orders/[slug]/disputes`'s `EntrySchema`, after its
/// photos have been uploaded.
class OpenDisputeEntry {
  const OpenDisputeEntry({
    required this.reason,
    required this.itemSlugs,
    required this.detail,
    required this.photoUrls,
    this.videoUrl,
    this.shortQuantity = const {},
    this.requestedResolution,
  });

  final DisputeReason reason;
  final List<String> itemSlugs;
  final String detail;
  final List<String> photoUrls;
  final String? videoUrl;

  /// `order_items.slug` -> how many are missing; only sent for `short`.
  final Map<String, int> shortQuantity;
  final DisputeResolution? requestedResolution;

  bool get _isShort => reason == DisputeReason.short;

  /// Matches `submitBasket`'s payload: `short` always asks for a refund, and
  /// the optional fields are omitted rather than sent as null, which the
  /// route's zod schema rejects.
  Map<String, dynamic> toJson() => {
    'itemSlugs': itemSlugs,
    'reason': reason.raw,
    'detail': detail.trim(),
    'photoUrls': photoUrls,
    if (videoUrl != null && videoUrl!.trim().isNotEmpty)
      'videoUrl': videoUrl!.trim(),
    if (_isShort)
      'shortQuantity': {
        for (final slug in itemSlugs) slug: shortQuantity[slug] ?? 1,
      },
    if (_isShort)
      'requestedResolution': DisputeResolution.refundOnly.raw
    else if (requestedResolution != null)
      'requestedResolution': requestedResolution!.raw,
  };
}
