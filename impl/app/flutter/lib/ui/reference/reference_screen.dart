import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/components/app_button.dart';
import '../../core/components/app_modal.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_type.dart';
import 'reference_controller.dart';
import 'reference_data.dart';

/// Reference 页（对照 Kotlin ReferenceScreen.kt）：
/// - 三个 inline underline tabs：字母表 / 音标 / 语法
/// - 字母表：26 字母 4 列网格（字母 + 音标），点击弹详情
/// - 音标：分组 SectionHeader（Primary 竖条 + 标题）+ 3 列网格
/// - 语法：可折叠分组（▸/▾）+ 语法卡片（名称/规则/中文/例句引文）
/// - 格子弹窗：大字（56sp）点击发音 + 音标/例词 + 「发音」按钮
class ReferenceScreen extends ConsumerStatefulWidget {
  const ReferenceScreen({super.key});

  @override
  ConsumerState<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends ConsumerState<ReferenceScreen> {
  int _selectedTab = 0;
  ReferenceCellData? _selectedCell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _ReferenceTabs(
                selected: _selectedTab,
                onSelect: (index) => setState(() => _selectedTab = index),
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: switch (_selectedTab) {
                    0 => _AlphabetContent(
                        onCellClick: (cell) => setState(() => _selectedCell = cell),
                      ),
                    1 => _PhonicsContent(
                        onCellClick: (cell) => setState(() => _selectedCell = cell),
                      ),
                    _ => const _GrammarContent(),
                  },
                ),
              ),
            ],
          ),
          if (_selectedCell != null)
            _ReferenceCellModal(
              cell: _selectedCell!,
              onDismiss: () => setState(() => _selectedCell = null),
            ),
        ],
      ),
    );
  }
}

/// Inline underline tabs（对照 Kotlin ReferenceScreen 的 Tabs 段；
/// 与 Settings 页 _InlineTabs 同款样式）。
class _ReferenceTabs extends StatelessWidget {
  const _ReferenceTabs({required this.selected, required this.onSelect});

  static const _labels = ['字母表', '音标', '语法'];

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppPage.horizontalPadding),
      child: Row(
        children: [
          for (final (index, label) in _labels.indexed)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(index),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppType.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: index == selected
                            ? AppColors.primary
                            : AppColors.mutedSoft,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 2,
                      color: index == selected
                          ? AppColors.primary
                          : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 字母表内容：26 字母 4 列网格（对照 Kotlin AlphabetContent）。
class _AlphabetContent extends StatelessWidget {
  const _AlphabetContent({required this.onCellClick});

  final ValueChanged<ReferenceCellData> onCellClick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _chunked(alphabetData, 4)) ...[
          Row(
            children: [
              for (final item in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _GridCard(
                      child: Column(
                        children: [
                          Text(
                            item.char,
                            style: AppType.textTheme.titleMedium
                                ?.copyWith(color: AppColors.ink),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.phone,
                            style: AppType.phonetic.copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                      onClick: () => onCellClick(ReferenceCellData(
                        char: item.char,
                        reading: item.phone,
                        example: item.example,
                        exampleCn: item.cn,
                        isPhonetic: false,
                      )),
                    ),
                  ),
                ),
              for (var i = row.length; i < 4; i++)
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

/// 音标内容：分组 SectionHeader + 3 列网格（对照 Kotlin PhonicsContent）。
class _PhonicsContent extends StatelessWidget {
  const _PhonicsContent({required this.onCellClick});

  final ValueChanged<ReferenceCellData> onCellClick;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final group in phonicsGroups) ...[
          _SectionHeader(title: group.name),
          for (final row in _chunked(group.items, 3)) ...[
            Row(
              children: [
                for (final item in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: _GridCard(
                        child: Column(
                          children: [
                            Text(
                              item.phone,
                              style: AppType.phonetic.copyWith(fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.example,
                              style: AppType.textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.bodyText),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              item.full,
                              style: AppType.textTheme.labelSmall
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                        onClick: () => onCellClick(ReferenceCellData(
                          char: item.phone,
                          reading: group.name,
                          example: item.example,
                          exampleCn: '',
                          isPhonetic: true,
                        )),
                      ),
                    ),
                  ),
                for (var i = row.length; i < 3; i++)
                  const Expanded(child: SizedBox()),
              ],
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

/// 分组标题：Primary 3dp 竖条 + 标题 + 计数（对照 Kotlin SectionHeader）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            title,
            style: AppType.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 网格卡片：SurfaceCard 底 + 8dp 圆角（对照 Kotlin AlphabetGridCard /
/// PhonicsGridCard）。
class _GridCard extends StatelessWidget {
  const _GridCard({required this.child, required this.onClick});

  final Widget child;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onClick,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 10,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 语法内容：可折叠分组（对照 Kotlin GrammarContent）。
class _GrammarContent extends StatefulWidget {
  const _GrammarContent();

  @override
  State<_GrammarContent> createState() => _GrammarContentState();
}

class _GrammarContentState extends State<_GrammarContent> {
  /// 默认展开第一组（对照 Kotlin remember { mutableStateOf(setOf(0)) }）。
  final Set<int> _expandedGroups = {0};

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (index, group) in grammarGroups.indexed) ...[
          _GrammarGroupHeader(
            name: group.name,
            count: group.items.length,
            expanded: _expandedGroups.contains(index),
            onClick: () => setState(() {
              if (!_expandedGroups.add(index)) {
                _expandedGroups.remove(index);
              }
            }),
          ),
          if (_expandedGroups.contains(index))
            for (final item in group.items) ...[
              _GrammarCard(item: item),
              const SizedBox(height: AppSpacing.xs),
            ],
        ],
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

/// 语法分组头：竖条 + 名称 + (计数) + ▸/▾（对照 Kotlin GrammarGroupHeader）。
class _GrammarGroupHeader extends StatelessWidget {
  const _GrammarGroupHeader({
    required this.name,
    required this.count,
    required this.expanded,
    required this.onClick,
  });

  final String name;
  final int count;
  final bool expanded;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onClick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              name,
              style: AppType.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: AppType.textTheme.labelMedium
                  ?.copyWith(color: AppColors.mutedSoft),
            ),
            const Spacer(),
            Text(
              expanded ? '▾' : '▸',
              style: AppType.textTheme.titleSmall
                  ?.copyWith(color: AppColors.mutedSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// 语法卡片：名称 + 规则 + 中文说明 + 例句引文（对照 Kotlin GrammarCard）。
class _GrammarCard extends StatelessWidget {
  const _GrammarCard({required this.item});

  final GrammarItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            item.name,
            style: AppType.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.explanation,
            style: AppType.textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
          Text(
            item.chineseExplanation,
            style: AppType.textTheme.bodySmall?.copyWith(color: AppColors.bodyText),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final (index, example) in item.examples.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.xs),
            // IntrinsicHeight + stretch：让竖条撑满整行（等价 Kotlin
            // IntrinsicSize.Min 的竖条引文）
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          example.$1,
                          style: AppType.textTheme.bodySmall
                              ?.copyWith(color: AppColors.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          example.$2,
                          style: AppType.textTheme.labelSmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 格子弹窗：56sp 大字（点击发音）+ 音标/分类 + 例词 + 发音按钮
/// （对照 Kotlin AppModal 内容）。
class _ReferenceCellModal extends ConsumerWidget {
  const _ReferenceCellModal({required this.cell, required this.onDismiss});

  final ReferenceCellData cell;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(referenceControllerProvider);
    return AppModal(
      visible: true,
      onDismiss: onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: AppIconButton(
              icon: Icons.close,
              tooltip: '关闭',
              onClick: onDismiss,
              size: 32,
              tint: AppColors.mutedSoft,
            ),
          ),
          // 56sp serif 大字：点击朗读（字母读字母名，音标读自身拟音）
          InkWell(
            onTap: () => controller.speak(ownSoundFor(cell)),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                cell.char,
                textAlign: TextAlign.center,
                style: AppType.textTheme.displayLarge
                    ?.copyWith(fontSize: 56, height: 60 / 56),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // reading：字母 → 音标（珊瑚）；音标 → 分类名（Muted）
          Text(
            cell.reading,
            textAlign: TextAlign.center,
            style: cell.isPhonetic
                ? AppType.textTheme.bodyMedium?.copyWith(color: AppColors.muted)
                : AppType.phonetic.copyWith(fontSize: 15),
          ),
          const SizedBox(height: AppSpacing.sm),
          // 例词：大字 + 珊瑚 + 可点击发音
          InkWell(
            onTap: () => controller.speak(cell.example),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                cell.example,
                textAlign: TextAlign.center,
                style: AppType.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          if (cell.exampleCn.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              cell.exampleCn,
              textAlign: TextAlign.center,
              style: AppType.textTheme.labelSmall?.copyWith(color: AppColors.muted),
            ),
          ],
          const SizedBox(height: AppPage.minTouchTarget ~/ 2 - 2),
          AppButton(
            text: '发音',
            onClick: () => controller.speak(speakTextFor(cell)),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// 按 [size] 分块。
List<List<T>> _chunked<T>(List<T> list, int size) => [
      for (var i = 0; i < list.length; i += size)
        list.sublist(i, (i + size).clamp(0, list.length)),
    ];
