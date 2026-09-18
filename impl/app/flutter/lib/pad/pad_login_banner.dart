import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_dimens.dart';
import '../core/theme/app_type.dart';

/// 平板首页的「未登录」状态带 + 登录入口。
///
/// 与手机首页的 `_LoginBanner` 是**两份实现**（两棵树不共享 UI）：那条嵌在
/// 手机滚动流顶部、按手机留白收窄；这条横跨平板内容区，是一条平铺的窄带。
///
/// 它不只是提示——平板上这是**唯一的登录入口**：设置页的账号区只在已登录时
/// 才渲染，登录页没有别的入口。少了它平板永远停在本地模式：每日同步不跑，
/// 首页永远只有安装时那批文章（2026-09-18 实测"首页没有读取今日文章"）。
class PadLoginBanner extends StatelessWidget {
  const PadLoginBanner({super.key, required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.person_outline,
              size: 18,
              color: AppColors.muted,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                '未登录 · 登录后可同步今日文章与学习记录',
                style: AppType.textTheme.bodyMedium?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ),
            TextButton(
              onPressed: onLogin,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size(64, AppPage.minTouchTarget),
              ),
              child: const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}
