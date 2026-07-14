import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/emby_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import 'player_page.dart';

/// 详情页：电影直接给播放按钮；剧集展示季 / 集列表。
class DetailPage extends StatefulWidget {
  final String itemId;
  const DetailPage({super.key, required this.itemId});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  MediaItem? _item;
  List<MediaItem> _seasons = [];
  List<MediaItem> _episodes = [];
  String? _selectedSeasonId;
  bool _loading = true;
  String? _error;

  EmbyApi get _api => context.read<AppState>().api!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final item = await _api.getItem(widget.itemId);
      _item = item;
      if (item.type == 'Series') {
        _seasons = await _api.getSeasons(item.id);
        if (_seasons.isNotEmpty) {
          await _selectSeason(_seasons.first.id, refresh: false);
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectSeason(String seasonId, {bool refresh = true}) async {
    _selectedSeasonId = seasonId;
    if (refresh) setState(() => _episodes = []);
    try {
      final eps = await _api.getEpisodes(_item!.id, seasonId);
      if (mounted && _selectedSeasonId == seasonId) {
        setState(() => _episodes = eps);
      }
    } catch (_) {}
  }

  void _play(MediaItem item, {bool fromStart = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(item: item, fromStart: fromStart)));
    // 回来后刷新进度
    if (mounted) _load();
  }

  Future<void> _toggleFavorite() async {
    final item = _item!;
    try {
      await _api.setFavorite(item.id, !item.isFavorite);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? '加载失败'),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final item = _item!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            actions: [
              IconButton(
                icon: Icon(
                    item.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: item.isFavorite ? Colors.redAccent : null),
                tooltip: '收藏',
                onPressed: _toggleFavorite,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _api.imageUrl(item.id,
                        type: 'Backdrop',
                        tag: item.backdropImageTag,
                        maxWidth: 1280),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: scheme.surfaceContainerHighest),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (item.productionYear != null)
                        Text('${item.productionYear}'),
                      if (item.runTime != null)
                        Text(formatRuntime(item.runTime!)),
                      if (item.officialRating != null)
                        _Badge(text: item.officialRating!),
                      if (item.communityRating != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 16, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(item.communityRating!.toStringAsFixed(1)),
                          ],
                        ),
                    ],
                  ),
                  if (item.genres.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(item.genres.join(' · '),
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 16),
                  if (item.isVideo) _buildPlayButtons(item),
                  if (item.overview != null &&
                      item.overview!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(item.overview!,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(height: 1.6)),
                  ],
                  if (item.type == 'Series') ...[
                    const SizedBox(height: 20),
                    _buildSeasonSelector(),
                  ],
                ],
              ),
            ),
          ),
          if (item.type == 'Series') _buildEpisodeList(),
        ],
      ),
    );
  }

  Widget _buildPlayButtons(MediaItem item) {
    final hasResume = item.resumePosition > Duration.zero;
    return Row(
      children: [
        FilledButton.icon(
          onPressed: () => _play(item),
          icon: const Icon(Icons.play_arrow),
          label: Text(hasResume
              ? '继续播放 ${formatDuration(item.resumePosition)}'
              : '播放'),
        ),
        if (hasResume) ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => _play(item, fromStart: true),
            icon: const Icon(Icons.replay),
            label: const Text('从头播放'),
          ),
        ],
      ],
    );
  }

  Widget _buildSeasonSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _seasons
            .map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s.name),
                    selected: _selectedSeasonId == s.id,
                    onSelected: (_) => _selectSeason(s.id),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildEpisodeList() {
    final scheme = Theme.of(context).colorScheme;
    return SliverList.builder(
      itemCount: _episodes.length,
      itemBuilder: (context, i) {
        final ep = _episodes[i];
        final progress = (ep.playedPercentage ?? 0) / 100.0;
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: SizedBox(
            width: 120,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: _api.imageUrl(ep.id,
                          tag: ep.primaryImageTag, maxWidth: 300),
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(color: scheme.surfaceContainerHighest),
                    ),
                    if (progress > 0 && progress < 1)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                            value: progress, minHeight: 3),
                      ),
                  ],
                ),
              ),
            ),
          ),
          title: Text(
            '${ep.indexNumber != null ? '${ep.indexNumber}. ' : ''}${ep.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              if (ep.runTime != null) Text(formatRuntime(ep.runTime!)),
              if (ep.played) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, size: 14, color: scheme.primary),
              ],
            ],
          ),
          onTap: () => _play(ep),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
