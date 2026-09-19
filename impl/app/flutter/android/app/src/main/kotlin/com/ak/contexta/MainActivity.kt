package com.ak.contexta

import android.Manifest
import android.content.pm.PackageManager
import android.telephony.TelephonyManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "contexta/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLine1Number" -> result.success(readLine1Number())
                    "getDeviceLabel" -> result.success(readDeviceLabel())
                    else -> result.notImplemented()
                }
            }
    }

    /// 读取本机号码（telephonyManager.line1Number）。
    ///
    /// 已知限制（README / 登录主题文档）：
    /// - 未授予 READ_PHONE_STATE（无运行时请求，走手动输入）→ null；
    /// - Android 26+ 多数设备（双卡 / 运营商限制）line1Number 恒为 null，
    ///   属平台已知限制，同样回退手动输入。
    /// - 权限在应用信息页仍可能被撤销，SecurityException 兜底 null。
    private fun readLine1Number(): String? {
        if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }
        val tm = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager ?: return null
        return try {
            tm.line1Number?.takeIf { it.isNotBlank() }
        } catch (_: SecurityException) {
            null
        }
    }

    /// 设备机型展示名（如 "Xiaomi 14"、"OPPO PGP110"）。
    /// 厂商名首字母大写；机型号已含厂商名时（如 "Xiaomi 2201123G"）不重复拼接。
    private fun readDeviceLabel(): String {
        val manufacturer = android.os.Build.MANUFACTURER
            .replaceFirstChar { it.uppercase() }
        val model = android.os.Build.MODEL
        return if (model.startsWith(manufacturer, ignoreCase = true)) {
            model
        } else {
            "$manufacturer $model"
        }
    }
}
