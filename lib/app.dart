import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'pages/servers_page.dart';
import 'state/app_state.dart';
import 'theme.dart';

class XiaoyaApp extends StatelessWidget {
  const XiaoyaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'Xiaoya Player',
      debugShowCheckedModeBanner: false,
      themeMode: state.themeMode,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      // 电视模式：整体放大 15%，3 米外可读；关闭时零影响
      builder: (context, child) {
        if (!state.tvMode || child == null) return child ?? const SizedBox();
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: const TextScaler.linear(1.15)),
          child: child,
        );
      },
      // 以服务器 id 作 key：切换服务器时强制重建首页、重新拉数据
      home: state.api != null
          ? HomePage(key: ValueKey(state.activeServer!.id))
          : const ServersPage(),
    );
  }
}
