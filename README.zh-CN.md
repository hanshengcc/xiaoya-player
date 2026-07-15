# Xiaoya Player

[English](README.md) | **简体中文**

### 你的 Emby / Jellyfin 片库，配得上一个这么好用的播放器。

Xiaoya Player 是一款给你自己片库用的播放器——快、好看、什么格式都能播，电视上用起来就是你熟悉的那套操作，不用重新学。

一个 App，覆盖你在乎的所有设备：**macOS · Windows · Linux · Android · Android TV · iOS**。

---

## 为什么选 Xiaoya

**什么格式都能播，不折腾。** 基于 MPV 内核，MKV、HEVC、EAC3、DTS，不管你的片源是什么格式，硬解直播，不用服务端转码，不用为了"兼容"重新压一遍片库。

**电视上就是 Netflix 那味儿。** 屏上播放控制、真正好用的字幕音轨面板、遥控器随时知道你在哪。指哪按哪，见下方 [遥控器](#遥控器)。

**进度到哪都跟着你。** 换设备自动接着看，电视上暂停，手机上继续。一集播完自动接下一集，一路追到季终。

**密码只用打一次。** 用遥控器在电视上打密码是种折磨。手机扫个码，服务器信息在手机上填，电视自动登录。不需要服务端开 Quick Connect，Emby、Jellyfin 都能用。

**哪个平台都好看。** 各平台观感统一：干净的字体排版、顺滑的动效、恰到好处的层次感——不是那种一眼就能认出"这是跨平台框架默认样式"的糙感。

**Emby、Jellyfin 一个 App 全搞定。** 想加几个服务器加几个，一键切换。

---

## 遥控器

| 按键 | 观看时 |
|---|---|
| 确认 | 呼出控制层 / 播放 / 暂停 |
| 左 · 右 | 快退 / 快进 10 秒 |
| 上 · 下 | 呼出控制层 |
| 菜单键（或遥控器上的字幕键，如果有） | 打开字幕、音轨、倍速面板 |
| 返回 | 先收起控制层，再退出播放 |

播放时控制层会自动淡出，一碰遥控器就回来；暂停时常驻不收，不会看着看着找不到进度条。字幕、音轨、倍速都在一个面板里，不用翻半天菜单。不管在首页、详情页还是库列表，进去遥控器立刻能用，不用瞎按找焦点。

## 功能一览

| 模块 | 说明 |
|---|---|
| 首页 | 继续观看（一键续播）、各库最新入库 |
| 浏览 | 网格无限滚动，按名称 / 入库时间 / 年份 / 评分排序 |
| 搜索 | 边输入边搜全库 |
| 详情 | 续播/从头播，剧集按季浏览集列表，收藏 |
| 播放器 | 音轨/字幕切换（内嵌 + **Emby 外挂字幕**）、倍速、双击快进、全屏 |
| 服务器 | 多服务器、会话持久化、重新登录、扫码配对 |

## 下载安装

到 [**Releases**](../../releases) 下载对应平台产物：

| 平台 | 产物 | 说明 |
|---|---|---|
| Android / Android TV | `xiaoya-*-android.apk` | `adb install` 或 U 盘安装；电视上自动识别成电视应用 |
| macOS | `xiaoya-*-macos.zip` | 未签名——首次启动右键 → 打开 |
| Windows | `xiaoya-*-windows.zip` | 解压运行 `xiaoya.exe` |
| Linux | `xiaoya-*-linux.tar.gz` | 需要 libmpv：`sudo apt install libmpv2 mpv` |

## 快速上手

1. 启动 → **添加服务器**
2. 填 Emby/Jellyfin 地址、用户名、密码；电视上点 **手机扫码配对**，在手机上填更方便
3. 开始看。进度到哪都跟着你

---

<details>
<summary><strong>给开发者</strong> —— 源码构建、项目结构</summary>

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

```
lib/
├── api/            # Emby/Jellyfin REST 客户端 + 数据模型
├── state/          # 全局状态：服务器、会话、主题、电视模式（持久化）
├── pages/          # 服务器 / 首页 / 库 / 详情 / 搜索 / 播放器 / 设置 / 配对
├── widgets/        # 海报卡片、横向区块、电视聚焦高亮
└── utils/          # TV 检测、局域网配对 HTTP 服务、格式化
```

- **播放**：`media_kit` 全平台封装 libmpv；宽松 DeviceProfile 避免服务端转码
- **状态**：轻量 `provider` + `shared_preferences`
- **电视模式**：Android 上经 `UiModeManager` 自动检测，其他平台手动开关

</details>

## 许可证

[MIT](LICENSE)
