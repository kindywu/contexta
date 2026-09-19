import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 被踢提示宿主：监听 AuthService 的待展示通知，弹一次性 AppModal。
///
/// 挂载点：MainApp 的 `MaterialApp.router(builder:)` —— 覆盖手机/平板两棵树
/// 与全部路由（含全屏阅读页、登录页）。无服务端配置时直接透传 child。
///
/// 导航注意：宿主挂在 `builder:` 上，位于 Router **之上**（WidgetsApp 把
/// builder 包在 Router 外层），因此 `GoRouter.of(context)` / `context.push`
/// 在宿主里找不到 InheritedGoRouter（实测抛「No GoRouter found in context」）。
/// 故跳转走 [routerProvider] 持有的 GoRouter 实例——与 routerConfig 同一实例。
class EvictionNoticeHost extends ConsumerWidget {
  const EvictionNoticeHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(serverConfiguredProvider)) return child;
    final notice = ref.watch(authServiceProvider).evictionNotice;
    return Stack(
      children: [
        child,
        if (notice != null)
          AppModal(
            visible: true,
            onDismiss: () =>
                ref.read(authServiceProvider.notifier).consumeEvictionNotice(),
            child: EvictionNoticePanel(
              notice: notice,
              onDismiss: () =>
                  ref.read(authServiceProvider.notifier).consumeEvictionNotice(),
              onRelogin: () {
                ref.read(authServiceProvider.notifier).consumeEvictionNotice();
                ref.read(routerProvider).push(Routes.login);
              },
            ),
          ),
      ],
    );
  }
}

/// 被踢提示内容（纯展示，测试直接构造 notice 渲染）。
class EvictionNoticePanel extends StatelessWidget {
  const EvictionNoticePanel({
    super.key,
    required this.notice,
    required this.onDismiss,
    required this.onRelogin,
  });

  final EvictionNotice notice;
  final VoidCallback onDismiss;
  final VoidCallback onRelogin;

  @override
  Widget build(BuildContext context) {
    final by = notice.by;
    final isRelogin = notice.reason == EvictionReason.relogin;
    final title = isRelogin ? '本机已重新登录' : '账号已在其他设备登录';
    final body = by == null
        ? '登录状态已失效，请重新登录。'
        : isRelogin
            ? '本机登录状态于 ${formatNoticeTime(notice.endedAtMillis)} 失效'
                '（本机重新登录）。'
            : '《${deviceLabel(by.deviceName, by.deviceId)}》于 '
                '${formatNoticeTime(notice.endedAtMillis)} 登录，本机已退出登录。';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppType.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(body, style: AppType.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(foregroundColor: AppColors.muted),
              child: const Text('知道了'),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(text: '重新登录', onClick: onRelogin),
          ],
        ),
      ],
    );
  }
}
