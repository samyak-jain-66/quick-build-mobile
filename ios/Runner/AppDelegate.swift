import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Mirrors what manifestPlaceholders["MAPS_API_KEY"] does for Android.
    // Hardcoded for now; lift into Info.plist + xcconfig when iOS gets its
    // own restricted client key.
    GMSServices.provideAPIKey("AIzaSyApgJd_IS-z0xUM103CIdCCHZWHd9Bz6O4")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
