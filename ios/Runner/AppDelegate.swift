import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS only shows a notification raised while the app is open if the
    // notification center has a delegate that says to. FlutterAppDelegate is
    // one, and hands the callbacks to flutter_local_notifications; without
    // this line nothing the app raises appears, and taps aren't delivered.
    UNUserNotificationCenter.current().delegate =
      self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerSocialShare(engineBridge.pluginRegistry)
  }

  /// Opens Instagram's Story editor with a picture already in it, which
  /// share_plus can't do. The picture goes on the pasteboard and the
  /// `instagram-stories` URL is opened; the result is false when Instagram
  /// isn't installed, so Dart can fall back to the system share sheet.
  /// `open` reports that on its own, so no LSApplicationQueriesSchemes entry
  /// (and no Info.plist change) is needed.
  private func registerSocialShare(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "SocialShare") else { return }
    let channel = FlutterMethodChannel(
      name: "id.pokepedia.app/social_share",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "instagramStory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let path = args["path"] as? String,
        let appId = args["appId"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "path and appId required", details: nil))
        return
      }
      guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        result(FlutterError(code: "no_file", message: "share image unreadable", details: path))
        return
      }
      // Built with URLComponents so the App ID is encoded, not pasted in.
      var components = URLComponents()
      components.scheme = "instagram-stories"
      components.host = "share"
      components.queryItems = [URLQueryItem(name: "source_application", value: appId)]
      guard let url = components.url else {
        result(FlutterError(code: "bad_url", message: "could not build the Story URL", details: nil))
        return
      }
      let key = "com.instagram.sharedSticker.backgroundImage"
      // Instagram reads the picture off the pasteboard. Local only, so it
      // doesn't sync to the user's other devices, and gone after 5 minutes.
      UIPasteboard.general.setItems(
        [[key: data]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)]
      )
      UIApplication.shared.open(url, options: [:]) { opened in
        // Not installed: don't leave the user's clipboard holding our image.
        if !opened, UIPasteboard.general.contains(pasteboardTypes: [key]) {
          UIPasteboard.general.items = []
        }
        result(opened)
      }
    }
  }
}
