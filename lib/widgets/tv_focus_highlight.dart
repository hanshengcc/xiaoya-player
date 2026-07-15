import 'package:flutter/material.dart';

/// 给标准 Material 控件（Chip/Button 等）套一层电视可见的聚焦框。
///
/// 默认的 Material 聚焦态只是一层很淡的 overlay，在深色背景 + 10 尺
/// 距离的电视上基本看不见——遥控器移动焦点时完全找不到当前停在哪。
/// 这里改用主色描边 + 轻微放大，和海报卡片、播放器按钮的聚焦视觉统一。
class TvFocusHighlight extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const TvFocusHighlight({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  State<TvFocusHighlight> createState() => _TvFocusHighlightState();
}

class _TvFocusHighlightState extends State<TvFocusHighlight> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedScale(
        scale: _focused ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
