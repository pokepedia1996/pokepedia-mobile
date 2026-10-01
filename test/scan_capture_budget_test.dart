import 'package:flutter_test/flutter_test.dart';
import 'package:pokepedia_mobile/features/scanner/repository/models/scan_models.dart';
import 'package:pokepedia_mobile/features/scanner/utils/warp_quad.dart';

Quad _rect(double w, double h) =>
    Quad([const Point2(0, 0), Point2(w, 0), Point2(w, h), Point2(0, h)]);

/// `scan.server.ts` resizes every upload to 512 before the embedder sees it.
/// The app was warping to 1400 and uploading 1400 — about three times web's
/// pixel count, over mobile data, for an embedder that never saw them.
void main() {
  test('the upload is sized for the embedder, not for the camera', () {
    // Web's CAPTURE_MAX_SIDE. Above the server's 512 so the final downscale
    // is its Lanczos rather than ours, and no higher than it has to be.
    expect(captureMaxSide, 768);
  });

  test('the warp stops at the same size the upload does', () {
    // The warp is per-pixel, so anything larger is sampled and interpolated
    // only to be thrown away by the resize that follows it.
    final huge = _rect(5000, 7000);
    expect(warpOutputSize(huge).width, captureMaxSide);

    // Sideways too: the cap is on the long side, whichever one that is.
    final wide = _rect(7000, 5000);
    expect(warpOutputSize(wide).width, captureMaxSide);
    expect(warpOutputSize(wide).height, lessThan(captureMaxSide));
  });

  test('a card smaller than the cap is left alone', () {
    // The cap is a ceiling, not a target — upscaling a distant card would
    // invent detail the embedder then reads as real.
    expect(warpOutputSize(_rect(200, 280)).width, lessThan(captureMaxSide));
  });
}
