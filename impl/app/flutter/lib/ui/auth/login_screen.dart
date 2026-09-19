import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/components/app_button.dart';
import '../../core/components/app_modal.dart';
import '../../core/navigation/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import '../../core/time/notice_time.dart';
import '../../data/auth/auth_service.dart';
import '../../data/remote/dto/session_device_dto.dart';
import '../../di/providers.dart';

/// 登录页（手机号免密登录）。
///
/// - 主按钮「本机号码快速登录」（仅 Android）：读本机号码（MethodChannel），
///   成功自动登录；读不到（无权限 / Android 26+ 多数设备限制）→ 展开手动输入框；
/// - iOS 无本机号码 API（`NativePhoneReader.supportsLine1Number` = false）→
///   不显示快速登录按钮，直接展示手动输入框；
/// - 手动输入框 + 「登录」（11 位手机号校验）；
/// - 错误 SnackBar：BANNED / 网络失败 / 服务端错误文案；
/// - 服务端未配置（本地模式）：提示「服务端未配置」，禁用登录按钮；
/// - 成功：守卫按 redirect from 自动回跳来源页；手动 push 进入时 pop 返回。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();

  /// 快速登录读不到号码时展开手动输入（平台不支持读本机号码时——iOS——
  /// 由 build 里的 `!phoneSupported` 直接进手动模式，不依赖这个标志）。
  bool _manualMode = false;
  bool _loading = false;

  /// 确认框目标设备（非 null → 渲染 AppModal）。
  SessionDevice? _evictTarget;
  Completer<bool>? _confirmCompleter;

  @override
  void initState() {
    super.initState();
    // 注：被踢/封禁的一次性提示已移除——守卫遇到 kicked 状态即清为
    // loggedOut（refreshListenable 重估，先于任何页面挂载），本页无法
    // 再观察到 evicted/banned；封禁提示由登录请求的 BANNED 结果承载。
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 主按钮：读本机号码 → 自动登录；读不到 → 手动输入。
  Future<void> _quickLogin() async {
    setState(() => _loading = true);
    final phone = await ref.read(nativePhoneReaderProvider).readLine1Number();
    if (!mounted) return;
    if (phone == null || phone.isEmpty) {
      // 读不到本机号码（无权限 / 平台限制）→ 展开手动输入
      setState(() {
        _loading = false;
        _manualMode = true;
      });
      return;
    }
    _phoneController.text = phone;
    await _login(phone);
  }

  /// 弹「将有一台设备退出登录」确认框，返回用户是否确认。
  Future<bool> _confirmEviction(SessionDevice device) {
    final completer = Completer<bool>();
    _confirmCompleter = completer;
    setState(() => _evictTarget = device);
    return completer.future;
  }

  void _resolveConfirm(bool confirmed) {
    _confirmCompleter?.complete(confirmed);
    _confirmCompleter = null;
    setState(() => _evictTarget = null);
  }

  Future<void> _login(String phone) async {
    setState(() => _loading = true);
    final service = ref.read(authServiceProvider.notifier);

    // ① 预览：会挤掉谁（fail-closed：预览失败不登录）
    final impact = await service.checkLoginImpact(phone);
    if (!mounted) return;
    switch (impact.kind) {
      case LoginImpactKind.networkError:
        setState(() => _loading = false);
        _snack('网络不可用，请检查网络后重试');
        return;
      case LoginImpactKind.serverError:
        setState(() => _loading = false);
        _snack('登录失败，请稍后重试');
        return;
      case LoginImpactKind.willEvict:
        final target = impact.evicted.first;
        final confirmed = await _confirmEviction(target);
        if (!mounted) return;
        if (!confirmed) {
          setState(() => _loading = false);
          return; // 取消：不登录、不挤人
        }
      case LoginImpactKind.clear:
        break;
    }

    // ② 登录
    final outcome = await service.loginWithPhone(phone);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (outcome.result) {
      case AuthResult.success:
        // 并发差异：实际挤掉的与预览不同（预览为空却挤了人 / 挤的不是同一台）
        final actual = outcome.evicted;
        final previewedId =
            impact.evicted.isEmpty ? null : impact.evicted.first.deviceId;
        final mismatch = actual.isNotEmpty &&
            (actual.length != impact.evicted.length ||
                actual.first.deviceId != previewedId);
        if (mismatch) {
          _snack('已将《${deviceLabel(actual.first.deviceName, actual.first.deviceId)}》挤下线');
        }
        _navigateAfterLogin();
      case AuthResult.banned:
        _snack('账号已被封禁，无法登录');
      case AuthResult.networkError:
        _snack('网络不可用，请检查网络后重试');
      case AuthResult.serverError:
        _snack('登录失败，请稍后重试');
    }
  }

  /// 登录成功后的回跳。守卫的 refreshListenable 重定向对 push 进入的
  /// /login 不生效（go_router 17 行为），故本页显式导航；目标与守卫
  /// 分支一致（from 校验逻辑相同）：
  /// - 有效 from（非空、以 / 开头、非 /login）→ go(from)；
  /// - 否则可 pop（首页横幅 push 进入）→ pop 回来源；
  /// - 否则 → go(home)。
  void _navigateAfterLogin() {
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    final validFrom = from != null &&
        from.isNotEmpty &&
        from.startsWith('/') &&
        from != Routes.login;
    if (validFrom) {
      context.go(from);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  void _manualLogin() {
    final phone = _phoneController.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      _snack('请输入 11 位手机号');
      return;
    }
    _login(phone);
  }

  @override
  Widget build(BuildContext context) {
    final serverConfigured = ref.watch(serverConfiguredProvider);
    // 平台能力：仅 Android 能读本机号码（iOS 无系统 API）——不支持时不给
    // 「本机号码快速登录」按钮，直接展示手动输入框。
    final phoneSupported =
        ref.watch(nativePhoneReaderProvider).supportsLine1Number;
    final manualMode = _manualMode || !phoneSupported;

    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppPage.horizontalPadding,
              vertical: AppSpacing.xl,
            ),
            children: [
              Icon(Icons.smartphone_outlined,
                  size: 48, color: AppColors.primary),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '手机号免密登录',
                textAlign: TextAlign.center,
                style: AppType.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '登录后可同步文章与学习记录',
                textAlign: TextAlign.center,
                style: AppType.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (phoneSupported)
                AppButton(
                  text: _loading ? '登录中…' : '本机号码快速登录',
                  onClick: _quickLogin,
                  enabled: serverConfigured && !_loading,
                ),
              if (!serverConfigured) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  '服务端未配置，当前为本地模式',
                  textAlign: TextAlign.center,
                  style: AppType.textTheme.bodySmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ],
              if (manualMode) ...[
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  decoration: const InputDecoration(
                    labelText: '手机号',
                    hintText: '请输入 11 位手机号',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  text: _loading ? '登录中…' : '登录',
                  onClick: _manualLogin,
                  enabled: serverConfigured && !_loading,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => context.go(Routes.home),
                child: const Text('暂不登录，先逛逛'),
              ),
            ],
          ),
          if (_evictTarget != null)
            AppModal(
              visible: true,
              onDismiss: () => _resolveConfirm(false),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('将有一台设备退出登录', style: AppType.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '继续登录会把《${deviceLabel(_evictTarget!.deviceName, _evictTarget!.deviceId)}》'
                    '（该设备 ${formatNoticeTime(_evictTarget!.issuedAtMillis)} 登录）挤下线。',
                    style: AppType.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _resolveConfirm(false),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AppButton(
                        text: '继续登录',
                        onClick: () => _resolveConfirm(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
