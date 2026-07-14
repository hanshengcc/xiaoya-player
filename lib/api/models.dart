/// Emby / Jellyfin 数据模型（两者 API 同源，共用一套模型）。
library;

enum ServerType { emby, jellyfin }

/// 已保存的服务器配置（含登录凭据）。
class ServerConfig {
  final String id; // 本地生成的唯一 id
  final String name; // 用户自定义显示名
  final String baseUrl; // http(s)://host:port，末尾不带 /
  final ServerType type;
  final String username;
  String? accessToken;
  String? userId;

  ServerConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.type,
    required this.username,
    this.accessToken,
    this.userId,
  });

  bool get isLoggedIn => accessToken != null && userId != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'type': type.name,
        'username': username,
        'accessToken': accessToken,
        'userId': userId,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        type: ServerType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ServerType.emby,
        ),
        username: json['username'] as String? ?? '',
        accessToken: json['accessToken'] as String?,
        userId: json['userId'] as String?,
      );
}

/// 媒体库视图（电影库、剧集库等）。
class LibraryView {
  final String id;
  final String name;
  final String? collectionType; // movies / tvshows / music ...
  final String? primaryImageTag;

  LibraryView({
    required this.id,
    required this.name,
    this.collectionType,
    this.primaryImageTag,
  });

  factory LibraryView.fromJson(Map<String, dynamic> json) => LibraryView(
        id: json['Id'] as String,
        name: json['Name'] as String? ?? '',
        collectionType: json['CollectionType'] as String?,
        primaryImageTag:
            (json['ImageTags'] as Map<String, dynamic>?)?['Primary'] as String?,
      );
}

/// 通用媒体条目：电影 / 剧集 / 季 / 集 / 文件夹。
class MediaItem {
  final String id;
  final String name;
  final String type; // Movie / Series / Season / Episode / BoxSet ...
  final String? overview;
  final String? seriesId;
  final String? seriesName;
  final String? seasonId;
  final int? indexNumber; // 集号
  final int? parentIndexNumber; // 季号
  final int? productionYear;
  final double? communityRating;
  final String? officialRating;
  final int? runTimeTicks;
  final String? primaryImageTag;
  final String? backdropImageTag;
  final String? imageItemId; // 取图用的 item id（集可能借用剧集封面）
  final int? playbackPositionTicks;
  final bool played;
  final bool isFavorite;
  final double? playedPercentage;
  final List<String> genres;

  MediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.overview,
    this.seriesId,
    this.seriesName,
    this.seasonId,
    this.indexNumber,
    this.parentIndexNumber,
    this.productionYear,
    this.communityRating,
    this.officialRating,
    this.runTimeTicks,
    this.primaryImageTag,
    this.backdropImageTag,
    this.imageItemId,
    this.playbackPositionTicks,
    this.played = false,
    this.isFavorite = false,
    this.playedPercentage,
    this.genres = const [],
  });

  bool get isVideo => type == 'Movie' || type == 'Episode' || type == 'Video';
  bool get isFolder =>
      type == 'Series' || type == 'Season' || type == 'BoxSet' ||
      type == 'Folder' || type == 'CollectionFolder';

  Duration? get runTime => runTimeTicks == null
      ? null
      : Duration(microseconds: runTimeTicks! ~/ 10);

  Duration get resumePosition =>
      Duration(microseconds: (playbackPositionTicks ?? 0) ~/ 10);

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final userData = json['UserData'] as Map<String, dynamic>? ?? const {};
    final imageTags = json['ImageTags'] as Map<String, dynamic>? ?? const {};
    final backdrops = json['BackdropImageTags'] as List<dynamic>? ?? const [];

    return MediaItem(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? '',
      type: json['Type'] as String? ?? '',
      overview: json['Overview'] as String?,
      seriesId: json['SeriesId'] as String?,
      seriesName: json['SeriesName'] as String?,
      seasonId: json['SeasonId'] as String?,
      indexNumber: json['IndexNumber'] as int?,
      parentIndexNumber: json['ParentIndexNumber'] as int?,
      productionYear: json['ProductionYear'] as int?,
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      officialRating: json['OfficialRating'] as String?,
      runTimeTicks: json['RunTimeTicks'] as int?,
      primaryImageTag: imageTags['Primary'] as String?,
      backdropImageTag: backdrops.isNotEmpty ? backdrops.first as String : null,
      imageItemId: json['Id'] as String,
      playbackPositionTicks: userData['PlaybackPositionTicks'] as int?,
      played: userData['Played'] as bool? ?? false,
      isFavorite: userData['IsFavorite'] as bool? ?? false,
      playedPercentage: (userData['PlayedPercentage'] as num?)?.toDouble(),
      genres: (json['Genres'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// 分页结果。
class ItemsResult {
  final List<MediaItem> items;
  final int totalCount;

  ItemsResult({required this.items, required this.totalCount});

  factory ItemsResult.fromJson(Map<String, dynamic> json) => ItemsResult(
        items: (json['Items'] as List<dynamic>? ?? const [])
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalCount: json['TotalRecordCount'] as int? ?? 0,
      );
}

/// 媒体流（音轨 / 字幕轨 / 视频轨），来自 PlaybackInfo。
class MediaStreamInfo {
  final int index;
  final String type; // Video / Audio / Subtitle
  final String? codec;
  final String? language;
  final String? displayTitle;
  final bool isDefault;
  final bool isExternal;
  final String? deliveryUrl; // 外挂字幕的下载路径（相对服务器）

  MediaStreamInfo({
    required this.index,
    required this.type,
    this.codec,
    this.language,
    this.displayTitle,
    this.isDefault = false,
    this.isExternal = false,
    this.deliveryUrl,
  });

  factory MediaStreamInfo.fromJson(Map<String, dynamic> json) =>
      MediaStreamInfo(
        index: json['Index'] as int? ?? 0,
        type: json['Type'] as String? ?? '',
        codec: json['Codec'] as String?,
        language: json['Language'] as String?,
        displayTitle: json['DisplayTitle'] as String?,
        isDefault: json['IsDefault'] as bool? ?? false,
        isExternal: json['IsExternal'] as bool? ?? false,
        deliveryUrl: json['DeliveryUrl'] as String?,
      );
}

/// 播放源信息。
class MediaSourceInfo {
  final String id;
  final String? container;
  final String? name;
  final int? bitrate;
  final bool supportsDirectPlay;
  final bool supportsDirectStream;
  final String? directStreamUrl;
  final String? transcodingUrl;
  final List<MediaStreamInfo> streams;

  MediaSourceInfo({
    required this.id,
    this.container,
    this.name,
    this.bitrate,
    this.supportsDirectPlay = true,
    this.supportsDirectStream = true,
    this.directStreamUrl,
    this.transcodingUrl,
    this.streams = const [],
  });

  factory MediaSourceInfo.fromJson(Map<String, dynamic> json) =>
      MediaSourceInfo(
        id: json['Id'] as String? ?? '',
        container: json['Container'] as String?,
        name: json['Name'] as String?,
        bitrate: json['Bitrate'] as int?,
        supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? true,
        supportsDirectStream: json['SupportsDirectStream'] as bool? ?? true,
        directStreamUrl: json['DirectStreamUrl'] as String?,
        transcodingUrl: json['TranscodingUrl'] as String?,
        streams: (json['MediaStreams'] as List<dynamic>? ?? const [])
            .map((e) => MediaStreamInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// PlaybackInfo 响应。
class PlaybackInfo {
  final String playSessionId;
  final List<MediaSourceInfo> mediaSources;

  PlaybackInfo({required this.playSessionId, required this.mediaSources});

  factory PlaybackInfo.fromJson(Map<String, dynamic> json) => PlaybackInfo(
        playSessionId: json['PlaySessionId'] as String? ?? '',
        mediaSources: (json['MediaSources'] as List<dynamic>? ?? const [])
            .map((e) => MediaSourceInfo.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
