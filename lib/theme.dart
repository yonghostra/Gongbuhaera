import 'package:flutter/material.dart';

/// 공부해라 디자인 — 공부방 책상 위에서 오래 켜 둬도 눈이 편한 다크 톤.
class AppColors {
  static const bg = Color(0xFF101418);
  static const surface = Color(0xFF1A2129);
  static const surfaceHi = Color(0xFF24303B);
  static const ink = Color(0xFFF3F6F9);
  static const inkSub = Color(0xFF9AA8B6);
  static const line = Color(0xFF2E3B48);

  static const accent = Color(0xFFFFB547); // 메인 (따뜻한 주황)
  static const focused = Color(0xFF3DDC84); // 집중 중
  static const drowsy = Color(0xFFB18CFF); // 졸음
  static const away = Color(0xFFFF6B6B); // 자리 비움
  static const distracted = Color(0xFFFFD84D); // 딴짓
}

class AppText {
  static const family = 'Pretendard';

  static TextStyle base(double size,
          {FontWeight w = FontWeight.w500,
          Color c = AppColors.ink,
          double? height}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: w,
        color: c,
        height: height,
      );
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      surface: AppColors.surface,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: AppText.family,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
  );
}

/// 화면 공통 큰 버튼.
class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  const BigButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.color = AppColors.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.surfaceHi,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: onPressed,
        child: Text(label, style: AppText.base(19, w: FontWeight.w700, c: onPressed == null ? AppColors.inkSub : Colors.black)),
      ),
    );
  }
}
