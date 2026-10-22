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
        if call.method == "latestSubscriptionTransaction" {
          guard #available(iOS 15.0, *), let productIds = call.arguments as? [String] else {
            result(FlutterMethodNotImplemented)
            return
          }
          Task { @MainActor in
            var latest: (transaction: StoreKit.Transaction, signed: String)?
            for await verification in StoreKit.Transaction.all {
              guard case .verified(let transaction) = verification,
                    productIds.contains(transaction.productID) else { continue }
              if latest == nil || transaction.purchaseDate > latest!.transaction.purchaseDate {
                latest = (transaction, verification.jwsRepresentation)
              }
            }
            guard let latest else {
              result(nil)
              return
            }
            result([
              "id": String(latest.transaction.id),
              "productId": latest.transaction.productID,
              "purchaseDate": String(Int64(latest.transaction.purchaseDate.timeIntervalSince1970 * 1000)),
              "receiptData": latest.signed,
              "jsonRepresentation": String(data: latest.transaction.jsonRepresentation, encoding: .utf8) ?? "",
              "appAccountToken": latest.transaction.appAccountToken?.uuidString as Any? ?? NSNull()
            ])
          }
          return
        }
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
