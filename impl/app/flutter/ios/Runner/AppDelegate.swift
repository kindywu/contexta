import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 后台每日同步（workmanager → BGTaskScheduler）的启动期注册。
    //
    // BGTaskScheduler 有两条硬性要求：提交任务请求前该标识必须已有注册的
    // launch handler（否则 iOS 直接断言崩溃：_handleSubmissionWithoutRegistration），
    // 且 handler 必须在 didFinishLaunching 返回前注册。而插件的 Dart 侧
    // `registerPeriodicTask` 是「先 submit 再 register」，UIScene 生命周期下
    // 插件注册又晚于 didFinishLaunching，因此必须在这里显式先注册一次。
    //
    // 标识串三处必须一致：此处、Info.plist 的 BGTaskSchedulerPermittedIdentifiers、
    // lib/data/background/sync_callback_dispatcher.dart 的 dailySyncTaskName。
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "dailyArticleSync",
      earliestBeginInSeconds: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // 应用级 MethodChannel（对齐 Android 侧 MainActivity 的 "contexta/native"）：
    // 当前仅提供机型名（登录时上报 device_name，多设备提示用）。
    let channel = FlutterMethodChannel(
      name: "contexta/native",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getDeviceLabel":
        result(self.deviceLabel())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 设备机型展示名：utsname.machine（如 "iPhone15,2"）→ 常见机型营销名；
  /// 未收录机型回退 machine 原码（不阻断）。
  private func deviceLabel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
    return Self.marketingNames[machine] ?? machine
  }

  /// 常见 iPhone / iPad 机型映射（新机型未收录时显示 machine 原码，可在后续补充）。
  private static let marketingNames: [String: String] = [
    "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max",
    "iPhone11,8": "iPhone XR",
    "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
    "iPhone12,8": "iPhone SE (2nd)", "iPhone14,6": "iPhone SE (3rd)",
    "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12",
    "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
    "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
    "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
    "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
    "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
    "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
    "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
    "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
    "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
    "iPad7,11": "iPad (7th)", "iPad7,12": "iPad (7th)",
    "iPad11,1": "iPad mini (5th)", "iPad11,2": "iPad mini (5th)",
    "iPad11,3": "iPad Air (3rd)", "iPad11,4": "iPad Air (3rd)",
    "iPad12,1": "iPad (9th)", "iPad12,2": "iPad (9th)",
    "iPad13,1": "iPad Air (4th)", "iPad13,2": "iPad Air (4th)",
    "iPad13,4": "iPad Pro 11-inch (3rd)", "iPad13,5": "iPad Pro 11-inch (3rd)",
    "iPad13,6": "iPad Pro 11-inch (3rd)", "iPad13,7": "iPad Pro 11-inch (3rd)",
    "iPad13,8": "iPad Pro 12.9-inch (5th)", "iPad13,9": "iPad Pro 12.9-inch (5th)",
    "iPad13,10": "iPad Pro 12.9-inch (5th)", "iPad13,11": "iPad Pro 12.9-inch (5th)",
    "iPad13,16": "iPad Air (5th)", "iPad13,17": "iPad Air (5th)",
    "iPad14,1": "iPad mini (6th)", "iPad14,2": "iPad mini (6th)",
    "iPad14,3": "iPad Pro 11-inch (4th)", "iPad14,4": "iPad Pro 11-inch (4th)",
    "iPad14,5": "iPad Pro 12.9-inch (6th)", "iPad14,6": "iPad Pro 12.9-inch (6th)",
    "iPad14,8": "iPad Air 11-inch (M2)", "iPad14,9": "iPad Air 11-inch (M2)",
    "iPad14,10": "iPad Air 13-inch (M2)", "iPad14,11": "iPad Air 13-inch (M2)",
    "iPad16,1": "iPad mini (7th)", "iPad16,2": "iPad mini (7th)",
    "iPad16,3": "iPad Pro 11-inch (M4)", "iPad16,4": "iPad Pro 11-inch (M4)",
    "iPad16,5": "iPad Pro 13-inch (M4)", "iPad16,6": "iPad Pro 13-inch (M4)",
  ]
}
