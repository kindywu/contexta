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
  }
}
