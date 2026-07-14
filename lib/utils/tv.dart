/// Android TV 检测。
///
/// 通过 MethodChannel 问原生 UiModeManager 是否为电视 UI 模式；
/// 非 Android 平台或通道不可用时一律返回 false，不影响既有平台。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('xiaoya/device');

Future<bool> detectTv() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    return await _channel.invokeMethod<bool>('isTv') ?? false;
  } catch (_) {
    return false;
  }
}
