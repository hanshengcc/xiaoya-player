import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/models.dart';

/// 海报卡片：封面 + 标题 + 副标题 + 观看进度条。
///
/// 支持焦点导航（TV 遥控器 D-pad / 键盘方向键）：
/// 聚焦时放大 + 主色描边，并自动滚动到可视区域；
/// 触摸和鼠标点击行为不受影响。
class PosterCard extends StatefulWidget {
  final MediaItem item;
  final String imageUrl;
  final VoidCallback onTap;
  final double width;
  final double aspectRatio; // 宽高比，海报 2/3，横图 16/9

  const PosterCard({
    super.key,
    required this.item,
    required this.imageUrl,
    required this.onTap,
    this.width = 146,
    this.aspectRatio = 2 / 3,
  });

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  MediaItem get item => widget.item;

  String get _subtitle {
    if (item.type == 'Episode') {
      final s = item.parentIndexNumber, e = item.indexNumber;
      final code = (s != null && e != null) ? 'S$s:E$e ' : '';
      return '$code${item.seriesName ?? ''}'.trim();
    }
    return item.productionYear?.toString() ?? '';
  }

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    if (focused) {
      // 遥控器/键盘走到这张卡时，把它滚进可视区域
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (item.playedPercentage ?? 0) / 100.0;

    return SizedBox(
      width: widget.width,
      child: AnimatedScale(
        scale: _focused ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: _onFocusChange,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _focused ? scheme.primary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: widget.aspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: widget.imageUrl,
                          fit: BoxFit.cover,
                          // 按显示尺寸解码，避免全尺寸位图占内存
                          memCacheWidth: (widget.width *
                                  MediaQuery.of(context).devicePixelRatio)
                              .round(),
                          placeholder: (_, __) => Container(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(Icons.movie_outlined,
                                color: scheme.outline, size: 32),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(Icons.broken_image_outlined,
                                color: scheme.outline, size: 32),
                          ),
                        ),
                        if (item.played)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.check,
                                  size: 14, color: scheme.onPrimary),
                            ),
                          ),
                        if (progress > 0 && progress < 1)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 4,
                              backgroundColor: Colors.black45,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: _focused ? scheme.primary : null,
                        fontWeight: _focused ? FontWeight.w600 : null,
                      ),
                ),
              ),
              if (_subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    _subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
