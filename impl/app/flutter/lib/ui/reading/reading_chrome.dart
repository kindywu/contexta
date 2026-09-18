import 'package:flutter/material.dart';

import '../../core/components/app_button.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import 'reading_controller.dart';

/// 阅读页共享 chrome：底部播放条 + 查词弹窗内容。
///
/// 从 reading_screen.dart 机械搬出——手机阅读页与 pad 阅读页共用同一份，
/// 搬移不改任何渲染细节（现有 reading_screen 测试即回归闸）。

/// 底部播放条：44dp 圆形播放/停止 + 状态文字 + 语速胶囊（对照 Kotlin
/// ReadingPlayerBar）。常驻于正文下方。
class ReadingPlayerBar extends StatelessWidget {
  const ReadingPlayerBar({
    super.key,
    required this.isSpeaking,
    required this.ttsSpeed,
    required this.speechProgress,
    required this.speechTotalSentences,
    required this.onTogglePlayback,
    required this.onToggleTtsSpeed,
  });

  final bool isSpeaking;
  final double ttsSpeed;
  final double? speechProgress;
  final int? speechTotalSentences;
  final VoidCallback onTogglePlayback;
  final VoidCallback onToggleTtsSpeed;

  @override
  Widget build(BuildContext context) {
    final slow = ttsSpeed < 1.0;
    return Container(
      color: AppColors.surfaceCard,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          // 圆形播放/停止按钮
          Material(
            color: AppColors.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                debugPrint('[UI] ReadingPlayerBar onTap PLAY/STOP');
                onTogglePlayback();
              },
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  isSpeaking ? Icons.stop : Icons.play_arrow,
                  color: AppColors.onPrimary,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (speechProgress != null && speechTotalSentences != null)
            Text(
              '第 ${speechProgress!.toStringAsFixed(0)}/$speechTotalSentences 句',
              style: AppType.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            )
          else
            Text(
              isSpeaking ? '正在朗读…' : '朗读全文',
              style: AppType.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: isSpeaking ? AppColors.primary : AppColors.bodyText,
              ),
            ),
          const Spacer(),
          // 语速胶囊（选中态 Primary 底 OnPrimary 文字）
          Material(
            color: slow ? AppColors.surfaceSoft : AppColors.primary,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: onToggleTtsSpeed,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  _speedLabel(ttsSpeed),
                  style: AppType.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: slow ? AppColors.mutedSoft : AppColors.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 语速显示标签：0.8x / 1x / 1.2x（去掉多余的小数位）。
  String _speedLabel(double speed) {
    if (speed == 0.8) return '0.8x';
    if (speed == 1.2) return '1.2x';
    return '1x';
  }
}

/// 查词弹窗内容（对照 Kotlin WordModalOverlay）：
/// 关闭 X → 词头 26sp serif + 发音钮 → 音标 → loading / 按词性分组义项 →
/// '加入生词表' / '从生词表移除' 全宽按钮。
class WordSheetBody extends StatelessWidget {
  const WordSheetBody({
    super.key,
    required this.data,
    required this.onDismiss,
    required this.onPlayWord,
    required this.onAddToVocabulary,
    required this.onRemoveFromVocabulary,
  });

  final WordSheetData? data;
  final VoidCallback onDismiss;
  final VoidCallback onPlayWord;
  final VoidCallback onAddToVocabulary;
  final VoidCallback onRemoveFromVocabulary;

  @override
  Widget build(BuildContext context) {
    // 关闭 X 固定置顶（不随内容滚动）；义项/按钮区包可滚动容器——
    // 内容总高超过 AppModal 的 85% 屏高上限（底部弹层）时可滚动查看。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 关闭 X — 右上（固定头部，不随滚动）
        SizedBox(
          width: double.infinity,
          child: Align(
            alignment: Alignment.topRight,
            child: AppIconButton(
              icon: Icons.close,
              tooltip: '关闭',
              onClick: onDismiss,
              size: 32,
              tint: AppColors.mutedSoft,
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data != null) ...[
                  // 词头 + 发音
                  Row(
                    children: [
                      Text(
                        data!.word,
                        style: AppType.textTheme.headlineLarge?.copyWith(
                          fontSize: 26,
                        ),
                      ),
                      const Spacer(),
                      if (!data!.isLoading)
                        AppIconButton(
                          icon: Icons.volume_up_outlined,
                          tooltip: '发音',
                          onClick: onPlayWord,
                          size: 36,
                          tint: AppColors.primary,
                        ),
                    ],
                  ),
                  if (data!.phonetic != null && !data!.isLoading)
                    Text(
                      data!.phonetic!,
                      style: AppType.phonetic.copyWith(fontSize: 13),
                    ),
                  // 词形解析标注：homes 是 home 的复数形式
                  if (data!.inflectionNote != null && !data!.isLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        data!.inflectionNote!,
                        style: AppType.textTheme.bodySmall?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                  if (data!.isLoading) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '正在查询…',
                          style: AppType.textTheme.bodyMedium?.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ] else if (data!.senses.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    // 按词性分组：词性标签（珊瑚）只在组首出现
                    for (final (index, sense) in data!.senses.indexed) ...[
                      if (index == 0 ||
                          sense.partOfSpeech !=
                              data!.senses[index - 1].partOfSpeech) ...[
                        const SizedBox(height: 16),
                        Text(
                          sense.partOfSpeech,
                          style: AppType.textTheme.labelMedium?.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ] else ...[
                        const SizedBox(height: 8),
                      ],
                      Text(
                        sense.englishDefinition,
                        style: AppType.textTheme.bodySmall?.copyWith(
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sense.chineseMeaning,
                        style: AppType.textTheme.bodySmall?.copyWith(
                          color: AppColors.mutedSoft,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  // 全宽操作按钮（已入生词本 → 移除，否则 → 加入）
                  SizedBox(
                    width: double.infinity,
                    child: data!.isInVocabulary
                        ? AppButton(
                            text: '从生词表移除',
                            onClick: onRemoveFromVocabulary,
                            variant: AppButtonVariant.secondary,
                          )
                        : AppButton(text: '加入生词表', onClick: onAddToVocabulary),
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
