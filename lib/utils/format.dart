/// 格式化工具。
library;

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// 片长的人类可读形式，如「1小时42分钟」。
String formatRuntime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0 && m > 0) return '$h小时$m分钟';
  if (h > 0) return '$h小时';
  return '$m分钟';
}
