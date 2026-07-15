import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/errors.dart';
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
      appBar: state.servers.isEmpty ? null : AppBar(title: const Text('服务器')),
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
                          tooltip: '删除',
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
      floatingActionButton: Column(
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
                    context: context, builder: (_) => const PairingDialog()),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('手机扫码配对'),
              ),
            ),
          const SizedBox(height: 12),
          TvFocusHighlight(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            child: FloatingActionButton.extended(
              heroTag: 'add',
              onPressed: () => _showAddSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('添加服务器'),
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
        title: const Text('删除服务器'),
        content: Text('确定删除「${s.name}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
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
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AddServerForm(relogin: relogin),
      ),
    );
  }
}

/// 首次启动的登录门页——固定暗场，不跟随浅色/深色主题。这是用户见到
/// 的第一屏，Netflix 式的克制：一个品牌名、一句话、一个动作，没有别的。
class _EmptyHint extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyHint({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tvMode = context.watch<AppState>().tvMode;
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
              Text('灯影',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      )),
              const SizedBox(height: 16),
              Text('添加一个 Emby 或 Jellyfin 服务器开始使用',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.white70)),
              const SizedBox(height: 28),
              TvFocusHighlight(
                borderRadius: const BorderRadius.all(Radius.circular(24)),
                child: FilledButton.icon(
                  style: primaryCtaStyle(),
                  autofocus: tvMode,
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('添加服务器'),
                ),
              ),
            ],
          ),
        ),
      ),
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
      setState(() => _error = friendlyError(e));
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
              Text(isRelogin ? '重新登录' : '添加服务器',
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
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'https://emby.example.com:8096',
                  prefixIcon: Icon(Icons.link),
                ),
                keyboardType: TextInputType.url,
                validator: (v) {
                  final u = Uri.tryParse(v?.trim() ?? '');
                  if (u == null || !u.hasScheme || u.host.isEmpty) {
                    return '请输入完整地址（含 http:// 或 https://）';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                enabled: !isRelogin,
                decoration: const InputDecoration(
                  labelText: '名称（可选）',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _user,
                enabled: !isRelogin,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofocus: tvMode && isRelogin,
                decoration: const InputDecoration(
                  labelText: '密码',
                  prefixIcon: Icon(Icons.lock_outline),
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
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(isRelogin ? '登录' : '连接并登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
