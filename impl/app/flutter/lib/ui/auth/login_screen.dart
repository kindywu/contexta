import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/components/app_button.dart';
import '../../core/navigation/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import '../../data/auth/auth_service.dart';
import '../../di/providers.dart';

/// 登录页（手机号免密登录）。
///
/// - 主按钮「本机号码快速登录」：读本机号码（MethodChannel），成功自动登录；
///   读不到（无权限 / Android 26+ 多数设备限制）→ 展开手动输入框；
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

  /// 快速登录读不到号码时展开手动输入。
  bool _manualMode = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // 被踢下线 / 封禁进入本页时给一次性提示
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final status = ref.read(authServiceProvider).status;
      if (status == AuthStatus.evicted) {
        _snack('登录已失效，请重新登录');
      } else if (status == AuthStatus.banned) {
        _snack('账号已被封禁，无法登录');
      }
    });
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

  Future<void> _login(String phone) async {
    final result =
        await ref.read(authServiceProvider.notifier).loginWithPhone(phone);
    if (!mounted) return;
    setState(() => _loading = false);
    switch (result) {
      case AuthResult.success:
        // 无需手动导航：守卫（refreshListenable）按 from 参数自动回跳来源页
        break;
      case AuthResult.banned:
        _snack('账号已被封禁，无法登录');
      case AuthResult.networkError:
        _snack('网络不可用，请检查网络后重试');
      case AuthResult.serverError:
        _snack('登录失败，请稍后重试');
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

    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: ListView(
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
          if (_manualMode) ...[
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
    );
  }
}
