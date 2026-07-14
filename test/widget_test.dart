import 'package:flutter_test/flutter_test.dart';

import 'package:xiaoya/api/models.dart';

void main() {
  test('ServerConfig JSON 往返', () {
    final server = ServerConfig(
      id: 'abc',
      name: '家里的 Emby',
      baseUrl: 'https://emby.example.com:8096',
      type: ServerType.emby,
      username: 'alice',
      accessToken: 'token',
      userId: 'uid',
    );
    final restored = ServerConfig.fromJson(server.toJson());
    expect(restored.id, server.id);
    expect(restored.baseUrl, server.baseUrl);
    expect(restored.type, ServerType.emby);
    expect(restored.isLoggedIn, isTrue);
  });

  test('MediaItem 解析与续播位置', () {
    final item = MediaItem.fromJson(const {
      'Id': '1',
      'Name': '测试电影',
      'Type': 'Movie',
      'RunTimeTicks': 36000000000, // 1 小时
      'UserData': {
        'PlaybackPositionTicks': 18000000000, // 30 分钟
        'Played': false,
        'PlayedPercentage': 50.0,
      },
    });
    expect(item.isVideo, isTrue);
    expect(item.runTime, const Duration(hours: 1));
    expect(item.resumePosition, const Duration(minutes: 30));
    expect(item.playedPercentage, 50.0);
  });
}
