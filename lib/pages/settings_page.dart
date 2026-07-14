import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// 设置页：主题、账户。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionHeader('外观'),
          RadioGroup<ThemeMode>(
            groupValue: state.themeMode,
            onChanged: (m) => state.setThemeMode(m!),
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                    title: Text('跟随系统'), value: ThemeMode.system),
                RadioListTile<ThemeMode>(
                    title: Text('浅色'), value: ThemeMode.light),
                RadioListTile<ThemeMode>(
                    title: Text('深色'), value: ThemeMode.dark),
              ],
            ),
          ),
          const Divider(),
          const _SectionHeader('电视'),
          SwitchListTile(
            title: const Text('电视模式'),
            subtitle: const Text('放大排版、遥控器按键适配（Android TV 自动开启）'),
            value: state.tvMode,
            onChanged: (v) => state.setTvMode(v),
          ),
          const Divider(),
          const _SectionHeader('账户'),
          if (state.activeServer != null)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(state.activeServer!.username),
              subtitle: Text(state.activeServer!.baseUrl),
            ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('退出登录'),
            onTap: () async {
              await context.read<AppState>().logout();
              if (context.mounted) {
                Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
          const Divider(),
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Xiaoya Player'),
            subtitle: Text('v0.1.0 · Flutter + MPV (media_kit) · 支持 Emby / Jellyfin'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
