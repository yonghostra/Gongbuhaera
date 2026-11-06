import 'package:flutter/material.dart';

import '../theme.dart';

/// 큰 알약 버튼 (핵심 동작 하나에만).
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const PillButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.sienna,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surface,
          shape: const StadiumBorder(),
        ),
        onPressed: onPressed,
        child: Text(label,
            style: AppText.base(19,
                w: FontWeight.w800,
                c: enabled ? Colors.white : AppColors.inkFaint)),
      ),
    );
  }
}

/// 동그란 아이콘 버튼 (보조 기능).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 52,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.42, color: AppColors.ink),
          ),
        ),
      ),
    );
  }
}

/// 점 + 짧은 글자 상태 칩. [filled] 면 색을 옅게 깔고 테두리를 칠한다.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final double fontSize;
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.filled = false,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: EdgeInsets.symmetric(
          horizontal: filled ? 16 : 14, vertical: filled ? 9 : 7),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        border: filled ? Border.all(color: color, width: 1.5) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: AppText.base(fontSize,
                  w: FontWeight.w700, c: filled ? color : AppColors.ink)),
        ],
      ),
    );
  }
}

/// 알약 모양 선택 탭.
class PillTabs<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  const PillTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == selected
                        ? AppColors.sienna
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(labelOf(v),
                      style: AppText.base(16,
                          w: FontWeight.w700,
                          c: v == selected ? Colors.white : AppColors.inkSub)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 숫자 + 이름 작은 카드 (졸음 0 / 자리 비움 1 …).
class CountCard extends StatelessWidget {
  final int count;
  final String label;
  final Color? highlight;
  const CountCard(
      {super.key, required this.count, required this.label, this.highlight});

  @override
  Widget build(BuildContext context) {
    final h = highlight;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: h == null ? AppColors.surface : h.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: h == null
            ? null
            : Border.all(color: h.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Text('$count',
              style: AppText.base(20, w: FontWeight.w800, c: h ?? AppColors.ink)),
          const SizedBox(height: 2),
          Text(label,
              style: AppText.base(12, c: h ?? AppColors.inkSub)),
        ],
      ),
    );
  }
}

/// 아바타 아래 말풍선 자막.
class SpeechBubble extends StatelessWidget {
  final String text;
  const SpeechBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: AppText.base(17,
              w: FontWeight.w700, c: AppColors.bg, height: 1.45)),
    );
  }
}

/// 큰 굵은 제목 + 회색 설명 한 줄.
class ScreenTitle extends StatelessWidget {
  final String title;
  final String? sub;
  const ScreenTitle({super.key, required this.title, this.sub});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.base(28, w: FontWeight.w800, height: 1.3)),
        if (sub != null) ...[
          const SizedBox(height: 8),
          Text(sub!,
              style: AppText.base(14, c: AppColors.inkSub, height: 1.5)),
        ],
      ],
    );
  }
}
