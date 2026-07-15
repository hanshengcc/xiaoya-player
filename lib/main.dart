import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 mpv 内核
  MediaKit.ensureInitialized();

  final state = AppState();
  await state.load();

  runApp(
    ChangeNotifierProvider.value(
      value: state,
      child: const DengYingApp(),
    ),
  );
}
