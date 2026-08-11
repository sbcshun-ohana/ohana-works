import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 保険: 起動時にもAPNs登録を明示発火(主経路は Dart の ohana/push チャネル)。
    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Dartのリトライから毎回 registerForRemoteNotifications を発火できるチャネル。
    // このハンドラは Firebase.initializeApp(Dart main) 後に呼ばれるため、
    // 到着したトークンは確実に FIRMessaging へ橋渡しされる。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OhanaPushChannel") {
      let channel = FlutterMethodChannel(name: "ohana/push", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "registerForRemoteNotifications" {
          DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  // 診断: APNsトークン取得成功。super で FlutterAppDelegate→firebase_messaging へ橋渡し。
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    print("[push][apns] didRegister OK len=\(deviceToken.count) token=\(hex.prefix(16))…")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // 診断: APNs登録失敗の理由(出れば capability/プロビジョニング/ネットワーク要因の切り分けに使える)。
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[push][apns] didFail error=\(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
