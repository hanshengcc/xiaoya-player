import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 首页横向滚动区块：标题 + 横向卡片列表。
///
/// 桌面端体验：支持鼠标拖拽滚动；悬停时显示左右翻页箭头，
/// 每次翻约一屏，解决鼠标滚轮无法横向滚动导致右侧内容够不着的问题。
class SectionRow extends StatefulWidget {
  final String title;
  final List<Widget> children;
  final double height;
  final VoidCallback? onMore;

  const SectionRow({
    super.key,
    required this.title,
    required this.children,
    this.height = 272,
    this.onMore,
  });

  @override
  State<SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<SectionRow> {
  final _controller = ScrollController();
  bool _hovering = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(double direction) {
    if (!_controller.hasClients) return;
    final viewport = _controller.position.viewportDimension;
    final target = (_controller.offset + direction * viewport * 0.85)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(target,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(widget.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (widget.onMore != null)
                TextButton(onPressed: widget.onMore, child: const Text('更多')),
            ],
          ),
        ),
        SizedBox(
          height: widget.height,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: Stack(
              children: [
                ScrollConfiguration(
                  // 允许鼠标按住拖拽滚动（桌面端默认只认触摸/触控板）
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: ListView.separated(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: widget.children.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 18),
                    itemBuilder: (_, i) => widget.children[i],
                  ),
                ),
                if (_hovering) ...[
                  _Arrow(
                    alignment: Alignment.centerLeft,
                    icon: Icons.chevron_left,
                    color: scheme,
                    onTap: () => _page(-1),
                  ),
                  _Arrow(
                    alignment: Alignment.centerRight,
                    icon: Icons.chevron_right,
                    color: scheme,
                    onTap: () => _page(1),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final ColorScheme color;
  final VoidCallback onTap;

  const _Arrow({
    required this.alignment,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: color.surface.withValues(alpha: 0.92),
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 26, color: color.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
