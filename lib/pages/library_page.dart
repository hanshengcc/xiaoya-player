import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/emby_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../widgets/poster_card.dart';
import 'detail_page.dart';
import 'player_page.dart';

/// 媒体库浏览页：网格 + 无限滚动分页 + 排序。
class LibraryPage extends StatefulWidget {
  final LibraryView view;
  const LibraryPage({super.key, required this.view});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  static const _pageSize = 60;

  final _items = <MediaItem>[];
  final _scroll = ScrollController();
  int _total = -1;
  bool _loading = false;
  String? _error;
  String _sortBy = 'SortName';
  String _sortOrder = 'Ascending';

  EmbyApi get _api => context.read<AppState>().api!;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _hasMore => _total < 0 || _items.length < _total;

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final isTv = widget.view.collectionType == 'tvshows';
      final result = await _api.getItems(
        parentId: widget.view.id,
        recursive: true,
        includeItemTypes: isTv
            ? 'Series'
            : widget.view.collectionType == 'movies'
                ? 'Movie'
                : null,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        startIndex: _items.length,
        limit: _pageSize,
      );
      _items.addAll(result.items);
      _total = result.totalCount;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resort(String sortBy, String order) {
    setState(() {
      _sortBy = sortBy;
      _sortOrder = order;
      _items.clear();
      _total = -1;
    });
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.view.name),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            onSelected: (v) {
              switch (v) {
                case 'name':
                  _resort('SortName', 'Ascending');
                case 'date':
                  _resort('DateCreated', 'Descending');
                case 'year':
                  _resort('ProductionYear', 'Descending');
                case 'rating':
                  _resort('CommunityRating', 'Descending');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'name', child: Text('按名称')),
              PopupMenuItem(value: 'date', child: Text('按入库时间')),
              PopupMenuItem(value: 'year', child: Text('按年份')),
              PopupMenuItem(value: 'rating', child: Text('按评分')),
            ],
          ),
        ],
      ),
      body: _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty && _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('这个库是空的'))
                  : GridView.builder(
                      controller: _scroll,
                      // 电视 overscan 安全边距
                      padding: EdgeInsets.all(
                          context.watch<AppState>().tvMode ? 40 : 16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.58,
                      ),
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= _items.length) {
                          return const Center(
                              child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ));
                        }
                        final item = _items[i];
                        return PosterCard(
                          item: item,
                          width: 160,
                          autofocus: i == 0 && context.read<AppState>().tvMode,
                          imageUrl:
                              _api.imageUrl(item.id, tag: item.primaryImageTag),
                          onTap: () {
                            if (item.isVideo) {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) =>
                                      DetailPage(itemId: item.id)));
                            } else if (item.isFolder) {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) =>
                                      DetailPage(itemId: item.id)));
                            } else {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => PlayerPage(item: item)));
                            }
                          },
                        );
                      },
                    ),
    );
  }
}
