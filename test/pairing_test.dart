import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xiaoya/api/models.dart';
import 'package:xiaoya/utils/pairing_server.dart';

void main() {
  test('局域网配对全流程：表单页 → 提交 → 成功页 → 链接失效', () async {
    PairingCredentials? received;
    final server = PairingServer(onSubmit: (creds) async {
      received = creds;
      return null; // 模拟登录成功
    });

    final url = await server.start();
    expect(url.scheme, 'http');
    final nonce = url.queryParameters['t']!;
    final client = HttpClient();

    Future<(int, String)> request(String method, Uri uri,
        {String? body}) async {
      final req = await client.openUrl(method, uri);
      if (body != null) {
        req.headers.contentType =
            ContentType('application', 'x-www-form-urlencoded');
        req.write(body);
      }
      final res = await req.close();
      return (res.statusCode, await utf8.decodeStream(res));
    }

    final base = Uri.parse('http://127.0.0.1:${url.port}');

    // 1. 错误 nonce 拒绝
    final (badCode, _) =
        await request('GET', base.replace(queryParameters: {'t': 'wrong'}));
    expect(badCode, HttpStatus.forbidden);

    // 2. 正确 nonce 拿到表单
    final (okCode, formHtml) =
        await request('GET', base.replace(queryParameters: {'t': nonce}));
    expect(okCode, HttpStatus.ok);
    expect(formHtml, contains('服务器地址'));

    // 3. 提交凭据
    final body = 't=$nonce&type=jellyfin'
        '&url=${Uri.encodeQueryComponent("https://demo.example.com:8096")}'
        '&name=${Uri.encodeQueryComponent("客厅")}'
        '&username=alice&password=secret';
    final (subCode, subHtml) =
        await request('POST', base.replace(path: '/submit'), body: body);
    expect(subCode, HttpStatus.ok);
    expect(subHtml, contains('配对成功'));
    expect(received, isNotNull);
    expect(received!.baseUrl, 'https://demo.example.com:8096');
    expect(received!.type, ServerType.jellyfin);
    expect(received!.username, 'alice');
    expect(received!.password, 'secret');

    // 4. 成功后链接失效
    final (goneCode, _) =
        await request('GET', base.replace(queryParameters: {'t': nonce}));
    expect(goneCode, HttpStatus.gone);

    client.close();
    await server.stop();
  });

  test('登录失败时返回错误并允许重试', () async {
    var calls = 0;
    final server = PairingServer(onSubmit: (creds) async {
      calls++;
      return calls == 1 ? '用户名或密码错误' : null;
    });
    final url = await server.start();
    final nonce = url.queryParameters['t']!;
    final client = HttpClient();
    final base = Uri.parse('http://127.0.0.1:${url.port}');

    Future<String> post(String body) async {
      final req = await client.postUrl(base.replace(path: '/submit'));
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      req.write(body);
      final res = await req.close();
      return utf8.decodeStream(res);
    }

    final body =
        't=$nonce&type=emby&url=http://e.io:8096&username=bob&password=x';
    expect(await post(body), contains('登录失败'));
    expect(await post(body), contains('配对成功'));

    client.close();
    await server.stop();
  });
}
