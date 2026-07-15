import 'dart:async';

import '../api/emby_api.dart';

/// 把异常转成人话给用户看。`EmbyApiException` 本来就是我们自己写的
/// 友好文案，原样用；网络传输层的异常（超时、DNS 解析失败、连接被拒）
/// toString() 是一坨 Dart/IO 内部堆栈文本，不能直接甩给用户。
String friendlyError(Object e) {
  if (e is EmbyApiException) return e.toString();

  final s = e.toString();
  if (e is TimeoutException || s.contains('TimeoutException')) {
    return '连接超时，请检查网络';
  }
  if (s.contains('SocketException') ||
      s.contains('Connection refused') ||
      s.contains('Failed host lookup') ||
      s.contains('Network is unreachable')) {
    return '无法连接到服务器，请检查网络或服务器地址';
  }
  if (s.contains('HandshakeException') || s.contains('CERTIFICATE')) {
    return '安全连接失败，请检查服务器证书';
  }
  return '加载失败，请重试';
}
