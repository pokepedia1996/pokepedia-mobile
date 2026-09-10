import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// What `uploadChatMedia` accepts — `ALLOWED_IMAGE_TYPES` on the web.
const chatAllowedImageTypes = [
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
];

/// `MAX_IMAGE_SIZE` — the ceiling on what a user may pick.
const chatMaxImageBytes = 10 * 1024 * 1024;

/// What the compressor aims to come in under: web's `maxSizeMB: 0.5`.
const _targetBytes = 512 * 1024;

/// `maxWidthOrHeight` in the same call.
const _maxEdge = 1920;

/// The quality ladder. Web hands `browser-image-compression` an initial 0.8
/// and lets it iterate toward the size target; this walks down by hand,
/// which is the same bargain — fidelity traded for bytes, best effort.
const _qualityLadder = [80, 70, 60, 50];

/// The bytes to upload, and what the row's `media_metadata` should say.
class ChatImage {
  const ChatImage({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;

  Map<String, dynamic> get metadata => {
    'width': width,
    'height': height,
    'file_size': bytes.length,
    'mime_type': mimeType,
  };
}

/// The picked file, on its way into [compressChatImage].
class ChatImageInput {
  const ChatImageInput({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

/// Sniffs the type from the file's own header rather than its extension,
/// which is what a picker's temp file often lacks.
///
/// Returns null for anything not in [chatAllowedImageTypes] — including an
/// untranscoded HEIC off an iPhone, which the caller rejects the way web
/// rejects a type `browser-image-compression` can't read.
String? sniffImageMime(Uint8List bytes) {
  if (bytes.length < 12) return null;
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return 'image/gif';
  }
  // RIFF....WEBP
  if (bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// Ports the `browser-image-compression` step of `uploadChatMedia`: scale the
/// long edge down to 1920 and re-encode as JPEG, aiming under half a
/// megabyte.
///
/// A GIF passes through untouched, as it does on the web — re-encoding one to
/// JPEG would freeze it on its first frame.
///
/// Returns null when the bytes won't decode, which the caller reports as
/// web's "Gagal memproses foto, coba foto lain". Meant to be run through
/// `compute`: decoding a 12MP photo on the UI isolate drops frames.
ChatImage? compressChatImage(ChatImageInput input) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(input.bytes);
  } on Exception {
    return null;
  } on RangeError {
    return null;
  }
  if (decoded == null) return null;

  if (input.mimeType == 'image/gif') {
    return ChatImage(
      bytes: input.bytes,
      mimeType: 'image/gif',
      width: decoded.width,
      height: decoded.height,
    );
  }

  var image = decoded;
  final longEdge = image.width > image.height ? image.width : image.height;
  if (longEdge > _maxEdge) {
    final scale = _maxEdge / longEdge;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  Uint8List encoded = img.encodeJpg(image, quality: _qualityLadder.first);
  for (final quality in _qualityLadder.skip(1)) {
    if (encoded.length <= _targetBytes) break;
    encoded = img.encodeJpg(image, quality: quality);
  }

  return ChatImage(
    bytes: encoded,
    mimeType: 'image/jpeg',
    width: image.width,
    height: image.height,
  );
}
