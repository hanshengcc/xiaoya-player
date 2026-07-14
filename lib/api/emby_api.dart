/// Emby / Jellyfin REST 客户端。
///
/// 两个服务端 API 基本兼容：认证头、/Users/AuthenticateByName、
/// /Users/{id}/Items、/Sessions/Playing 等端点一致，
/// `X-Emby-Token` 在 Jellyfin 上同样有效，因此一个客户端同时支持两者。
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';

class EmbyApiException implements Exception {
  final int? statusCode;
  final String message;
  EmbyApiException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

class EmbyApi {
  static const clientName = 'Xiaoya Player';
  static const clientVersion = '0.1.0';

  final ServerConfig server;
  final http.Client _http;
  final String deviceId;

  EmbyApi(this.server, {http.Client? client, String? deviceId})
      : _http = client ?? http.Client(),
        deviceId = deviceId ?? _stableDeviceId();

  static String? _cachedDeviceId;
  static String _stableDeviceId() {
    // 进程内稳定即可；持久化 id 由 AppState 注入
    return _cachedDeviceId ??= List.generate(
        16, (_) => Random().nextInt(16).toRadixString(16)).join();
  }

  String get _deviceName {
    try {
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isLinux) return 'Linux';
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
    } catch (_) {}
    return 'Flutter';
  }

  Map<String, String> get _headers {
    final auth = 'MediaBrowser Client="$clientName", Device="$_deviceName", '
        'DeviceId="$deviceId", Version="$clientVersion"'
        '${server.accessToken != null ? ', Token="${server.accessToken}"' : ''}';
    return {
      'Content-Type': 'application/json',
      'X-Emby-Authorization': auth,
      'Authorization': auth,
      if (server.accessToken != null) 'X-Emby-Token': server.accessToken!,
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = server.baseUrl.endsWith('/')
        ? server.baseUrl.substring(0, server.baseUrl.length - 1)
        : server.baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _getJson(String path,
      [Map<String, String>? query]) async {
    final res = await _http
        .get(_uri(path, query), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw EmbyApiException('请求失败: $path', statusCode: res.statusCode);
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> _postJson(String path, Map<String, dynamic> body) async {
    final res = await _http
        .post(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode >= 300) {
      throw EmbyApiException('请求失败: $path', statusCode: res.statusCode);
    }
  }

  // ---------------- 认证 ----------------

  /// 用户名密码登录，成功后回填 server.accessToken / userId。
  Future<void> authenticate(String password) async {
    final res = await _http
        .post(
          _uri('/Users/AuthenticateByName'),
          headers: _headers,
          body: jsonEncode({'Username': server.username, 'Pw': password}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw EmbyApiException('用户名或密码错误', statusCode: res.statusCode);
    }
    if (res.statusCode != 200) {
      throw EmbyApiException('登录失败', statusCode: res.statusCode);
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    server.accessToken = json['AccessToken'] as String?;
    server.userId =
        (json['User'] as Map<String, dynamic>?)?['Id'] as String?;
    if (!server.isLoggedIn) {
      throw EmbyApiException('登录响应缺少凭据');
    }
  }

  // ---------------- 浏览 ----------------

  Future<List<LibraryView>> getViews() async {
    final json = await _getJson('/Users/${server.userId}/Views');
    return (json['Items'] as List<dynamic>? ?? const [])
        .map((e) => LibraryView.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static const _defaultFields =
      'Overview,Genres,PrimaryImageAspectRatio,ProductionYear,'
      'OfficialRating,CommunityRating,RunTimeTicks,BackdropImageTags';

  /// 继续观看。
  Future<List<MediaItem>> getResumeItems({int limit = 12}) async {
    final json = await _getJson('/Users/${server.userId}/Items/Resume', {
      'Limit': '$limit',
      'MediaTypes': 'Video',
      'Fields': _defaultFields,
    });
    return ItemsResult.fromJson(json).items;
  }

  /// 最新入库。
  Future<List<MediaItem>> getLatestItems({String? parentId, int limit = 16}) async {
    final uri = _uri('/Users/${server.userId}/Items/Latest', {
      'Limit': '$limit',
      if (parentId != null) 'ParentId': parentId,
      'Fields': _defaultFields,
    });
    final res = await _http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw EmbyApiException('获取最新入库失败', statusCode: res.statusCode);
    }
    // 注意：Latest 端点直接返回数组而非 { Items: [...] }
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list
        .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 浏览媒体库（分页）。
  Future<ItemsResult> getItems({
    String? parentId,
    String? includeItemTypes,
    String? searchTerm,
    bool recursive = false,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    int startIndex = 0,
    int limit = 60,
  }) async {
    final json = await _getJson('/Users/${server.userId}/Items', {
      if (parentId != null) 'ParentId': parentId,
      if (includeItemTypes != null) 'IncludeItemTypes': includeItemTypes,
      if (searchTerm != null) 'SearchTerm': searchTerm,
      if (recursive) 'Recursive': 'true',
      'SortBy': sortBy,
      'SortOrder': sortOrder,
      'StartIndex': '$startIndex',
      'Limit': '$limit',
      'Fields': _defaultFields,
      'ImageTypeLimit': '1',
    });
    return ItemsResult.fromJson(json);
  }

  /// 单条目详情。
  Future<MediaItem> getItem(String itemId) async {
    final json = await _getJson('/Users/${server.userId}/Items/$itemId');
    return MediaItem.fromJson(json);
  }

  /// 剧集的季列表。
  Future<List<MediaItem>> getSeasons(String seriesId) async {
    final json = await _getJson('/Shows/$seriesId/Seasons', {
      'UserId': server.userId!,
      'Fields': _defaultFields,
    });
    return ItemsResult.fromJson(json).items;
  }

  /// 某季的集列表。
  Future<List<MediaItem>> getEpisodes(String seriesId, String seasonId) async {
    final json = await _getJson('/Shows/$seriesId/Episodes', {
      'UserId': server.userId!,
      'SeasonId': seasonId,
      'Fields': _defaultFields,
    });
    return ItemsResult.fromJson(json).items;
  }

  // ---------------- 播放 ----------------

  Future<PlaybackInfo> getPlaybackInfo(String itemId) async {
    final res = await _http
        .post(
          _uri('/Items/$itemId/PlaybackInfo', {
            'UserId': server.userId!,
          }),
          headers: _headers,
          body: jsonEncode({
            'DeviceProfile': {
              // mpv 几乎全格式直连，声明宽松 profile 避免服务端转码
              'MaxStreamingBitrate': 200000000,
              'DirectPlayProfiles': [
                {'Type': 'Video'},
                {'Type': 'Audio'},
              ],
            },
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw EmbyApiException('获取播放信息失败', statusCode: res.statusCode);
    }
    return PlaybackInfo.fromJson(
        jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// 直连播放地址（mpv 直接拉流）。
  String streamUrl(String itemId, MediaSourceInfo source) {
    final base = server.baseUrl.endsWith('/')
        ? server.baseUrl.substring(0, server.baseUrl.length - 1)
        : server.baseUrl;
    if (source.transcodingUrl != null && !source.supportsDirectPlay) {
      return '$base${source.transcodingUrl}';
    }
    return '$base/Videos/$itemId/stream?Static=true'
        '&MediaSourceId=${source.id}'
        '&DeviceId=$deviceId'
        '&api_key=${server.accessToken}';
  }

  /// 把服务器相对路径拼成绝对地址（如外挂字幕的 DeliveryUrl）。
  String absoluteUrl(String path) {
    final base = server.baseUrl.endsWith('/')
        ? server.baseUrl.substring(0, server.baseUrl.length - 1)
        : server.baseUrl;
    if (path.startsWith('http')) return path;
    var p = path.startsWith('/') ? path : '/$path';
    if (!p.contains('api_key') && server.accessToken != null) {
      p += p.contains('?') ? '&' : '?';
      p += 'api_key=${server.accessToken}';
    }
    return '$base$p';
  }

  /// 封面图地址。
  String imageUrl(
    String itemId, {
    String type = 'Primary',
    String? tag,
    int maxWidth = 400,
  }) {
    final base = server.baseUrl.endsWith('/')
        ? server.baseUrl.substring(0, server.baseUrl.length - 1)
        : server.baseUrl;
    var url = '$base/Items/$itemId/Images/$type?maxWidth=$maxWidth&quality=90';
    if (tag != null) url += '&tag=$tag';
    return url;
  }

  // ---------------- 进度上报 ----------------

  Future<void> reportPlaybackStart(
      String itemId, String mediaSourceId, String playSessionId) async {
    await _postJson('/Sessions/Playing', {
      'ItemId': itemId,
      'MediaSourceId': mediaSourceId,
      'PlaySessionId': playSessionId,
      'CanSeek': true,
      'PlayMethod': 'DirectPlay',
    });
  }

  Future<void> reportPlaybackProgress(
    String itemId,
    String mediaSourceId,
    String playSessionId,
    Duration position, {
    bool isPaused = false,
  }) async {
    await _postJson('/Sessions/Playing/Progress', {
      'ItemId': itemId,
      'MediaSourceId': mediaSourceId,
      'PlaySessionId': playSessionId,
      'PositionTicks': position.inMicroseconds * 10,
      'IsPaused': isPaused,
      'PlayMethod': 'DirectPlay',
    });
  }

  Future<void> reportPlaybackStopped(
    String itemId,
    String mediaSourceId,
    String playSessionId,
    Duration position,
  ) async {
    await _postJson('/Sessions/Playing/Stopped', {
      'ItemId': itemId,
      'MediaSourceId': mediaSourceId,
      'PlaySessionId': playSessionId,
      'PositionTicks': position.inMicroseconds * 10,
    });
  }

  // ---------------- 收藏 / 已看 ----------------

  Future<void> setFavorite(String itemId, bool favorite) async {
    final path = '/Users/${server.userId}/FavoriteItems/$itemId';
    if (favorite) {
      await _postJson(path, const {});
    } else {
      final res = await _http.delete(_uri(path), headers: _headers);
      if (res.statusCode >= 300) {
        throw EmbyApiException('取消收藏失败', statusCode: res.statusCode);
      }
    }
  }

  Future<void> setPlayed(String itemId, bool played) async {
    final path = '/Users/${server.userId}/PlayedItems/$itemId';
    if (played) {
      await _postJson(path, const {});
    } else {
      final res = await _http.delete(_uri(path), headers: _headers);
      if (res.statusCode >= 300) {
        throw EmbyApiException('标记未看失败', statusCode: res.statusCode);
      }
    }
  }

  void dispose() => _http.close();
}
