import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/tv_focus_highlight.dart';

/// 设置页：主题、账户。每组设置放一张圆角卡片里，不是一条条平铺到底——
/// 分组更清楚，也是 Netflix 设置页那种"一屏几大块"的排法。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SettingsSection(
            title: '外观',
            child: RadioGroup<ThemeMode>(
              groupValue: state.themeMode,
              onChanged: (m) => state.setThemeMode(m!),
              child: Column(
                children: [
                  TvFocusHighlight(
                    child: RadioListTile<ThemeMode>(
                        autofocus: state.tvMode,
                        title: const Text('跟随系统'),
                        value: ThemeMode.system),
                  ),
                  const TvFocusHighlight(
                    child: RadioListTile<ThemeMode>(
                        title: Text('浅色'), value: ThemeMode.light),
                  ),
                  const TvFocusHighlight(
                    child: RadioListTile<ThemeMode>(
                        title: Text('深色'), value: ThemeMode.dark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            title: '电视',
            child: TvFocusHighlight(
              child: SwitchListTile(
                title: const Text('电视模式'),
                subtitle: const Text('放大排版、遥控器按键适配（Android TV 自动开启）'),
                value: state.tvMode,
                onChanged: (v) => state.setTvMode(v),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            title: '账户',
            child: Column(
              children: [
                if (state.activeServer != null)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(state.activeServer!.username),
                    subtitle: Text(state.activeServer!.baseUrl),
                  ),
                TvFocusHighlight(
                  child: ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('退出登录'),
                    onTap: () async {
                      await context.read<AppState>().logout();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SettingsSection(
            title: '关于',
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('灯影'),
              subtitle: Text(
                  'v0.1.0 · Flutter + MPV (media_kit) · 支持 Emby / Jellyfin'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _SettingsSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: scheme.primary),
          ),
        ),
        Material(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}
