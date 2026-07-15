/// 局域网扫码配对：电视端起临时 HTTP 服务，手机扫码打开表单，
/// 提交服务器地址与账号密码，电视端拿到后走正常密码登录。
///
/// 安全设计：
/// - 一次性 nonce，URL 不带对不上就 403；
/// - 登录成功后服务立即关闭；
/// - 随机端口，只在配对弹层打开期间存活；
/// - 仅限局域网场景（家庭内网）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../api/models.dart';

class PairingCredentials {
  final String baseUrl;
  final String name;
  final ServerType type;
  final String username;
  final String password;

  PairingCredentials({
    required this.baseUrl,
    required this.name,
    required this.type,
    required this.username,
    required this.password,
  });
}

class PairingServer {
  /// 收到手机提交时回调；返回 null 表示登录成功，否则返回错误文案
  /// （会显示在手机页面上，手机可改完重新提交）。
  final Future<String?> Function(PairingCredentials) onSubmit;

  PairingServer({required this.onSubmit});

  HttpServer? _server;
  late final String _nonce = List.generate(
      24, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
  bool _done = false;

  /// 启动服务，返回手机要访问的 URL；无可用局域网地址时抛异常。
  Future<Uri> start() async {
    final ip = await _localIp();
    if (ip == null) {
      throw Exception('没有找到局域网地址，请确认已连接 Wi-Fi/网线');
    }
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server!.listen(_handle, onError: (_) {});
    return Uri.parse('http://$ip:${_server!.port}/?t=$_nonce');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static Future<String?> _localIp() async {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    String? candidate;
    for (final ni in interfaces) {
      for (final addr in ni.addresses) {
        final ip = addr.address;
        // 优先常见家庭网段
        if (ip.startsWith('192.168.') || ip.startsWith('10.')) return ip;
        candidate ??= ip;
      }
    }
    return candidate;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final res = req.response;
      res.headers.contentType = ContentType.html;

      if (_done) {
        res.statusCode = HttpStatus.gone;
        res.write(_page('配对已完成', '这个配对链接已失效。'));
      } else if (req.uri.queryParameters['t'] != _nonce &&
          req.uri.path != '/submit') {
        res.statusCode = HttpStatus.forbidden;
        res.write(_page('无效链接', '请重新扫电视上的二维码。'));
      } else if (req.method == 'POST' && req.uri.path == '/submit') {
        await _handleSubmit(req, res);
      } else {
        res.write(_formPage());
      }
      await res.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleSubmit(HttpRequest req, HttpResponse res) async {
    final body = await utf8.decodeStream(req);
    final form = Uri.splitQueryString(body);
    if (form['t'] != _nonce) {
      res.statusCode = HttpStatus.forbidden;
      res.write(_page('无效请求', '请重新扫电视上的二维码。'));
      return;
    }
    final creds = PairingCredentials(
      baseUrl: (form['url'] ?? '').trim(),
      name: (form['name'] ?? '').trim(),
      type: form['type'] == 'jellyfin' ? ServerType.jellyfin : ServerType.emby,
      username: (form['username'] ?? '').trim(),
      password: form['password'] ?? '',
    );
    final uri = Uri.tryParse(creds.baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      res.write(_page('地址不对', '服务器地址要含 http:// 或 https://，返回上页改一下。',
          back: true));
      return;
    }
    if (creds.username.isEmpty) {
      res.write(_page('缺用户名', '返回上页填一下用户名。', back: true));
      return;
    }

    final error = await onSubmit(creds);
    if (error == null) {
      _done = true;
      res.write(_page('✅ 配对成功', '电视已登录，可以关掉这个页面了。'));
    } else {
      res.write(_page('登录失败', '$error\n返回上页检查后重新提交。', back: true));
    }
  }

  String _page(String title, String message, {bool back = false}) => '''
<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title</title><style>${_css()}</style></head>
<body><main><h1>$title</h1><p>${message.replaceAll('\n', '<br>')}</p>
${back ? '<button onclick="history.back()">返回修改</button>' : ''}
</main></body></html>''';

  String _formPage() => '''
<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>灯影 配对</title><style>${_css()}</style></head>
<body><main>
<h1>连接到电视</h1>
<p>填好后提交，电视会自动登录。</p>
<form method="post" action="/submit">
<input type="hidden" name="t" value="$_nonce">
<label>服务器类型</label>
<div class="seg">
<label><input type="radio" name="type" value="emby" checked> Emby</label>
<label><input type="radio" name="type" value="jellyfin"> Jellyfin</label>
</div>
<label>服务器地址</label>
<input name="url" type="url" placeholder="https://emby.example.com:8096" required>
<label>名称（可选）</label>
<input name="name" type="text" placeholder="家里的 Emby">
<label>用户名</label>
<input name="username" type="text" required>
<label>密码</label>
<input name="password" type="password">
<button type="submit">提交并登录电视</button>
</form>
</main></body></html>''';

  static String _css() => '''
*{box-sizing:border-box;margin:0;padding:0}
body{font:16px/1.6 -apple-system,"PingFang SC",sans-serif;
  background:#101418;color:#e2e6ea;min-height:100vh;
  display:flex;align-items:center;justify-content:center;padding:20px}
main{width:100%;max-width:420px}
h1{font-size:22px;margin-bottom:8px;color:#8fb8d8}
p{color:#9aa4ad;margin-bottom:20px}
label{display:block;margin:14px 0 6px;font-size:14px;color:#b8c2cc}
input[type=url],input[type=text],input[type=password]{
  width:100%;padding:12px;border-radius:10px;border:1px solid #2a333c;
  background:#1a2129;color:#e2e6ea;font-size:16px}
.seg{display:flex;gap:16px}
.seg label{display:flex;align-items:center;gap:6px;margin:0}
button{width:100%;margin-top:24px;padding:14px;border:none;border-radius:10px;
  background:#4a7c9b;color:#fff;font-size:16px;font-weight:600}
''';
}
