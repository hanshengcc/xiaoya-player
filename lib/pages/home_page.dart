import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/emby_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../utils/errors.dart';
import '../utils/update_checker.dart';
import '../widgets/poster_card.dart';
import '../widgets/section_row.dart';
import '../widgets/tv_focus_highlight.dart';
import '../widgets/update_dialog.dart';
import 'detail_page.dart';
import 'library_page.dart';
import 'player_page.dart';
import 'search_page.dart';
import 'servers_page.dart';
import 'settings_page.dart';

/// 首页：继续观看 / 各媒体库最新入库 / 媒体库入口。
///
/// 启动只拉 2 个请求（继续观看 + 库列表）；各库的"最新入库"区块
/// 由 ListView.builder 懒构建，滚动进视口附近才发请求，结果缓存
/// 在页面级 map 里，滚回来不重复请求。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;
  String? _error;
  List<MediaItem> _resume = [];
  List<LibraryView> _views = [];
  final Map<String, List<MediaItem>> _latestCache = {};

  EmbyApi get _api => context.read<AppState>().api!;

  @override
  void initState() {
    super.initState();
    _load();
    _checkUpdate();
  }

  /// 静默查一次新版本，找到了就用 SnackBar 提一句——不弹窗打断，
  /// 12 小时内查过会自己跳过（节流逻辑在 UpdateChecker 里）。
  Future<void> _checkUpdate() async {
    final info = await UpdateChecker.checkThrottled();
    if (!mounted || info == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('发现新版本 v${info.version}'),
      action: SnackBarAction(
        label: '查看',
        onPressed: () => showUpdateDialog(context, info),
      ),
      duration: const Duration(seconds: 8),
    ));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getResumeItems(),
        _api.getViews(),
      ]);
      _resume = results[0] as List<MediaItem>;
      _views = (results[1] as List<LibraryView>)
          .where((v) =>
              v.collectionType == 'movies' ||
              v.collectionType == 'tvshows' ||
              v.collectionType == null)
          .toList();
      _latestCache.clear();
    } catch (e) {
      _error = friendlyError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openItem(MediaItem item) {
    if (item.isVideo) {
      // 继续观看的条目直接进播放器，从上次位置续播
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => PlayerPage(item: item)));
    } else {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => DetailPage(itemId: item.id)));
    }
  }

  void _openLibrary(LibraryView v) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LibraryPage(view: v)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(state.activeServer?.name ?? '灯影'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: '服务器',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ServersPage())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorRetry(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  // builder 懒构建：区块滚进视口附近才实例化、才发请求
                  child: ListView.builder(
                    // 电视 overscan 安全边距
                    padding: state.tvMode
                        ? const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16)
                        : null,
                    itemCount: 2 + _views.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) return _buildLibraryChips();
                      if (i == 1) {
                        return _resume.isEmpty
                            ? const SizedBox.shrink()
                            : SectionRow(
                                title: '继续观看',
                                height: 224,
                                children: _resume.indexed
                                    .map((r) => PosterCard(
                                          item: r.$2,
                                          width: 280,
                                          aspectRatio: 16 / 9,
                                          autofocus: r.$1 == 0 && state.tvMode,
                                          imageUrl: _api.imageUrl(r.$2.id,
                                              type: 'Primary', maxWidth: 480),
                                          onTap: () => _openItem(r.$2),
                                        ))
                                    .toList(),
                              );
                      }
                      if (i == 2 + _views.length) {
                        return const SizedBox(height: 24);
                      }
                      final v = _views[i - 2];
                      return _LatestSection(
                        key: ValueKey(v.id),
                        view: v,
                        cache: _latestCache,
                        api: _api,
                        // 最新入库点进去先看简介，不直接开播
                        onOpenItem: (item) => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => DetailPage(itemId: item.id))),
                        onMore: () => _openLibrary(v),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildLibraryChips() {
    // 没有"继续观看"时，这里是首页第一个可聚焦元素，电视需要默认落焦点
    final autofocusFirst = context.read<AppState>().tvMode && _resume.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _views.indexed
            .map((r) => TvFocusHighlight(
                  borderRadius: const BorderRadius.all(Radius.circular(20)),
                  child: ActionChip(
                    autofocus: autofocusFirst && r.$1 == 0,
                    avatar: Icon(
                      r.$2.collectionType == 'movies'
                          ? Icons.movie_outlined
                          : r.$2.collectionType == 'tvshows'
                              ? Icons.tv_outlined
                              : Icons.folder_outlined,
                      size: 18,
                    ),
                    label: Text(r.$2.name),
                    onPressed: () => _openLibrary(r.$2),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

/// 单个库的"最新入库"区块：进入视口附近（initState）才发请求；
/// 结果写入页面级缓存，widget 被回收后再滚回来直接复用。
class _LatestSection extends StatefulWidget {
  final LibraryView view;
  final Map<String, List<MediaItem>> cache;
  final EmbyApi api;
  final void Function(MediaItem) onOpenItem;
  final VoidCallback onMore;

  const _LatestSection({
    super.key,
    required this.view,
    required this.cache,
    required this.api,
    required this.onOpenItem,
    required this.onMore,
  });

  @override
  State<_LatestSection> createState() => _LatestSectionState();
}

class _LatestSectionState extends State<_LatestSection> {
  List<MediaItem>? _items;

  @override
  void initState() {
    super.initState();
    _items = widget.cache[widget.view.id];
    if (_items == null) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final items = await widget.api.getLatestItems(parentId: widget.view.id);
      widget.cache[widget.view.id] = items;
      if (mounted) setState(() => _items = items);
    } catch (_) {
      widget.cache[widget.view.id] = const [];
      if (mounted) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return _Skeleton(title: widget.view.name);
    if (items.isEmpty) return const SizedBox.shrink();
    return SectionRow(
      title: '最新 · ${widget.view.name}',
      onMore: widget.onMore,
      children: items
          .map((e) => PosterCard(
                item: e,
                imageUrl: widget.api.imageUrl(e.id, tag: e.primaryImageTag),
                onTap: () => widget.onOpenItem(e),
              ))
          .toList(),
    );
  }
}

/// 加载占位骨架：与真实区块等高，避免滚动跳动。
class _Skeleton extends StatelessWidget {
  final String title;
  const _Skeleton({required this.title});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
          child: Text('最新 · $title',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ),
        SizedBox(
          height: 272,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: 8,
            separatorBuilder: (_, __) => const SizedBox(width: 18),
            itemBuilder: (_, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 146,
                  height: 219,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 90,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(error, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
