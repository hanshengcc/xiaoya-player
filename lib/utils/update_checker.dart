import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 检查更新——直接读 GitHub Releases，不用自建服务端。
class UpdateInfo {
  final String version;
  final String notes;
  final String htmlUrl;
  final String? assetUrl; // 当前平台对应的产物直链；没找到就退回 htmlUrl

  UpdateInfo({
    required this.version,
    required this.notes,
    required this.htmlUrl,
    this.assetUrl,
  });
}

const _repo = 'hanshengcc/dengying-player';
const _kLastCheck = 'update_last_check_ms';

class UpdateChecker {
  /// 静默后台检查用：12 小时内查过就跳过，别老敲 GitHub API。
  static Future<UpdateInfo?> checkThrottled() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastCheck) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < const Duration(hours: 12).inMilliseconds) return null;
    await prefs.setInt(_kLastCheck, now);
    return check();
  }

  /// 手动点"检查更新"用：无条件查一次。
  static Future<UpdateInfo?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').replaceFirst(
          RegExp(r'^v'), '');
      if (tag.isEmpty || !_isNewer(tag, info.version)) return null;

      final assets = (json['assets'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      final keyword = _platformKeyword();
      final asset = assets.cast<Map<String, dynamic>?>().firstWhere(
            (a) => (a?['name'] as String? ?? '').contains(keyword),
            orElse: () => null,
          );

      return UpdateInfo(
        version: tag,
        notes: (json['body'] as String? ?? '').trim(),
        htmlUrl: json['html_url'] as String? ??
            'https://github.com/$_repo/releases/latest',
        assetUrl: asset?['browser_download_url'] as String?,
      );
    } catch (_) {
      // 断网、超时、GitHub 限流……静默失败，检查更新不该打断正常使用
      return null;
    }
  }

  static String _platformKeyword() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return '';
  }

  /// 版本号只用形如 x.y.z 的三段式，逐段比较，够用不用引第三方 semver 包。
  static bool _isNewer(String remote, String local) {
    List<int> parse(String v) => v
        .split(RegExp(r'[+\-]'))
        .first
        .split('.')
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    final r = parse(remote), l = parse(local);
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv != lv) return rv > lv;
    }
    return false;
  }
}
