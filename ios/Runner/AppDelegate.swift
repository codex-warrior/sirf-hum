import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Platform key store for the crypto core (D-066). App-owned channel,
    // not a third-party plugin (KEY-MANAGEMENT.md §3, option a).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SirfHumSecureKeyStore") {
      SecureKeyStore.register(with: registrar.messenger())
    }
  }
}
