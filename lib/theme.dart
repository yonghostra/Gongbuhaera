import 'package:flutter/material.dart';

/// 공부해라 디자인 시스템.
///
/// 원칙 (화면 시안 기준)
///  · 화면마다 주인공 하나(아바타)를 가운데 크게, 나머지는 작게.
///  · 강조색은 시에나 하나만, 선택된 것·핵심 버튼에만.
///  · 안내는 회색 한 줄, 숫자는 아주 굵게.
///  · 알약 탭, 상태 칩, 동그란 아이콘 버튼.
class AppColors {
  static const bg = Color(0xFF121110); // 따뜻한 검정
  static const surface = Color(0xFF1D1A18);
  static const surfaceHi = Color(0xFF2A2522);
  static const line = Color(0xFF3A332E);
  static const ink = Color(0xFFF5F1EE);
  static const inkSub = Color(0xFFA39A93);
  static const inkFaint = Color(0xFF5A4F48);

  /// 시에나 — 버튼·선택 칸 채우기 (흰 글자와 대비 5.6:1)
  static const sienna = Color(0xFFA0522D);

  /// 밝은 시에나 — 어두운 배경 위 글자·점·진행 막대 (배경 대비 6.5:1)
  static const siennaLight = Color(0xFFE08A5B);

  // 상태 표시 (칩의 점·테두리에만 작게 쓴다)
  static const focused = Color(0xFF6FCF97);
  static const drowsy = Color(0xFFB39DFF);
  static const away = Color(0xFFFF7A6B);
  static const distracted = Color(0xFFFFD166);
}

class AppText {
  static const family = 'Pretendard';

  static TextStyle base(double size,
          {FontWeight w = FontWeight.w500,
          Color c = AppColors.ink,
          double? height,
          double? spacing}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: w,
        color: c,
        height: height,
        letterSpacing: spacing,
      );

  /// 타이머 같은 큰 숫자 (자릿수 폭 고정)
  static TextStyle number(double size, {Color c = AppColors.ink}) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: c,
        height: 1.05,
        letterSpacing: -size * 0.03,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.sienna,
      secondary: AppColors.siennaLight,
      surface: AppColors.surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceHi,
      behavior: SnackBarBehavior.floating,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: AppText.family,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
  );
}
