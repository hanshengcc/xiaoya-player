import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

const _fontFamily = 'PlusJakartaSans';

/// 全局设计语言：字号、圆角、动效曲线统一在这里定义，
/// 页面里不再各自散落魔法数字。
class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const pill = 999.0;
}

class AppMotion {
  static const fast = Duration(milliseconds: 160);
  static const normal = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutQuint;
}

/// 主题种子色：柔和的青蓝，观感舒适、暗色下不刺眼。
const _seed = Color(0xFF4A7C9B);

/// 品牌强调色，专给"需要在任何主题下都醒目"的实心填充用（主 CTA 按钮、
/// 聚焦态选中的标签）。`scheme.primary` 在深色模式会被 Material3 自动
/// 提亮成浅色调（tone ~80，为了跟深色文字够对比度），大面积实心色块
/// 用它会发白发糯、没有品牌辨识度；这个常量不随主题切换，两种模式下
/// 都是同一个笃定的颜色。
const kAccentFill = _seed;

/// 主 CTA 按钮样式——每个页面"这个最重要"的那一个动作用它：详情页的
/// 播放、登录门页的添加服务器、表单提交。品牌色实心 + 白字 + 阴影，
/// 跟其他 FilledButton（重试之类的次要动作）拉开层级。
ButtonStyle primaryCtaStyle() => FilledButton.styleFrom(
      backgroundColor: kAccentFill,
      foregroundColor: Colors.white,
      elevation: 3,
      shadowColor: kAccentFill.withValues(alpha: 0.5),
    );

ThemeData buildAppTheme(Brightness brightness) {
  var scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);

  if (brightness == Brightness.dark) {
    // Material3 默认暗色是偏蓝灰的"浅黑"；换成更深的近纯黑背景，
    // 层次靠 surfaceContainer 的微妙灰阶区分，观感更接近 tvOS/Apple TV。
    scheme = scheme.copyWith(
      surface: const Color(0xFF08090B),
      surfaceContainerLowest: const Color(0xFF000000),
      surfaceContainerLow: const Color(0xFF0F1113),
      surfaceContainer: const Color(0xFF15181B),
      surfaceContainerHigh: const Color(0xFF1C2024),
      surfaceContainerHighest: const Color(0xFF23282D),
    );
  }

  final base = ThemeData(brightness: brightness)
      .textTheme
      .apply(fontFamily: _fontFamily);
  final textTheme = base
      .copyWith(
        headlineSmall: base.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: base.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        bodyMedium: base.bodyMedium?.copyWith(height: 1.45),
      )
      .apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      );

  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.pill),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: shape,
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.primaryContainer,
      labelStyle: textTheme.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    ),
    // 不在这儿给 FilledButton 强制配色——FilledButtonThemeData 这一个
    // style 对象会同时套到 FilledButton 和 FilledButton.tonal 上（Flutter
    // 没有分开的主题槽位），强行统一颜色会把"重试"这种次要按钮跟主 CTA
    // 拉平，反而丢了层级。主 CTA 用 primaryCtaStyle() 单独在各自按钮上指定。
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        textStyle: textTheme.labelLarge,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: shape),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      elevation: 2,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      iconColor: scheme.onSurfaceVariant,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      backgroundColor: scheme.surfaceContainerHigh,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      circularTrackColor: scheme.surfaceContainerHighest,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
    ),
  );
}
