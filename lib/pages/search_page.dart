import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/emby_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../widgets/poster_card.dart';
import 'detail_page.dart';

/// 全库搜索页，输入防抖 400ms。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<MediaItem> _results = [];
  bool _loading = false;
  bool _searched = false;

  EmbyApi get _api => context.read<AppState>().api!;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(text));
  }

  Future<void> _search(String text) async {
    final term = text.trim();
    if (term.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await _api.getItems(
        searchTerm: term,
        recursive: true,
        includeItemTypes: 'Movie,Series,Episode',
        limit: 60,
      );
      if (mounted && term == _controller.text.trim()) {
        setState(() {
          _results = result.items;
          _searched = true;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索电影、剧集…',
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _search,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? Center(
                  child: Text(_searched ? '没有找到相关内容' : '输入关键词搜索'))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.58,
                  ),
                  itemCount: _results.length,
                  itemBuilder: (context, i) {
                    final item = _results[i];
                    return PosterCard(
                      item: item,
                      width: 160,
                      imageUrl: _api.imageUrl(
                        item.type == 'Episode'
                            ? (item.seriesId ?? item.id)
                            : item.id,
                        tag: item.type == 'Episode'
                            ? null
                            : item.primaryImageTag,
                      ),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => DetailPage(itemId: item.id))),
                    );
                  },
                ),
    );
  }
}
