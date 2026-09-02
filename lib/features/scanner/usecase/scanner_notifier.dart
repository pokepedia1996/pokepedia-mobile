import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pokepedia_api.dart';
import '../../../shared/models/card_model.dart';
import '../repository/models/scan_models.dart';
import '../repository/scanner_repository.dart';
import '../utils/card_capture.dart';

/// Ports `features/scanner/hooks/useScanner.ts` — the state of the one scan
/// currently in flight, separate from the batch it eventually lands in
/// (`scan_session_notifier.dart`).

@immutable
sealed class ScanState {
  const ScanState();
}

class ScanIdle extends ScanState {
  const ScanIdle();
}

class ScanLoading extends ScanState {
  const ScanLoading();
}

class ScanMatched extends ScanState {
  const ScanMatched({
    required this.matches,
    required this.variants,
    required this.confident,
    required this.logId,
  });

  final List<ScanMatch> matches;
  final List<ScanCard> variants;
  final bool confident;
  final int? logId;

  ScanCard get card => matches.first.card;
}

class ScanFailed extends ScanState {
  const ScanFailed(this.message, {this.retryAfter});

  /// Already user-facing Indonesian — either the server's own mapped string
  /// (`ERROR_MESSAGES` in `app/api/scan/route.ts`) or one of the client-side
  /// messages below.
  final String message;

  /// How long the server asked us to wait, when it said so. Set only for a
  /// 429 — either the per-user scan budget (30/60s) or the embedder shedding
  /// load. The capture path holds the shutter for at least this long rather
  /// than letting the user retry straight into the same refusal.
  final Duration? retryAfter;
}

class ScannerNotifier extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanIdle();

  /// A scan can still be in flight when the user resets, switches language, or
  /// re-arms capture. Without this a slow earlier response lands last and
  /// overwrites a newer scan's result.
  var _generation = 0;

  /// Sends a capture for recognition and returns the outcome.
  ///
  /// The caller gets its own result back regardless — only the shared [state]
  /// defers to whichever scan is current, so a superseded response can't
  /// clobber a newer one while the caller still learns what happened to the
  /// request it made.
  Future<ScanState> scan({
    required CardCapture capture,
    required CardLanguage language,
    Map<String, dynamic>? captureMeta,
  }) async {
    final requestGeneration = ++_generation;
    state = const ScanLoading();

    ScanState next;
    try {
      final response = await ref
          .read(scannerRepositoryProvider)
          .scan(
            imageBytes: capture.bytes,
            language: language,
            captureMeta: captureMeta,
          );

      // Guards only an UNCONFIDENT match: a blurred capture can land close to
      // an arbitrary wrong card by chance. A confident match already cleared
      // the server's calibrated distance+margin gate, which is a far stronger
      // signal than this per-device heuristic — so this must never override
      // one.
      final tooBlurry = capture.sharpness < captureMinSharpness;

      if (response.matches.isNotEmpty && (response.confident || !tooBlurry)) {
        next = ScanMatched(
          matches: response.matches,
          variants: response.variants,
          // The server's verdict, not a local recomputation: the thresholds
          // behind it live in two places already (the route and the embedder)
          // and a third copy here would drift out of step unnoticed.
          confident: response.confident,
          logId: response.logId,
        );
      } else {
        next = ScanFailed(
          tooBlurry
              ? 'Gambar buram. Tahan kartu lebih stabil dan tambah cahaya.'
              : 'Kartu tidak dikenali, pindai ulang',
        );
      }
    } on ApiRateLimitedException catch (e) {
      // Caught ahead of `ApiException` so the wait survives — retrying
      // immediately would spend another token against a budget that is
      // already exhausted.
      next = ScanFailed(e.message, retryAfter: e.retryAfter);
    } on ApiException catch (e) {
      // The route already localizes every failure it knows about, so its
      // message beats anything invented here.
      next = ScanFailed(e.message);
    } catch (e) {
      if (kDebugMode) debugPrint('[scan] unexpected failure: $e');
      next = ScanFailed('Gagal menghubungi server, periksa koneksi');
    }

    if (requestGeneration == _generation) state = next;
    return next;
  }

  void reset() {
    _generation++;
    state = const ScanIdle();
  }

  /// For failures that never reach [scan] — e.g. the crop couldn't be produced
  /// from the captured frame — so they still surface through the same state.
  void setError(String message) {
    _generation++;
    state = ScanFailed(message);
  }
}

final scannerProvider = NotifierProvider<ScannerNotifier, ScanState>(
  ScannerNotifier.new,
);

/// The language the scanner tags captures with.
///
/// Separate from [catalogLanguageProvider] on purpose: that one scopes which
/// catalog the user is *browsing*, while this one declares what's physically
/// in their hand. Per the PRD this is the primary mechanism for print
/// language — visual embedding can't reliably separate an Indonesian print
/// from its English reprint, so the human sets it — and it is a live control,
/// re-flippable mid-batch rather than locked once per session.
class ScanLanguageNotifier extends Notifier<CardLanguage> {
  @override
  CardLanguage build() => CardLanguage.id;

  void set(CardLanguage language) => state = language;
}

final scanLanguageProvider =
    NotifierProvider<ScanLanguageNotifier, CardLanguage>(
      ScanLanguageNotifier.new,
    );
