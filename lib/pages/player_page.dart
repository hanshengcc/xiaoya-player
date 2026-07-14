import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../api/emby_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';

/// 播放器页：mpv 内核（media_kit），直连播放，
/// 每 10 秒向服务器上报进度，退出时上报停止位置。
class PlayerPage extends StatefulWidget {
  final MediaItem item;
  final bool fromStart;

  const PlayerPage({super.key, required this.item, this.fromStart = false});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      title: 'Xiaoya Player',
      bufferSize: 64 * 1024 * 1024,
    ),
  );
  late final VideoController _controller = VideoController(_player);

  EmbyApi get _api => context.read<AppState>().api!;

  /// 当前播放条目（自动连播时会切换，widget.item 只是起点）
  late MediaItem _current = widget.item;
  PlaybackInfo? _playbackInfo;
  MediaSourceInfo? _source;
  String? _error;
  Timer? _progressTimer;
  bool _started = false;
  bool _switching = false;
  StreamSubscription<bool>? _completedSub;

  String get _title {
    final item = _current;
    if (item.type == 'Episode') {
      final s = item.parentIndexNumber, e = item.indexNumber;
      final code = (s != null && e != null) ? ' S$s:E$e' : '';
      return '${item.seriesName ?? ''}$code ${item.name}'.trim();
    }
    return item.name;
  }

  @override
  void initState() {
    super.initState();
    _enterFullContext();
    // 播放自然结束 → 自动切下一集
    _completedSub = _player.stream.completed.listen((done) {
      if (done) _playNext();
    });
    _start();
  }

  Future<void> _enterFullContext() async {
    // 移动端横屏 + 沉浸式；桌面端保持原样
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
  }

  Future<void> _exitFullContext() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {}
  }

  Future<void> _start() async {
    final resume = widget.fromStart ? Duration.zero : _current.resumePosition;
    await _open(_current, resume: resume);
    _progressTimer ??= Timer.periodic(const Duration(seconds: 10), (_) {
      _reportProgress();
    });
  }

  Future<void> _open(MediaItem item, {Duration resume = Duration.zero}) async {
    try {
      final info = await _api.getPlaybackInfo(item.id);
      if (info.mediaSources.isEmpty) {
        throw Exception('没有可用的播放源');
      }
      _current = item;
      _playbackInfo = info;
      _source = info.mediaSources.first;
      final url = _api.streamUrl(item.id, _source!);

      await _player
          .open(Media(url, start: resume > Duration.zero ? resume : null));

      await _api.reportPlaybackStart(item.id, _source!.id, info.playSessionId);
      _started = true;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// 找相邻集：offset=+1 下一集（季末跨下季首集），-1 上一集（季首跨上季末集）；
  /// 电影或到头返回 null。
  Future<MediaItem?> _findSibling(int offset) async {
    final cur = _current;
    if (cur.type != 'Episode' || cur.seriesId == null || cur.seasonId == null) {
      return null;
    }
    try {
      final episodes = await _api.getEpisodes(cur.seriesId!, cur.seasonId!);
      final idx = episodes.indexWhere((e) => e.id == cur.id);
      if (idx >= 0) {
        final target = idx + offset;
        if (target >= 0 && target < episodes.length) return episodes[target];
      }

      // 跨季
      final seasons = await _api.getSeasons(cur.seriesId!);
      final sIdx = seasons.indexWhere((s) => s.id == cur.seasonId);
      final sTarget = sIdx + offset;
      if (sIdx >= 0 && sTarget >= 0 && sTarget < seasons.length) {
        final other =
            await _api.getEpisodes(cur.seriesId!, seasons[sTarget].id);
        if (other.isNotEmpty) return offset > 0 ? other.first : other.last;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _playNext() => _playSibling(1, auto: true);

  Future<void> _playSibling(int offset, {bool auto = false}) async {
    if (_switching) return;
    _switching = true;
    try {
      final next = await _findSibling(offset);
      if (next == null) return;
      await _reportStopped(); // 当前集收尾（服务器会记录进度/已看）
      _started = false;
      if (!mounted) return;
      final prefix = auto ? '自动播放' : (offset > 0 ? '下一集' : '上一集');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$prefix：第${next.indexNumber ?? '?'}集 ${next.name}'),
        duration: const Duration(seconds: 3),
      ));
      await _open(next);
    } finally {
      _switching = false;
    }
  }

  Future<void> _reportProgress() async {
    if (!_started || _source == null || _playbackInfo == null) return;
    try {
      await _api.reportPlaybackProgress(
        _current.id,
        _source!.id,
        _playbackInfo!.playSessionId,
        _player.state.position,
        isPaused: !_player.state.playing,
      );
    } catch (_) {}
  }

  Future<void> _reportStopped() async {
    if (!_started || _source == null || _playbackInfo == null) return;
    try {
      await _api.reportPlaybackStopped(
        _current.id,
        _source!.id,
        _playbackInfo!.playSessionId,
        _player.state.position,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _completedSub?.cancel();
    _progressTimer?.cancel();
    _reportStopped();
    _player.dispose();
    _exitFullContext();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.transparent, foregroundColor: Colors.white),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 56),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }

    final tvMode = context.read<AppState>().tvMode;

    if (tvMode) {
      // 电视：Netflix 式屏上控制层，media_kit 触摸控件整个关掉
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Video(controller: _controller, controls: NoVideoControls),
            _TvControls(
              player: _player,
              title: _title,
              isEpisode: _current.type == 'Episode',
              onNextEpisode: () => _playSibling(1),
              onShowSettings: _showTvMenu,
              onSeekBy: _seekBy,
            ),
          ],
        ),
      );
    }

    // 桌面/手机：media_kit 自带 Material 控件：进度条、播放/暂停、
    // 音量、倍速、音轨/字幕轨选择、全屏，桌面与移动端自动适配。
    final Widget theme = MaterialVideoControlsTheme(
      normal: _controlsTheme(false),
      fullscreen: _controlsTheme(true),
      child: MaterialDesktopVideoControlsTheme(
        normal: _desktopControlsTheme(),
        fullscreen: _desktopControlsTheme(),
        child: Video(
          controller: _controller,
          controls: AdaptiveVideoControls,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: theme,
    );
  }

  /// 电视端播放设置面板：D-pad 上下移动焦点、确认选中、返回关闭。
  Future<void> _showTvMenu() async {
    final current = _player.state.track;
    final subtitleOptions = <(SubtitleTrack, String, bool)>[
      for (final t in _player.state.tracks.subtitle)
        (t, _trackLabel(t), t == current.subtitle),
    ];
    final external = _source?.streams.where((s) =>
            s.type == 'Subtitle' && s.isExternal && s.deliveryUrl != null) ??
        const <MediaStreamInfo>[];
    for (final s in external) {
      final url = _api.absoluteUrl(s.deliveryUrl!);
      subtitleOptions.add((
        SubtitleTrack.uri(url, title: s.displayTitle, language: s.language),
        '外挂 · ${s.displayTitle ?? s.language ?? s.index}',
        current.subtitle.id == url,
      ));
    }
    final audioOptions = <(AudioTrack, String, bool)>[
      for (final t in _player.state.tracks.audio)
        (t, _trackLabel(t), t == current.audio),
    ];

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        Widget header(String text) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: scheme.primary)),
            );
        Widget option(String label, bool selected, VoidCallback onTap,
                {bool autofocus = false}) =>
            ListTile(
              autofocus: autofocus,
              dense: true,
              leading: Icon(Icons.check,
                  size: 18,
                  color: selected ? scheme.primary : Colors.transparent),
              title: Text(label),
              onTap: () {
                onTap();
                Navigator.of(context).pop();
              },
            );

        return AlertDialog(
          title: const Text('播放设置'),
          contentPadding: const EdgeInsets.only(bottom: 8),
          content: SizedBox(
            width: 380,
            height: 420,
            child: ListView(
              children: [
                header('字幕'),
                for (final (i, o) in subtitleOptions.indexed)
                  option(o.$2, o.$3,
                      () => _player.setSubtitleTrack(o.$1),
                      autofocus: i == 0),
                header('音轨'),
                for (final o in audioOptions)
                  option(o.$2, o.$3, () => _player.setAudioTrack(o.$1)),
                header('倍速'),
                for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                  option(r == 1.0 ? '正常' : '${r}x',
                      _player.state.rate == r, () => _player.setRate(r)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _seekBy(Duration delta) {
    final duration = _player.state.duration;
    var target = _player.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    _player.seek(target);
  }

  List<Widget> get _topBar => [
        BackButton(
          color: Colors.white,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(
            _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ];

  MaterialVideoControlsThemeData _controlsTheme(bool fullscreen) =>
      MaterialVideoControlsThemeData(
        topButtonBar: _topBar,
        seekBarThumbColor: Theme.of(context).colorScheme.primary,
        seekBarPositionColor: Theme.of(context).colorScheme.primary,
        seekOnDoubleTap: true,
        bottomButtonBar: [
          const MaterialPositionIndicator(),
          const Spacer(),
          _audioMenu(),
          _subtitleMenu(),
          _speedMenu(),
          const MaterialFullscreenButton(),
        ],
      );

  MaterialDesktopVideoControlsThemeData _desktopControlsTheme() =>
      MaterialDesktopVideoControlsThemeData(
        topButtonBar: _topBar,
        seekBarThumbColor: Theme.of(context).colorScheme.primary,
        seekBarPositionColor: Theme.of(context).colorScheme.primary,
        bottomButtonBar: [
          const MaterialDesktopSkipPreviousButton(),
          const MaterialDesktopPlayOrPauseButton(),
          const MaterialDesktopSkipNextButton(),
          const MaterialDesktopVolumeButton(),
          const MaterialDesktopPositionIndicator(),
          const Spacer(),
          _audioMenu(),
          _subtitleMenu(),
          _speedMenu(),
          const MaterialDesktopFullscreenButton(),
        ],
      );

  // ---------------- 音轨 / 字幕 / 倍速 ----------------

  /// AudioTrack / SubtitleTrack 无公共父类，动态取 id/title/language。
  String _trackLabel(dynamic t) {
    final String id = t.id as String;
    if (id == 'auto') return '自动';
    if (id == 'no') return '关闭';
    final String? title = t.title as String?;
    final String? language = t.language as String?;
    final parts = [
      if (title != null && title.isNotEmpty) title,
      if (language != null && language.isNotEmpty) language,
    ];
    return parts.isEmpty ? '轨道 $id' : parts.join(' · ');
  }

  PopupMenuItem<T> _menuItem<T>(T value, String label, bool selected) =>
      PopupMenuItem<T>(
        value: value,
        child: Row(
          children: [
            Icon(Icons.check,
                size: 18,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent),
            const SizedBox(width: 8),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  Widget _audioMenu() => PopupMenuButton<AudioTrack>(
        icon: const Icon(Icons.audiotrack, color: Colors.white, size: 22),
        tooltip: '音轨',
        onSelected: (t) => _player.setAudioTrack(t),
        itemBuilder: (_) {
          final current = _player.state.track.audio;
          return _player.state.tracks.audio
              .map((t) => _menuItem(t, _trackLabel(t), t == current))
              .toList();
        },
      );

  Widget _subtitleMenu() => PopupMenuButton<SubtitleTrack>(
        icon: const Icon(Icons.subtitles, color: Colors.white, size: 22),
        tooltip: '字幕',
        onSelected: (t) => _player.setSubtitleTrack(t),
        itemBuilder: (_) {
          final current = _player.state.track.subtitle;
          final items = _player.state.tracks.subtitle
              .map((t) => _menuItem(t, _trackLabel(t), t == current))
              .toList();
          // Emby 外挂字幕：内嵌轨之外的 srt/ass 文件，走服务器下载地址
          final external = _source?.streams.where((s) =>
                  s.type == 'Subtitle' &&
                  s.isExternal &&
                  s.deliveryUrl != null) ??
              const <MediaStreamInfo>[];
          for (final s in external) {
            final url = _api.absoluteUrl(s.deliveryUrl!);
            items.add(_menuItem(
              SubtitleTrack.uri(url,
                  title: s.displayTitle, language: s.language),
              '外挂 · ${s.displayTitle ?? s.language ?? s.index}',
              current.id == url,
            ));
          }
          return items;
        },
      );

  Widget _speedMenu() => PopupMenuButton<double>(
        icon: const Icon(Icons.speed, color: Colors.white, size: 22),
        tooltip: '倍速',
        onSelected: (r) => _player.setRate(r),
        itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
            .map((r) => _menuItem(
                r, r == 1.0 ? '正常' : '${r}x', _player.state.rate == r))
            .toList(),
      );
}

/// Netflix 式电视控制层：
/// - 隐藏时：确认=暂停并呼出；左右=±10 秒（同时短暂显示）；上下=呼出
/// - 显示时：D-pad 在按钮间移动焦点，确认激活；4 秒无操作自动隐藏（暂停时常驻）
/// - 按钮行：快退 / 播放暂停 / 快进 / 下一集(剧集) / 字幕和音频 / 倍速
class _TvControls extends StatefulWidget {
  final Player player;
  final String title;
  final bool isEpisode;
  final VoidCallback onNextEpisode;
  final VoidCallback onShowSettings;
  final void Function(Duration) onSeekBy;

  const _TvControls({
    required this.player,
    required this.title,
    required this.isEpisode,
    required this.onNextEpisode,
    required this.onShowSettings,
    required this.onSeekBy,
  });

  @override
  State<_TvControls> createState() => _TvControlsState();
}

class _TvControlsState extends State<_TvControls> {
  bool _visible = true;
  Timer? _hideTimer;
  final _rootFocus = FocusNode(debugLabel: 'tv-controls-root');
  final _playFocus = FocusNode(debugLabel: 'tv-play');

  Player get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _restartHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _rootFocus.dispose();
    _playFocus.dispose();
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      // 暂停时控制层常驻，符合 Netflix 行为
      if (mounted && _player.state.playing) _hide();
    });
  }

  void _show({bool focusPlay = true}) {
    if (!_visible) {
      setState(() => _visible = true);
      if (focusPlay) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _playFocus.requestFocus();
        });
      }
    }
    _restartHideTimer();
  }

  void _hide() {
    if (!_visible) return;
    setState(() => _visible = false);
    _rootFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // 菜单键任何时候都开字幕/音轨/倍速面板
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.f10) {
      widget.onShowSettings();
      return KeyEventResult.handled;
    }

    if (_visible) {
      // 显示中：任何按键都续命；导航与激活交给焦点系统
      _restartHideTimer();
      if (key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.escape) {
        _hide();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 隐藏中
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onSeekBy(const Duration(seconds: 10));
      _show(focusPlay: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onSeekBy(const Duration(seconds: -10));
      _show(focusPlay: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _show();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _player.playOrPause();
      _show();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: ExcludeFocus(
          excluding: !_visible,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent, Colors.black87],
                stops: [0, 0.4, 1],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(48, 24, 48, 32),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 20),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _buildSeekBar(),
                const SizedBox(height: 20),
                _buildButtonRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeekBar() {
    return StreamBuilder<Duration>(
      stream: _player.stream.position,
      initialData: _player.state.position,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = _player.state.duration;
        final progress = dur.inMilliseconds > 0
            ? pos.inMilliseconds / dur.inMilliseconds
            : 0.0;
        final primary = Theme.of(context).colorScheme.primary;
        return Row(
          children: [
            Text(_fmt(pos),
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(width: 16),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation(primary),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(_fmt(dur),
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        );
      },
    );
  }

  Widget _buildButtonRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _TvButton(
          icon: Icons.replay_10,
          label: '快退',
          onTap: () {
            widget.onSeekBy(const Duration(seconds: -10));
            _restartHideTimer();
          },
        ),
        StreamBuilder<bool>(
          stream: _player.stream.playing,
          initialData: _player.state.playing,
          builder: (_, snap) => _TvButton(
            focusNode: _playFocus,
            icon: (snap.data ?? true) ? Icons.pause : Icons.play_arrow,
            label: (snap.data ?? true) ? '暂停' : '播放',
            big: true,
            onTap: () {
              _player.playOrPause();
              _restartHideTimer();
            },
          ),
        ),
        _TvButton(
          icon: Icons.forward_10,
          label: '快进',
          onTap: () {
            widget.onSeekBy(const Duration(seconds: 10));
            _restartHideTimer();
          },
        ),
        if (widget.isEpisode)
          _TvButton(
            icon: Icons.skip_next,
            label: '下一集',
            onTap: widget.onNextEpisode,
          ),
        _TvButton(
          icon: Icons.subtitles,
          label: '字幕和音频',
          onTap: widget.onShowSettings,
        ),
      ],
    );
  }
}

/// 电视控制按钮：聚焦时白圈高亮 + 放大 + 底部文字。
class _TvButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool big;
  final FocusNode? focusNode;

  const _TvButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.big = false,
    this.focusNode,
  });

  @override
  State<_TvButton> createState() => _TvButtonState();
}

class _TvButtonState extends State<_TvButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.big ? 64.0 : 52.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: _focused ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Material(
              color: _focused ? Colors.white : Colors.white12,
              shape: const CircleBorder(),
              child: InkWell(
                focusNode: widget.focusNode,
                onFocusChange: (f) => setState(() => _focused = f),
                onTap: widget.onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    widget.icon,
                    size: widget.big ? 36 : 28,
                    color: _focused ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.label,
            style: TextStyle(
              color: _focused ? Colors.white : Colors.white60,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
