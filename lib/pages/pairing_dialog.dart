import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/app_state.dart';
import '../utils/pairing_server.dart';

/// 扫码配对弹层：显示二维码，等手机提交凭据并登录。
class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key});

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  PairingServer? _server;
  Uri? _url;
  String? _error;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final server = PairingServer(onSubmit: _onSubmit);
    _server = server;
    try {
      final url = await server.start();
      if (mounted) setState(() => _url = url);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<String?> _onSubmit(PairingCredentials creds) async {
    final state = context.read<AppState>();
    try {
      await state.addServerAndLogin(
        name: creds.name,
        baseUrl: creds.baseUrl,
        type: creds.type,
        username: creds.username,
        password: creds.password,
      );
    } catch (e) {
      return e.toString();
    }
    if (mounted) {
      setState(() => _success = true);
      // 手机端已看到成功页，稍候关弹层回首页
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
    }
    return null;
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('手机扫码配对'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_success) ...[
              Icon(Icons.check_circle, size: 64, color: scheme.primary),
              const SizedBox(height: 12),
              const Text('配对成功，正在进入…'),
            ] else if (_error != null) ...[
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
            ] else if (_url == null) ...[
              const CircularProgressIndicator(),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: _url.toString(),
                  size: 200,
                ),
              ),
              const SizedBox(height: 16),
              const Text('手机连同一 Wi-Fi，扫码填写服务器信息',
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              SelectableText(
                _url.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: scheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Text('等待手机提交…',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
