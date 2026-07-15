import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../utils/update_checker.dart';

/// 新版本弹窗：桌面/手机直接打开下载链接；电视没有浏览器，改成扫码——
/// 跟配对登录用的是同一套"手机接手"思路。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  final tvMode = context.read<AppState>().tvMode;
  final url = info.assetUrl ?? info.htmlUrl;

  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('发现新版本 v${info.version}'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.notes.isNotEmpty)
                Text(info.notes, style: Theme.of(context).textTheme.bodyMedium),
              if (tvMode) ...[
                const SizedBox(height: 16),
                const Text('手机扫码下载新版本：'),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: QrImageView(data: url, size: 200),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          autofocus: tvMode,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tvMode ? '关闭' : '以后再说'),
        ),
        if (!tvMode)
          FilledButton(
            style: primaryCtaStyle(),
            onPressed: () {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              Navigator.of(context).pop();
            },
            child: const Text('去下载'),
          ),
      ],
    ),
  );
}
