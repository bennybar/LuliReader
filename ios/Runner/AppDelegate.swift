import Flutter
import UIKit

#if canImport(workmanager)
import workmanager
#elseif canImport(workmanager_apple)
import workmanager_apple
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let badgeChannel = FlutterMethodChannel(name: "lulireader.app/badge",
                                              binaryMessenger: controller.binaryMessenger)
    badgeChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "setBadge" {
        if let count = call.arguments as? Int {
          DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = count
            result(true)
          }
        } else {
          result(FlutterError(code: "INVALID_ARGUMENT",
                            message: "Badge count must be an integer",
                            details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    })
    
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: self)
    UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
