import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sharing straight to one app, which `share_plus` can't target. Every call
/// answers `false` when it couldn't (app not installed, no Meta App ID, wrong
/// platform), so the caller falls back to the system share sheet.
///
/// Native side: `MainActivity.kt` and `AppDelegate.swift`.
class SocialShare {
  const SocialShare._();

  static const _channel = MethodChannel('id.pokepedia.app/social_share');

  /// Instagram's Story editor needs a Meta App ID, which the app doesn't have
  /// yet, so this always falls back to the share sheet.
  // shortcut: no Meta App ID; pass `{'path': path, 'appId': <id>}` to the
  // native `instagramStory` handler (AppDelegate/MainActivity) once one exists.
  static Future<bool> instagramStory(String path) async => false;

  /// Opens WhatsApp's picker with the PNG at [path] and [text] together.
  /// Android only: iOS has no route for image plus text into WhatsApp other
  /// than the share sheet.
  static Future<bool> whatsapp(String path, String text) async {
    if (!Platform.isAndroid) return false;
    return _call('whatsapp', {'path': path, 'text': text});
  }

  /// A native side that never answers would hold the share button busy
  /// forever; past this it falls back like any other failure.
  static const _timeout = Duration(seconds: 10);

  static Future<bool> _call(String method, Map<String, Object?> args) async {
    try {
      return await _channel
              .invokeMethod<bool>(method, args)
              .timeout(_timeout) ??
          false;
    } on PlatformException catch (e) {
      // A real failure (unreadable file, bad URI), not "not installed".
      debugPrint('[social_share] $method failed: $e');
      return false;
    } on MissingPluginException catch (e) {
      // The channel isn't registered: every share would quietly fall back.
      debugPrint('[social_share] $method has no native handler: $e');
      return false;
    } on TimeoutException {
      debugPrint('[social_share] $method timed out');
      return false;
    }
  }
}
