import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/components/app_badge.dart';
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
/// - 格子弹窗：符号 28sp + 例词 40sp 主角 + 例词音标（拼写行）+ 「发音」按钮
class ReferenceScreen extends ConsumerStatefulWidget {
  const ReferenceScreen({super.key});

  @override
  ConsumerState<ReferenceScreen> createState() => _ReferenceScreenState();
}

/// 「连播全部」的范围标识（分组连播用组名做标识）。
const String _allPhonicsKey = '__all__';

/// 字母表「连播全部 26 个字母」的范围标识。
const String _allLettersKey = '__all_letters__';

/// 弹层里「连播这 N 种读音」的范围标识（按字母各一个）。
String _letterSeqKey(String letter) => 'letter:$letter';

class _ReferenceScreenState extends ConsumerState<ReferenceScreen> {
  int _selectedTab = 0;
  ReferenceCellData? _selectedCell;

  /// 正在连播的范围（`_allPhonicsKey` / 音标分组名 / `_allLettersKey` /
  /// `_letterSeqKey`），null = 没在播。
  String? _playingKey;

  /// 当前正在读的格子（高亮用）：音标格 = 符号，字母格 = 'A a'。
  String? _activeCell;

  /// 弹层里当前正在读的那行读音（音标符号），null = 没在读。
  String? _activeSound;

  /// 连播轮次令牌：停止 / 改播别的范围 / 离开页面都会 +1，
  /// 迟到的异步回调靠它丢弃（否则停止后还会把高亮滚回去）。
  int _playToken = 0;

  /// 音标格的 GlobalKey（连播时滚动到当前格用），按符号懒建。
  final Map<String, GlobalKey> _cellKeys = {};

  /// 控制器在 initState 里取一次：`dispose` 里不能再碰 `ref`
  /// （riverpod 会抛「Cannot use "ref" after the widget was disposed」）。
  late final ReferenceController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(referenceControllerProvider);
  }

  @override
  void dispose() {
    // 离开页面即停：否则切走/返回后整张表还在后台读下去
    unawaited(_controller.stopSequence());
    super.dispose();
  }

  void _openCell(ReferenceCellData cell) {
    if (_playingKey != null) _stopSequence(); // 弹窗与连播的声音不叠着响
    setState(() => _selectedCell = cell);
  }

  /// 关弹层：顺手掐掉弹层里可能正在跑的「连播这 N 种读音」。
  void _closeCell() {
    if (_playingKey != null) _stopSequence();
    setState(() => _selectedCell = null);
  }

  void _selectTab(int index) {
    if (_playingKey != null) _stopSequence();
    setState(() => _selectedTab = index);
  }

  void _toggleSequence(String key, List<List<ReferenceCellData>> groups) {
    if (_playingKey == key) {
      _stopSequence();
      return;
    }
    unawaited(_startSequence(key, (token) => _controller.playSequence(
          groups,
          onCell: (cell) => _focusCell(token, cell.char),
        )));
  }

  /// 字母连播：`allLetterPlayGroups` = 整张字母表，`[letterPlayGroupOf('A')]` = 一个字母。
  void _toggleLetterSequence(String key, List<LetterPlayGroup> groups) {
    if (_playingKey == key) {
      _stopSequence();
      return;
    }
    unawaited(_startSequence(key, (token) => _controller.playLetterSequence(
          groups,
          onGroup: (group) => _focusCell(token, group.cellKey),
          onRow: (row) => _focusSound(token, row.phoneme),
        )));
  }

  /// 点读音行的**读音**（左边）：与连播的声音不叠着响。
  void _playSound(LetterSoundRow row) {
    if (_playingKey != null) _stopSequence();
    unawaited(_controller.playLetterSound(row));
  }

  /// 点读音行的**例词**（右边）。
  void _playExample(LetterSoundRow row) {
    if (_playingKey != null) _stopSequence();
    unawaited(_controller.playLetterExample(row));
  }

  /// 连播的通用骨架：置状态 → 播放（回调里按 [token] 聚焦当前格/行）→ 收尾复位。
  /// 令牌一变（停止 / 换一轮 / 离开页面），迟到的回调全部作废。
  Future<void> _startSequence(
    String key,
    Future<void> Function(int token) play,
  ) async {
    final token = ++_playToken;
    setState(() {
      _playingKey = key;
      _activeCell = null;
      _activeSound = null;
    });
    await play(token);
    if (!mounted || token != _playToken) return; // 已被停止 / 换了一轮
    setState(() {
      _playingKey = null;
      _activeCell = null;
      _activeSound = null;
    });
  }

  void _stopSequence() {
    _playToken++;
    unawaited(_controller.stopSequence());
    setState(() {
      _playingKey = null;
      _activeCell = null;
      _activeSound = null;
    });
  }

  /// 高亮当前格并滚到可见（垂直方向留一点上文，别把格子顶到屏幕边上）。
  void _focusCell(int token, String cellKey) {
    if (!mounted || token != _playToken) return;
    setState(() => _activeCell = cellKey);
    final cellContext = _cellKeys[cellKey]?.currentContext;
    if (cellContext != null) {
      Scrollable.ensureVisible(
        cellContext,
        alignment: 0.3,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  /// 高亮弹层里正在读的那行读音（字母名那一拍已过去，格子高亮随之让位）。
  void _focusSound(int token, String phoneme) {
    if (!mounted || token != _playToken) return;
    setState(() {
      _activeSound = phoneme;
      _activeCell = null;
    });
  }

  GlobalKey _cellKey(String phone) =>
      _cellKeys.putIfAbsent(phone, () => GlobalKey());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Column(
            children: [
              _ReferenceTabs(selected: _selectedTab, onSelect: _selectTab),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: switch (_selectedTab) {
                    0 => _AlphabetContent(
                        onCellClick: _openCell,
                        activeCell: _activeCell,
                        playingKey: _playingKey,
                        cellKey: _cellKey,
                        onToggleAll: () =>
                            _toggleLetterSequence(_allLettersKey, allLetterPlayGroups),
                      ),
                    1 => _PhonicsContent(
                        onCellClick: _openCell,
                        activeCell: _activeCell,
                        playingKey: _playingKey,
                        cellKey: _cellKey,
                        onToggleAll: () =>
                            _toggleSequence(_allPhonicsKey, allPhoneticGroups),
                        onToggleGroup: (group) => _toggleSequence(
                          group.name,
                          [phoneticCellsOf(group)],
                        ),
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
              activeSound: _activeSound,
              letterHighlighted: _activeCell == _selectedCell!.char,
              soundsPlaying:
                  _playingKey == _letterSeqKey(_selectedCell!.letterName),
              onPlaySound: _playSound,
              onPlayExample: _playExample,
              onToggleSounds: () => _toggleLetterSequence(
                _letterSeqKey(_selectedCell!.letterName),
                [letterPlayGroupOf(_selectedCell!.letterName)],
              ),
              onDismiss: _closeCell,
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

/// 字母表内容：连播工具栏 + 26 字母 4 列网格（对照 Kotlin AlphabetContent）。
class _AlphabetContent extends StatelessWidget {
  const _AlphabetContent({
    required this.onCellClick,
    required this.activeCell,
    required this.playingKey,
    required this.cellKey,
    required this.onToggleAll,
  });

  final ValueChanged<ReferenceCellData> onCellClick;

  /// 正在读的字母格（高亮）与正在播的范围（决定按钮显示「连播」还是「停止」）。
  final String? activeCell;
  final String? playingKey;

  final GlobalKey Function(String cellKey) cellKey;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 连播工具栏：26 个字母一次读完（逐格点开仍可单听读音行）
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '连播：依次读「字母名 → 读音 → 例词」',
                  style: AppType.textTheme.labelSmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ),
              AppButton(
                text: playingKey == _allLettersKey ? '停止' : '连播全部 26 个字母',
                variant: AppButtonVariant.secondary,
                onClick: onToggleAll,
              ),
            ],
          ),
        ),
        for (final row in _chunked(alphabetData, 4)) ...[
          Row(
            children: [
              for (final item in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: _GridCard(
                      key: cellKey(item.char),
                      highlighted: activeCell == item.char,
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
                          const SizedBox(height: 2),
                          Text(
                            '${item.soundCount} 种读音',
                            style: AppType.textTheme.labelSmall
                                ?.copyWith(color: AppColors.mutedSoft),
                          ),
                        ],
                      ),
                      onClick: () => onCellClick(alphabetCellOf(item)),
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

/// 音标内容：连播工具栏 + 分组 SectionHeader + 3 列网格（对照 Kotlin PhonicsContent）。
class _PhonicsContent extends StatelessWidget {
  const _PhonicsContent({
    required this.onCellClick,
    required this.activeCell,
    required this.playingKey,
    required this.cellKey,
    required this.onToggleAll,
    required this.onToggleGroup,
  });

  final ValueChanged<ReferenceCellData> onCellClick;

  /// 正在读的音标（高亮）与正在播的范围（决定按钮显示「连播」还是「停止」）。
  final String? activeCell;
  final String? playingKey;

  final GlobalKey Function(String phone) cellKey;
  final VoidCallback onToggleAll;
  final void Function(PhonicsGroup group) onToggleGroup;

  @override
  Widget build(BuildContext context) {
    final playingAll = playingKey == _allPhonicsKey;
    return Column(
      children: [
        // 连播工具栏：整表 48 个一次读完（逐格点「发音」仍是单格方式）
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '连播：依次读「音标 → 例词」',
                  style: AppType.textTheme.labelSmall
                      ?.copyWith(color: AppColors.muted),
                ),
              ),
              AppButton(
                text: playingAll ? '停止' : '连播全部 48 个',
                variant: AppButtonVariant.secondary,
                onClick: onToggleAll,
              ),
            ],
          ),
        ),
        for (final group in phonicsGroups) ...[
          // 分组标题带本组条目数；弹窗注脚只显示组名（见下 `reading: group.name`）——
          // 「这组有几个」放在标题上才读得通，挂在单个音标旁边会被当成这个音标的属性
          _SectionHeader(
            title: '${group.name} (${group.items.length})',
            trailing: AppIconButton(
              icon: playingKey == group.name ? Icons.stop : Icons.play_arrow,
              tooltip: playingKey == group.name ? '停止' : '连播「${group.name}」',
              onClick: () => onToggleGroup(group),
              size: 32,
              tint: playingKey == group.name
                  ? AppColors.primary
                  : AppColors.mutedSoft,
            ),
          ),
          for (final row in _chunked(group.items, 3)) ...[
            Row(
              children: [
                for (final item in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: _GridCard(
                        key: cellKey(item.phone),
                        highlighted: activeCell == item.phone,
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
                        onClick: () =>
                            onCellClick(phoneticCellOf(group, item)),
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
/// [trailing] 放行尾操作（音标分组用「连播这组」）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

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
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 网格卡片：SurfaceCard 底 + 8dp 圆角（对照 Kotlin AlphabetGridCard /
/// PhonicsGridCard）。[highlighted] = 连播正读到这一格，套一圈珊瑚描边。
class _GridCard extends StatelessWidget {
  const _GridCard({
    super.key,
    required this.child,
    required this.onClick,
    this.highlighted = false,
  });

  final Widget child;
  final VoidCallback onClick;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.sm);
    return Container(
      // 描边常驻（未高亮时透明）：高亮不该让卡片尺寸跳一下
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: highlighted ? AppColors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: radius,
        child: InkWell(
          onTap: onClick,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 10,
            ),
            child: child,
          ),
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

/// 格子弹窗（字母格 = 底部弹层，音标格 = 居中卡片）：
/// ① 顶部行 28sp 符号 + 小号注脚（字母 → 音标；音标 → 分类名）
/// ② 例词 40sp 主角（珊瑚，点击读词）③ 例词完整音标（拼写行）
/// ④ 例词中文（仅字母格有）⑤ 发音按钮（读「符号 + 例词」两段）
/// ⑥ 字母格另有「常见读音」列表（读音行点一下放音标录音 + 例词录音），见 [LetterSoundRow]。
class _ReferenceCellModal extends ConsumerWidget {
  const _ReferenceCellModal({
    required this.cell,
    required this.activeSound,
    required this.letterHighlighted,
    required this.soundsPlaying,
    required this.onPlaySound,
    required this.onPlayExample,
    required this.onToggleSounds,
    required this.onDismiss,
  });

  final ReferenceCellData cell;

  /// 正在读的那行读音（音标符号），null = 没在读。
  final String? activeSound;

  /// 正在读这个字母的**字母名**（连播开头那一下），高亮弹层里的字母。
  final bool letterHighlighted;

  /// 这个字母的「连播这 N 种读音」是否在跑。
  final bool soundsPlaying;

  final ValueChanged<LetterSoundRow> onPlaySound;
  final ValueChanged<LetterSoundRow> onPlayExample;
  final VoidCallback onToggleSounds;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(referenceControllerProvider);
    final header = _header(controller);
    final closeRow = Align(
      alignment: Alignment.centerRight,
      child: AppIconButton(
        icon: Icons.close,
        tooltip: '关闭',
        onClick: onDismiss,
        size: 32,
        tint: AppColors.mutedSoft,
      ),
    );

    // 音标格：内容短，仍是居中卡片
    if (cell.isPhonetic) {
      return AppModal(
        visible: true,
        onDismiss: onDismiss,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            closeRow,
            ...header,
            const SizedBox(height: AppPage.minTouchTarget ~/ 2 - 2),
            AppButton(text: '发音', onClick: () => controller.playCell(cell)),
            const SizedBox(height: 4),
          ],
        ),
      );
    }

    // 字母格：弹层 = 字母（读到时高亮）+「常见读音」列表——字母表的例词与
    // 「发音」按钮不在这儿，点读音行进来看的就是这个字母能发哪些音（最多 6 条）。
    final rows = soundRowsOf(cell.letterName);
    return AppModal(
      visible: true,
      onDismiss: onDismiss,
      alignment: AppModalAlignment.bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          closeRow,
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LetterHeading(cell: cell, highlighted: letterHighlighted),
                  const SizedBox(height: AppSpacing.xs),
                  _SectionHeader(
                    title: '常见读音 (${rows.length})',
                    trailing: AppIconButton(
                      icon: soundsPlaying ? Icons.stop : Icons.play_arrow,
                      tooltip: soundsPlaying ? '停止' : '连播这 ${rows.length} 种读音',
                      onClick: onToggleSounds,
                      size: 32,
                      tint: soundsPlaying
                          ? AppColors.primary
                          : AppColors.mutedSoft,
                    ),
                  ),
                  for (final row in rows)
                    _LetterSoundTile(
                      row: row,
                      highlighted: activeSound == row.phoneme,
                      onPlaySound: () => onPlaySound(row),
                      onPlayExample: () => onPlayExample(row),
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 符号行 + 例词 + 拼写行 + 中文（字母格与音标格共用）。
  List<Widget> _header(ReferenceController controller) => [
        // ① 顶部行：符号（点击发音——字母读字母名，音标放随包录音）
        //    + 小号注脚（字母格 = 音标 15sp 珊瑚；音标格 = 分类名 12sp Muted）
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            InkWell(
              onTap: () => controller.playSymbol(cell),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  cell.char,
                  textAlign: TextAlign.center,
                  style: AppType.textTheme.displayMedium
                      ?.copyWith(color: AppColors.ink),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              cell.reading,
              style: cell.isPhonetic
                  ? AppType.textTheme.labelSmall
                      ?.copyWith(color: AppColors.mutedSoft)
                  : AppType.phonetic.copyWith(fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // ② 例词：主角大字（serif 400 珊瑚，display 级不加粗）+ 可点击发音
        //    （音标格放例词录音，字母格走 TTS）
        InkWell(
          onTap: () => controller.playExample(cell),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              cell.example,
              textAlign: TextAlign.center,
              style: AppType.textTheme.displayLarge?.copyWith(
                fontSize: 40,
                height: 44 / 40,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        // ③ 拼写行：例词完整音标（英式，与分组数据同一体系）
        if (cell.exampleIpa.isNotEmpty)
          Text(
            cell.exampleIpa,
            textAlign: TextAlign.center,
            style: AppType.phonetic.copyWith(fontSize: 15),
          ),
        // ④ 例词中文（音标格无此数据）
        if (cell.exampleCn.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            cell.exampleCn,
            textAlign: TextAlign.center,
            style: AppType.textTheme.labelSmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ];
}

/// 弹层顶部的字母：`A a` + 字母名音标。不可点（听字母名走连播），
/// 连播读到这个字母时套一圈珊瑚描边。
class _LetterHeading extends StatelessWidget {
  const _LetterHeading({required this.cell, required this.highlighted});

  final ReferenceCellData cell;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.sm);
    return Container(
      // 描边常驻（未高亮时透明）：高亮不该让行高跳一下
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: highlighted ? AppColors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                cell.char,
                textAlign: TextAlign.center,
                style: AppType.textTheme.displayMedium
                    ?.copyWith(color: AppColors.ink),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                cell.reading,
                style: AppType.phonetic.copyWith(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹层里的一行读音：音标 + 类别徽章（「常见音」不挂）+ 例词 + 例词音标。
///
/// **两个点击区**（与音标格弹窗同款分工）：点左边的音标放**读音本身**，
/// 点右边的例词放**例词**；想连着听「读音 → 例词」用弹层上的「连播」。
class _LetterSoundTile extends StatelessWidget {
  const _LetterSoundTile({
    required this.row,
    required this.highlighted,
    required this.onPlaySound,
    required this.onPlayExample,
  });

  final LetterSoundRow row;
  final bool highlighted;
  final VoidCallback onPlaySound;
  final VoidCallback onPlayExample;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.sm);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      // 描边常驻（未高亮时透明）：高亮不该让行高跳一下
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: highlighted ? AppColors.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: radius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppPage.minTouchTarget),
          // stretch + padding：两个点击区各占满整行高度（各自都是 ≥44dp 的
          // 触摸目标，符合 DESIGN.md 的 touch target 要求）
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: onPlaySound,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Text(
                          row.phoneme,
                          style: AppType.phonetic.copyWith(
                            fontSize: 15,
                            color:
                                highlighted ? AppColors.primary : AppColors.ink,
                          ),
                        ),
                        if (row.kind != LetterSoundKind.common) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Tooltip(
                            message: row.kind.description,
                            child: AppBadge(row.kind.label),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: onPlayExample,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          row.example,
                          style: AppType.textTheme.bodyMedium
                              ?.copyWith(color: AppColors.bodyText),
                        ),
                        Text(
                          row.exampleIpa,
                          style: AppType.textTheme.labelSmall
                              ?.copyWith(color: AppColors.muted),
                        ),
                        if (row.note != null)
                          Text(
                            row.note!,
                            style: AppType.textTheme.labelSmall
                                ?.copyWith(color: AppColors.mutedSoft),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 按 [size] 分块。
List<List<T>> _chunked<T>(List<T> list, int size) => [
      for (var i = 0; i < list.length; i += size)
        list.sublist(i, (i + size).clamp(0, list.length)),
    ];
