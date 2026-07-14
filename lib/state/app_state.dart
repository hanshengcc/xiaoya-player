import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/emby_api.dart';
import '../api/models.dart';
import '../utils/tv.dart';

/// 全局应用状态：服务器列表、当前会话、主题设置。
class AppState extends ChangeNotifier {
  static const _kServers = 'servers';
  static const _kActiveServer = 'activeServerId';
  static const _kThemeMode = 'themeMode';
  static const _kDeviceId = 'deviceId';
  static const _kTvMode = 'tvMode';

  final List<ServerConfig> servers = [];
  ServerConfig? _active;
  EmbyApi? _api;
  ThemeMode themeMode = ThemeMode.system;
  late String deviceId;

  /// 电视模式：放大排版、overscan 边距、遥控器按键映射。
  /// Android TV 自动检测开启；设置页可手动覆盖。
  bool tvMode = false;

  SharedPreferences? _prefs;

  ServerConfig? get activeServer => _active;

  /// 当前服务器的 API 客户端；未登录时为 null。
  EmbyApi? get api => _api;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    deviceId = _prefs!.getString(_kDeviceId) ??
        List.generate(16, (_) => Random().nextInt(16).toRadixString(16)).join();
    await _prefs!.setString(_kDeviceId, deviceId);

    final raw = _prefs!.getStringList(_kServers) ?? const [];
    servers
      ..clear()
      ..addAll(raw.map((s) =>
          ServerConfig.fromJson(jsonDecode(s) as Map<String, dynamic>)));

    final mode = _prefs!.getString(_kThemeMode);
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == mode,
      orElse: () => ThemeMode.system,
    );

    // 电视模式：用户手动设过用用户的，否则自动检测
    tvMode = _prefs!.getBool(_kTvMode) ?? await detectTv();

    final activeId = _prefs!.getString(_kActiveServer);
    final match = servers.where((s) => s.id == activeId && s.isLoggedIn);
    if (match.isNotEmpty) {
      _setActive(match.first);
    }
    notifyListeners();
  }

  void _setActive(ServerConfig? server) {
    _api?.dispose();
    _active = server;
    _api = server == null ? null : EmbyApi(server, deviceId: deviceId);
  }

  Future<void> _persist() async {
    await _prefs?.setStringList(
        _kServers, servers.map((s) => jsonEncode(s.toJson())).toList());
    if (_active != null) {
      await _prefs?.setString(_kActiveServer, _active!.id);
    } else {
      await _prefs?.remove(_kActiveServer);
    }
  }

  /// 添加服务器并登录，成功后设为当前服务器。
  Future<void> addServerAndLogin({
    required String name,
    required String baseUrl,
    required ServerType type,
    required String username,
    required String password,
  }) async {
    final server = ServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toRadixString(36),
      name: name.isEmpty ? Uri.parse(baseUrl).host : name,
      baseUrl: baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
      type: type,
      username: username,
    );
    final api = EmbyApi(server, deviceId: deviceId);
    try {
      await api.authenticate(password);
    } finally {
      api.dispose();
    }
    servers.add(server);
    _setActive(server);
    await _persist();
    notifyListeners();
  }

  /// 重新登录已保存的服务器（token 失效时）。
  Future<void> relogin(ServerConfig server, String password) async {
    final api = EmbyApi(server, deviceId: deviceId);
    try {
      await api.authenticate(password);
    } finally {
      api.dispose();
    }
    _setActive(server);
    await _persist();
    notifyListeners();
  }

  void switchServer(ServerConfig server) {
    if (!server.isLoggedIn) return;
    _setActive(server);
    _persist();
    notifyListeners();
  }

  Future<void> removeServer(ServerConfig server) async {
    servers.remove(server);
    if (_active == server) {
      _setActive(servers.where((s) => s.isLoggedIn).firstOrNull);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    if (_active != null) {
      _active!.accessToken = null;
      _active!.userId = null;
    }
    _setActive(null);
    await _persist();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    await _prefs?.setString(_kThemeMode, mode.name);
    notifyListeners();
  }

  Future<void> setTvMode(bool value) async {
    tvMode = value;
    await _prefs?.setBool(_kTvMode, value);
    notifyListeners();
  }
}
