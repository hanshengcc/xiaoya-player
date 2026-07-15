import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../api/emby_api.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../utils/errors.dart';
import '../theme.dart';

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
      title: '灯影',
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
      if (mounted) setState(() => _error = friendlyError(e));
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
              key: ValueKey(_current.id),
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

  /// 电视端播放设置面板：自管理上下移动 + 确认选中，不依赖框架默认方向
  /// 焦点穿透（ListView 在部分平台会把方向键当滚动而非焦点移动处理，
  /// 导致遥控器上下键选不动、确认键总是命中第一项）。
  Future<void> _showTvMenu() async {
    final current = _player.state.track;
    final subtitleOptions = <_TvMenuOption>[
      for (final t in _player.state.tracks.subtitle)
        _TvMenuOption(_trackLabel(t), t == current.subtitle,
            () => _player.setSubtitleTrack(t)),
    ];
    final external = _source?.streams.where((s) =>
            s.type == 'Subtitle' && s.isExternal && s.deliveryUrl != null) ??
        const <MediaStreamInfo>[];
    for (final s in external) {
      final url = _api.absoluteUrl(s.deliveryUrl!);
      final track =
          SubtitleTrack.uri(url, title: s.displayTitle, language: s.language);
      subtitleOptions.add(_TvMenuOption(
        '外挂 · ${s.displayTitle ?? s.language ?? s.index}',
        current.subtitle.id == url,
        () => _player.setSubtitleTrack(track),
      ));
    }
    final audioOptions = <_TvMenuOption>[
      for (final t in _player.state.tracks.audio)
        _TvMenuOption(
            _trackLabel(t), t == current.audio, () => _player.setAudioTrack(t)),
    ];
    final speedOptions = <_TvMenuOption>[
      for (final r in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
        _TvMenuOption(r == 1.0 ? '正常' : '${r}x', _player.state.rate == r,
            () => _player.setRate(r)),
    ];

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => _TvSettingsDialog(sections: [
        ('字幕', subtitleOptions),
        ('音轨', audioOptions),
        ('倍速', speedOptions),
      ]),
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
/// - 显示时：左右自行移动按钮焦点，确认激活；4 秒无操作自动隐藏（暂停时常驻）
/// - 按钮行：快退 / 播放暂停 / 快进 / 下一集(剧集) / 字幕和音频
///
/// 焦点导航与激活全部自管理（不用框架默认的方向焦点穿透 / Activate
/// intent）：不同电视盒子、不同遥控器对 Flutter 隐式焦点系统支持不一致，
/// 曾经导致按钮切不动、字幕面板打不开。这里只依赖固定的按键集合，稳定
/// 可控。
class _TvControls extends StatefulWidget {
  final Player player;
  final String title;
  final bool isEpisode;
  final VoidCallback onNextEpisode;
  final Future<void> Function() onShowSettings;
  final void Function(Duration) onSeekBy;

  const _TvControls({
    super.key,
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
  int _focusedIndex = 1; // 默认聚焦播放/暂停
  Timer? _hideTimer;
  final _focusNode = FocusNode(debugLabel: 'tv-controls');
  List<({IconData icon, String label, bool big, VoidCallback onTap})> _actions =
      const [];

  Player get _player => widget.player;

  @override
  void initState() {
    super.initState();
    _restartHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      // 暂停时控制层常驻，符合 Netflix 行为
      if (mounted && _player.state.playing) _hide();
    });
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _restartHideTimer();
  }

  void _hide() {
    if (!_visible) return;
    setState(() => _visible = false);
  }

  void _move(int delta) {
    if (_actions.isEmpty) return;
    setState(() =>
        _focusedIndex = (_focusedIndex + delta).clamp(0, _actions.length - 1));
    _restartHideTimer();
  }

  void _activate() {
    if (_focusedIndex >= 0 && _focusedIndex < _actions.length) {
      _actions[_focusedIndex].onTap();
    }
    _restartHideTimer();
  }

  bool _isConfirm(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.mediaPlayPause ||
      key == LogicalKeyboardKey.gameButtonA;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // 菜单键 / 部分遥控器的独立字幕键：任何时候都开设置面板
    if (key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.f10 ||
        key == LogicalKeyboardKey.closedCaptionToggle) {
      _openSettings();
      return KeyEventResult.handled;
    }

    if (!_visible) {
      if (key == LogicalKeyboardKey.arrowRight) {
        widget.onSeekBy(const Duration(seconds: 10));
        _show();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        widget.onSeekBy(const Duration(seconds: -10));
        _show();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        _show();
        return KeyEventResult.handled;
      }
      if (_isConfirm(key)) {
        _player.playOrPause();
        _show();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // 显示中：左右移动按钮焦点，确认激活
    if (key == LogicalKeyboardKey.arrowRight) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      _restartHideTimer();
      return KeyEventResult.handled;
    }
    if (_isConfirm(key)) {
      _activate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      _hide();
      return KeyEventResult.handled;
    }
    _restartHideTimer();
    return KeyEventResult.ignored;
  }

  /// 打开设置面板并在关闭后抢回焦点——弹窗会把系统焦点带走，
  /// 不手动要回来的话遥控器后续按键会“悄悄”没反应。
  Future<void> _openSettings() async {
    await widget.onShowSettings();
    if (mounted) _focusNode.requestFocus();
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
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: AppMotion.normal,
        curve: AppMotion.curve,
        child: IgnorePointer(
          ignoring: !_visible,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black54,
                  Colors.transparent,
                  Colors.transparent
                ],
                stops: [0, 0.35, 1],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(40, 24, 40, 28),
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
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _FrostedPanel(
                  child: Column(
                    children: [
                      _buildSeekBar(),
                      const SizedBox(height: 18),
                      _buildButtonRow(),
                    ],
                  ),
                ),
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
    return StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: _player.state.playing,
      builder: (_, snap) {
        final playing = snap.data ?? true;
        _actions = [
          (
            icon: Icons.replay_10,
            label: '快退',
            big: false,
            onTap: () => widget.onSeekBy(const Duration(seconds: -10)),
          ),
          (
            icon: playing ? Icons.pause : Icons.play_arrow,
            label: playing ? '暂停' : '播放',
            big: true,
            onTap: () => _player.playOrPause(),
          ),
          (
            icon: Icons.forward_10,
            label: '快进',
            big: false,
            onTap: () => widget.onSeekBy(const Duration(seconds: 10)),
          ),
          if (widget.isEpisode)
            (
              icon: Icons.skip_next,
              label: '下一集',
              big: false,
              onTap: widget.onNextEpisode,
            ),
          (
            icon: Icons.subtitles,
            label: '字幕和音频',
            big: false,
            onTap: _openSettings,
          ),
        ];
        if (_focusedIndex >= _actions.length) {
          _focusedIndex = _actions.length - 1;
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (i, a) in _actions.indexed)
              _TvButton(
                icon: a.icon,
                label: a.label,
                big: a.big,
                focused: i == _focusedIndex,
                onTap: () {
                  setState(() => _focusedIndex = i);
                  a.onTap();
                  _restartHideTimer();
                },
              ),
          ],
        );
      },
    );
  }
}

/// 毛玻璃底栏：进度条 + 按钮行的容器，磨砂材质质感（tvOS 播放器同款做法）。
class _FrostedPanel extends StatelessWidget {
  final Widget child;
  const _FrostedPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 电视控制按钮：聚焦时白圈高亮 + 放大 + 底部文字。
/// 焦点状态由外部（_TvControlsState）驱动，本身不持有 FocusNode。
class _TvButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool big;
  final bool focused;

  const _TvButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.focused,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = big ? 64.0 : 52.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: focused ? 1.15 : 1.0,
            duration: const Duration(milliseconds: 120),
            child: Material(
              color: focused ? Colors.white : Colors.white12,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Icon(
                    icon,
                    size: big ? 36 : 28,
                    color: focused ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: focused ? Colors.white : Colors.white60,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// 电视设置面板的一个可选项（字幕/音轨/倍速三段共用）。
class _TvMenuOption {
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  _TvMenuOption(this.label, this.selected, this.onSelect);
}

/// 电视设置面板：Netflix 式分栏——顶部「字幕 / 音轨 / 倍速」横向切
/// 换标签，下方纵向选具体项。左右切标签，下键从标签行落到列表，
/// 上键在列表首项时回到标签行，确认选中并关闭。全部自管理，不依赖
/// 框架默认方向焦点。
class _TvSettingsDialog extends StatefulWidget {
  final List<(String, List<_TvMenuOption>)> sections;
  const _TvSettingsDialog({required this.sections});

  @override
  State<_TvSettingsDialog> createState() => _TvSettingsDialogState();
}

class _TvSettingsDialogState extends State<_TvSettingsDialog> {
  final _focusNode = FocusNode(debugLabel: 'tv-settings');
  late final List<(String, List<_TvMenuOption>)> _tabs =
      widget.sections.where((s) => s.$2.isNotEmpty).toList();
  int _tabIndex = 0;
  bool _onTabs = true;
  int _itemIndex = 0;

  List<_TvMenuOption> get _currentOptions =>
      _tabs.isEmpty ? const [] : _tabs[_tabIndex].$2;

  @override
  void initState() {
    super.initState();
    // 默认停在已选中项所在的标签
    for (final (i, t) in _tabs.indexed) {
      final sel = t.$2.indexWhere((o) => o.selected);
      if (sel >= 0) {
        _tabIndex = i;
        _itemIndex = sel;
        break;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _changeTab(int delta) {
    if (_tabs.length < 2) return;
    setState(() {
      _tabIndex = (_tabIndex + delta).clamp(0, _tabs.length - 1);
      _itemIndex = 0;
    });
  }

  void _moveItem(int delta) {
    final n = _currentOptions.length;
    if (n == 0) return;
    setState(() => _itemIndex = (_itemIndex + delta).clamp(0, n - 1));
  }

  void _activate() {
    if (_currentOptions.isEmpty) return;
    _currentOptions[_itemIndex].onSelect();
    Navigator.of(context).pop();
  }

  bool _isConfirm(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.gameButtonA;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_onTabs) _changeTab(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_onTabs) _changeTab(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (_onTabs) {
        setState(() => _onTabs = false);
      } else {
        _moveItem(1);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (!_onTabs) {
        if (_itemIndex == 0) {
          setState(() => _onTabs = true);
        } else {
          _moveItem(-1);
        }
      }
      return KeyEventResult.handled;
    }
    if (_isConfirm(key)) {
      if (_onTabs) {
        setState(() => _onTabs = false);
      } else {
        _activate();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_tabs.isEmpty) {
      return const AlertDialog(title: Text('播放设置'), content: Text('没有可用选项'));
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AlertDialog(
        title: const Text('播放设置'),
        contentPadding: const EdgeInsets.only(bottom: 8),
        content: SizedBox(
          width: 420,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final (i, t) in _tabs.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _TvTabChip(
                          label: t.$1,
                          selected: i == _tabIndex,
                          focused: _onTabs && i == _tabIndex,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _currentOptions.length,
                  itemBuilder: (context, i) {
                    final o = _currentOptions[i];
                    final focused = !_onTabs && i == _itemIndex;
                    return Container(
                      color: focused
                          ? scheme.primary.withValues(alpha: 0.18)
                          : null,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.check,
                            size: 18,
                            color: o.selected
                                ? scheme.primary
                                : Colors.transparent),
                        title: Text(o.label,
                            style: focused
                                ? TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.bold)
                                : null),
                        onTap: () {
                          o.onSelect();
                          Navigator.of(context).pop();
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置面板顶部的标签胶囊：选中态描边高亮，聚焦态实心高亮。
class _TvTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool focused;

  const _TvTabChip({
    required this.label,
    required this.selected,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: focused
            ? kAccentFill
            : (selected
                ? scheme.primary.withValues(alpha: 0.18)
                : Colors.transparent),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: focused ? Colors.white : (selected ? scheme.primary : null),
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}
