import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ports `cropImageToAspect` from `storefront-uploads.ts` — centre-crops to
/// the target aspect, then scales to exactly the target size.
///
/// Web crops in a canvas and encodes WebP; the `image` package can't write
/// WebP, so this encodes JPEG at a matching quality. The bucket serves both
/// and the route's URL check only cares about the path, not the extension.
///
/// Returns null when the bytes aren't a decodable image — a format the
/// package can't read (an untranscoded HEIC off an iPhone), or a truncated
/// file. The decoders probe by signature and can throw on malformed input
/// rather than declining it, so this catches as well as null-checks; the
/// caller shows web's "Gagal memproses foto, coba foto lain" either way.
Uint8List? cropToAspect(
  Uint8List bytes, {
  required int targetWidth,
  required int targetHeight,
  int quality = 88,
}) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Exception {
    return null;
  } on RangeError {
    return null;
  }
  if (decoded == null) return null;

  final sourceAspect = decoded.width / decoded.height;
  final targetAspect = targetWidth / targetHeight;

  var x = 0;
  var y = 0;
  var width = decoded.width;
  var height = decoded.height;

  if (sourceAspect > targetAspect) {
    // Too wide: trim the sides.
    width = (decoded.height * targetAspect).round();
    x = ((decoded.width - width) / 2).round();
  } else if (sourceAspect < targetAspect) {
    // Too tall: trim top and bottom.
    height = (decoded.width / targetAspect).round();
    y = ((decoded.height - height) / 2).round();
  }

  final cropped = img.copyCrop(
    decoded,
    x: x,
    y: y,
    width: width,
    height: height,
  );
  final resized = img.copyResize(
    cropped,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.average,
  );
  return img.encodeJpg(resized, quality: quality);
}
