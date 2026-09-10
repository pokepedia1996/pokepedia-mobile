// Generates the launcher-icon and splash sources under `branding/` from the
// website's own artwork, so both clients wear the same mark.
//
// Run after changing the brand:
//   dart run tool/generate_branding.dart
//
// The outputs are build inputs for `flutter_launcher_icons` and
// `flutter_native_splash`, not bundled assets — nothing here ships inside the
// app, so they live outside `assets/`.
import 'dart:io';

import 'package:image/image.dart' as img;

/// `pokepedia-web/public/pwa-icon-512.png` — the mark on its patterned cream
/// tile, corners already rounded.
const _webTile = '../pokepedia-web/public/pwa-icon-512.png';

/// `pokepedia-web/app/icon.png` — the same mark with nothing behind it.
const _webMark = '../pokepedia-web/app/icon.png';

/// The manifest's `background_color`: the tile's own cream, used to fill the
/// alpha iOS refuses.
final _iconBackground = img.ColorRgb8(0xF9, 0xF5, 0xE8);

img.Image _load(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('missing source: $path');
    exit(1);
  }
  final decoded = img.decodePng(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('could not decode: $path');
    exit(1);
  }
  return decoded;
}

/// [source] scaled to [size] and centred on a [canvas]-square, over
/// [background] when one is given and transparency when not.
img.Image _centred(
  img.Image source, {
  required int canvas,
  required int size,
  img.Color? background,
}) {
  final out = img.Image(width: canvas, height: canvas, numChannels: 4);
  if (background != null) {
    img.fill(out, color: background);
  }
  final scaled = img.copyResize(
    source,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
  final offset = ((canvas - size) / 2).round();
  return img.compositeImage(out, scaled, dstX: offset, dstY: offset);
}

void _write(String path, img.Image image) {
  File(path).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $path (${image.width}x${image.height})');
}

void main() {
  final tile = _load(_webTile);
  final mark = _load(_webMark);

  // iOS and legacy Android take one opaque square. The tile's rounded corners
  // are transparent, and iOS renders alpha as black, so they are filled with
  // the cream the tile itself sits on — the platform masks its own corners
  // over the top.
  _write(
    'branding/app-icon.png',
    _centred(tile, canvas: 1024, size: 1024, background: _iconBackground),
  );

  // Android's adaptive foreground is masked to a circle at worst, which keeps
  // roughly the middle two thirds. The mark is inset to 62% so nothing of it
  // is ever cut.
  _write(
    'branding/app-icon-foreground.png',
    _centred(mark, canvas: 1024, size: 635),
  );

  // The splash composites over the theme's own background colour, so the mark
  // travels alone.
  _write('branding/splash-mark.png', _centred(mark, canvas: 512, size: 512));

  // Android 12 hands the splash a 1152px canvas and shows the middle 768 of
  // it inside a circle.
  _write(
    'branding/splash-icon-android12.png',
    _centred(mark, canvas: 1152, size: 660),
  );
}
