import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/models.dart';
import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/errors.dart';
import '../utils/pairing_server.dart';
import '../widgets/tv_focus_highlight.dart';
import 'pairing_dialog.dart';

/// 服务器管理页：列表 + 添加登录。首次启动时作为入口。
class ServersPage extends StatelessWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      // 首次启动的空态是登录入口，不是管理页——去掉 AppBar 铬边，
      // 让下面的暗场氛围铺满全屏，跟 Netflix 的登录门页一个调子。
      appBar: state.servers.isEmpty
          ? null
          : AppBar(title: Text(L.of(context).servers)),
      body: state.servers.isEmpty
          ? _EmptyHint(onAdd: () => _showAddSheet(context))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: state.servers.length,
              itemBuilder: (context, i) {
                final s = state.servers[i];
                final active = state.activeServer == s;
                return TvFocusHighlight(
                  child: ListTile(
                    autofocus: i == 0 && state.tvMode,
                    leading: Icon(
                      s.type == ServerType.emby
                          ? Icons.dns_outlined
                          : Icons.storage_outlined,
                      color:
                          active ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(s.name),
                    subtitle: Text('${s.baseUrl} · ${s.username}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (active)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.check_circle, size: 20),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: L.of(context).delete,
                          onPressed: () => _confirmDelete(context, s),
                        ),
                      ],
                    ),
                    onTap: () {
                      if (s.isLoggedIn) {
                        state.switchServer(s);
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      } else {
                        _showAddSheet(context, relogin: s);
                      }
                    },
                  ),
                );
              },
            ),
      // 空态登录门页的添加/配对入口已经并排放在正文里了，这里的悬浮
      // 按钮只服务"已有服务器、还想再加一个"的场景，不重复。
      floatingActionButton: state.servers.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 局域网扫码配对：浏览器端起不了 HTTP 服务，web 隐藏
                if (!kIsWeb)
                  TvFocusHighlight(
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                    child: FloatingActionButton.extended(
                      heroTag: 'pair',
                      onPressed: () => showDialog(
                          context: context,
                          builder: (_) => const PairingDialog()),
                      icon: const Icon(Icons.qr_code_2),
                      label: Text(L.of(context).pairViaPhone),
                    ),
                  ),
                const SizedBox(height: 12),
                TvFocusHighlight(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  child: FloatingActionButton.extended(
                    heroTag: 'add',
                    onPressed: () => _showAddSheet(context),
                    icon: const Icon(Icons.add),
                    label: Text(L.of(context).addServer),
                  ),
                ),
              ],
            ),
    );
  }

  void _confirmDelete(BuildContext context, ServerConfig s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L.of(context).deleteServerTitle),
        content: Text(L.of(context).deleteServerConfirm(s.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.of(context).cancel)),
          FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(L.of(context).delete)),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<AppState>().removeServer(s);
    }
  }

  void _showAddSheet(BuildContext context, {ServerConfig? relogin}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // 用弹层自己的 context，不是外层传进来的——外层页面登录成功后
      // 会被 popUntil 弹掉、context 失效，这时候如果还拿它查 MediaQuery
      // 会直接崩（"Looking up a deactivated widget's ancestor"）。
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _AddServerForm(relogin: relogin),
      ),
    );
  }
}

/// 首次启动的登录门页——固定暗场，不跟随浅色/深色主题。这是用户见到
/// 的第一屏，Netflix 式的克制：一个品牌名、一句话、两个并排动作。
///
/// "手机扫码配对"不再弹独立弹窗切走界面——焦点移到这个按钮上（遥控器
/// 移过去，或鼠标点一下）就在同一屏下方直接展开二维码，跟"添加服务器"
/// 表单一样都是这屏内的状态切换，不是导航到别的路由。
class _EmptyHint extends StatefulWidget {
  final VoidCallback onAdd;
  const _EmptyHint({required this.onAdd});

  @override
  State<_EmptyHint> createState() => _EmptyHintState();
}

class _EmptyHintState extends State<_EmptyHint> {
  PairingServer? _pairingServer;
  Uri? _pairingUrl;
  String? _pairingError;
  bool _pairingSuccess = false;
  bool _qrRevealed = false;

  @override
  void dispose() {
    _pairingServer?.stop();
    super.dispose();
  }

  Future<void> _ensurePairingStarted() async {
    if (_pairingServer != null) return;
    final server = PairingServer(onSubmit: _onPairingSubmit);
    _pairingServer = server;
    try {
      final url = await server.start();
      if (mounted) setState(() => _pairingUrl = url);
    } catch (e) {
      if (mounted) setState(() => _pairingError = friendlyError(context, e));
    }
  }

  Future<String?> _onPairingSubmit(PairingCredentials creds) async {
    final state = context.read<AppState>();
    try {
      await state.addServerAndLogin(
        name: creds.name,
        baseUrl: creds.baseUrl,
        type: creds.type,
        username: creds.username,
        password: creds.password,
      );
    } catch (e) {
      return friendlyError(context, e);
    }
    // 不用导航——state 更新后 ServersPage 会自己从空态切到列表页。
    if (mounted) setState(() => _pairingSuccess = true);
    return null;
  }

  void _revealQr() {
    setState(() => _qrRevealed = true);
    _ensurePairingStarted();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tvMode = context.watch<AppState>().tvMode;
    final l = L.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 1.3,
          colors: [
            scheme.primary.withValues(alpha: 0.28),
            Colors.black,
          ],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.appName,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      )),
              const SizedBox(height: 16),
              Text(l.addServerHint,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white70)),
              const SizedBox(height: 28),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvFocusHighlight(
                    borderRadius: const BorderRadius.all(Radius.circular(24)),
                    child: FilledButton.icon(
                      style: primaryCtaStyle(),
                      autofocus: tvMode,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        widget.onAdd();
                      },
                      icon: const Icon(Icons.add),
                      label: Text(l.addServer),
                    ),
                  ),
                  if (!kIsWeb) ...[
                    const SizedBox(width: 12),
                    Focus(
                      onFocusChange: (focused) {
                        setState(() => _qrRevealed = focused);
                        if (focused) _ensurePairingStarted();
                      },
                      child: TvFocusHighlight(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(24)),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _revealQr();
                          },
                          icon: const Icon(Icons.qr_code_2),
                          label: Text(l.pairViaPhone),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!kIsWeb) ...[
                const SizedBox(height: 28),
                // 固定预留这块区域的高度——二维码显示/隐藏只是这块内容
                // 淡入淡出，不改变外层 Column 的总高度，上面两个按钮的
                // 位置就不会跟着跳动。
                SizedBox(
                  height: 200,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: (_qrRevealed || _pairingSuccess) ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !(_qrRevealed || _pairingSuccess),
                        child: _buildPairingPanel(scheme, l),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPairingPanel(ColorScheme scheme, L l) {
    if (_pairingSuccess) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 48, color: scheme.primary),
          const SizedBox(height: 8),
          Text(l.pairingSuccess, style: const TextStyle(color: Colors.white)),
        ],
      );
    }
    if (_pairingError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: scheme.error),
          const SizedBox(height: 8),
          Text(_pairingError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ],
      );
    }
    if (_pairingUrl == null) {
      return const CircularProgressIndicator.adaptive();
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: QrImageView(data: _pairingUrl.toString(), size: 160),
    );
  }
}

class _AddServerForm extends StatefulWidget {
  final ServerConfig? relogin;
  const _AddServerForm({this.relogin});

  @override
  State<_AddServerForm> createState() => _AddServerFormState();
}

class _AddServerFormState extends State<_AddServerForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.relogin?.name ?? '');
  late final _url = TextEditingController(text: widget.relogin?.baseUrl ?? '');
  late final _user =
      TextEditingController(text: widget.relogin?.username ?? '');
  final _password = TextEditingController();
  ServerType _type = ServerType.emby;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.relogin != null) _type = widget.relogin!.type;
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = context.read<AppState>();
    try {
      if (widget.relogin != null) {
        widget.relogin!
          ..accessToken = null
          ..userId = null;
        await state.relogin(widget.relogin!, _password.text);
      } else {
        await state.addServerAndLogin(
          name: _name.text.trim(),
          baseUrl: _url.text.trim(),
          type: _type,
          username: _user.text.trim(),
          password: _password.text,
        );
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      setState(() => _error = friendlyError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRelogin = widget.relogin != null;
    final tvMode = context.watch<AppState>().tvMode;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(isRelogin ? L.of(context).reloginTitle : L.of(context).addServer,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              SegmentedButton<ServerType>(
                segments: const [
                  ButtonSegment(value: ServerType.emby, label: Text('Emby')),
                  ButtonSegment(
                      value: ServerType.jellyfin, label: Text('Jellyfin')),
                ],
                selected: {_type},
                onSelectionChanged:
                    isRelogin ? null : (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                enabled: !isRelogin,
                autofocus: tvMode && !isRelogin,
                decoration: InputDecoration(
                  labelText: L.of(context).serverAddress,
                  hintText: 'https://emby.example.com:8096',
                  prefixIcon: const Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  final u = Uri.tryParse(v?.trim() ?? '');
                  if (u == null || !u.hasScheme || u.host.isEmpty) {
                    return L.of(context).invalidUrlError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                enabled: !isRelogin,
                decoration: InputDecoration(
                  labelText: L.of(context).nameOptional,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _user,
                enabled: !isRelogin,
                decoration: InputDecoration(
                  labelText: L.of(context).username,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? L.of(context).usernameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofocus: tvMode && isRelogin,
                decoration: InputDecoration(
                  labelText: L.of(context).password,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                style: primaryCtaStyle(),
                onPressed: _busy
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        _submit();
                      },
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white)))
                    : Text(isRelogin ? L.of(context).login : L.of(context).connectAndLogin),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
