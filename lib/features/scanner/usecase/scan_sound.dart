import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The scan chime. Ports `useKachingSound` — same asset, same trigger point:
/// once per card that actually lands in the session.
///
/// With auto-capture there is no shutter and no tap, so this is the only
/// feedback that a scan happened at all. The user is looking at the card in
/// their hand, not the screen.
class ScanSound {
  ScanSound(this._prefs);

  static const _asset = 'sounds/coin-money.mp3';
  static const _mutedKey = 'pokepedia.scan-sound.v1';

  final SharedPreferences? _prefs;

  /// One player reused for every scan. A fresh player per sound leaks native
  /// handles on Android, and scanning a binder fires this a few hundred times
  /// in a sitting.
  final _player = AudioPlayer();
  bool _ready = false;

  bool get muted => _prefs?.getString(_mutedKey) == 'muted';

  Future<void> setMuted(bool value) async {
    await _prefs?.setString(_mutedKey, value ? 'muted' : 'on');
  }

  /// Plays the chime, unless muted.
  ///
  /// Failures are swallowed: a scan that worked should not read as broken
  /// because the audio device was busy or the file could not be decoded.
  Future<void> play() async {
    if (muted) return;
    try {
      if (!_ready) {
        // `lowLatency` keeps the gap between capture and chime short enough
        // to feel like a response rather than a notification.
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.setSource(AssetSource(_asset));
        _ready = true;
      }
      await _player.stop();
      await _player.resume();
    } catch (e) {
      if (kDebugMode) debugPrint('[scan] chime failed (ignored): $e');
    }
  }

  void dispose() => _player.dispose();
}

final scanSoundProvider = Provider<ScanSound>((ref) {
  final sound = ScanSound(ref.watch(sharedPreferencesProvider).valueOrNull);
  ref.onDispose(sound.dispose);
  return sound;
});

/// Cached so the mute flag is readable synchronously at the moment of play —
/// awaiting storage inside `play()` would delay the chime past the point it
/// still reads as feedback.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);
