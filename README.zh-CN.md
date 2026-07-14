# Xiaoya Player

[English](README.md) | **简体中文**

基于 **Flutter + MPV**（[media_kit](https://github.com/media-kit/media-kit)）的全平台 **Emby / Jellyfin** 播放器，简洁完整、配色舒服。

一套代码，六个目标平台：**macOS · Windows · Linux · Android · Android TV · iOS**。

## 亮点

- **MPV 播放内核** — 几乎全格式直连硬解（MKV、HEVC、EAC3、DTS……），不触发服务端转码
- **Emby 与 Jellyfin 双支持** — 两者 API 同源，一套客户端通吃；多服务器管理，一键切换
- **进度互通** — 每 10 秒 + 退出时回传播放进度，换任何设备接着看
- **自动连播** — 一集播完自动下一集，支持跨季
- **Android TV 适配** — leanback 桌面入口、D-pad 焦点导航（海报聚焦放大描边）、遥控器按键映射、大屏排版、overscan 安全边距
- **局域网扫码配对** — 电视上不用遥控器打密码：电视出二维码，手机扫码填表提交，电视自动登录。**不要求服务端开启 Quick Connect**，任何版本可用
- **舒服的界面** — Material 3，柔和青蓝配色，浅色/深色/跟随系统

## 功能一览

| 模块 | 说明 |
|---|---|
| 首页 | 继续观看（一键续播）、各库最新入库（滚动到视口才加载） |
| 浏览 | 网格无限滚动，按名称 / 入库时间 / 年份 / 评分排序 |
| 搜索 | 全库搜索，输入防抖 |
| 详情 | 电影续播/从头播，剧集按季浏览集列表，收藏 |
| 播放器 | 音轨/字幕切换（内嵌 + **Emby 外挂字幕**）、倍速、双击快进、全屏 |
| 遥控器 | 确认=播放/暂停 · 左右=±10 秒 · 上下=上/下一集 · 菜单=字幕/音轨/倍速面板 |
| 服务器 | 多服务器、会话持久化、重新登录、扫码配对 |

## 安装

到 [**Releases**](../../releases) 下载对应平台产物：

| 平台 | 产物 | 说明 |
|---|---|---|
| Android / Android TV | `xiaoya-*-android.apk` | `adb install` 或 U 盘安装；含 TV 桌面入口 |
| macOS | `xiaoya-*-macos.zip` | 未签名——首次启动右键 → 打开 |
| Windows | `xiaoya-*-windows.zip` | 解压运行 `xiaoya.exe` |
| Linux | `xiaoya-*-linux.tar.gz` | 需要 libmpv：`sudo apt install libmpv2 mpv` |

## 快速上手

1. 启动 → **添加服务器**
2. 填 Emby/Jellyfin 地址（`https://host:port`）、用户名、密码；电视上点 **手机扫码配对**，在手机上填
3. 开始看。进度自动回传服务器

## 源码构建

```bash
git clone https://github.com/hanshengcc/xiaoya-player.git
cd xiaoya-player
flutter pub get

flutter run -d macos      # 或 windows / linux / android / ios / chrome
flutter build apk --release
```

平台说明：

- **Linux**：`sudo apt install libmpv-dev mpv ninja-build libgtk-3-dev`
- **macOS/iOS**：需要完整 Xcode + CocoaPods
- **Web**：能跑但仅作 UI 预览（浏览器解不了 MKV/HEVC，跨域服务器还需 CORS）

## 架构

```
lib/
├── api/            # Emby/Jellyfin REST 客户端 + 数据模型
├── state/          # 全局状态：服务器、会话、主题、电视模式（持久化）
├── pages/          # 服务器 / 首页 / 库 / 详情 / 搜索 / 播放器 / 设置 / 配对
├── widgets/        # 海报卡片（焦点感知）、横向区块
└── utils/          # TV 检测、局域网配对 HTTP 服务、格式化
```

- **播放**：`media_kit` 全平台封装 libmpv；宽松 DeviceProfile 避免服务端转码
- **状态**：轻量 `provider` + `shared_preferences`
- **电视模式**：Android 上经 `UiModeManager` 自动检测，其他平台手动开关

## 许可证

[MIT](LICENSE)
