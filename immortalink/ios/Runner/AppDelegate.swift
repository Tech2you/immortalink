import Flutter
import UIKit
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var subscriptionChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "EverRootsSubscriptions") {
      let channel = FlutterMethodChannel(
        name: "com.everroots.app/subscriptions",
        binaryMessenger: registrar.messenger()
      )
      subscriptionChannel = channel
      channel.setMethodCallHandler { call, result in
        guard call.method == "manageSubscriptions" else {
          result(FlutterMethodNotImplemented)
          return
        }
        if #available(iOS 15.0, *) {
          Task { @MainActor in
            guard let scene = UIApplication.shared.connectedScenes
              .compactMap({ $0 as? UIWindowScene })
              .first(where: { $0.activationState == .foregroundActive }) else {
              result(FlutterError(code: "NO_SCENE", message: "No active window", details: nil))
              return
            }
            do {
              try await AppStore.showManageSubscriptions(in: scene)
              result(nil)
            } catch {
              result(FlutterError(code: "MANAGE_FAILED", message: "Could not open subscriptions", details: nil))
            }
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
