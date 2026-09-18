import 'package:flutter/widgets.dart';

/// 宽屏下把内容列限宽居中；窄屏（手机）下不产生任何影响
/// （maxWidth 大于可用宽时 ConstrainedBox 不生效）。
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
