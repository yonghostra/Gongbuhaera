import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 동그란 부모 사진. 말하는 중이면 테두리가 맥박처럼 커졌다 작아진다.
class ParentAvatar extends StatefulWidget {
  final String photoPath;
  final double size;
  final Color ringColor;
  final bool speaking;

  const ParentAvatar({
    super.key,
    required this.photoPath,
    this.size = 200,
    this.ringColor = AppColors.accent,
    this.speaking = false,
  });

  @override
  State<ParentAvatar> createState() => _ParentAvatarState();
}

class _ParentAvatarState extends State<ParentAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void didUpdateWidget(covariant ParentAvatar old) {
    super.didUpdateWidget(old);
    if (widget.speaking && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.speaking && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.photoPath);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final ring = 5.0 + _pulse.value * 7;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: widget.size + ring * 2,
          height: widget.size + ring * 2,
          padding: EdgeInsets.all(ring),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.ringColor,
            boxShadow: [
              BoxShadow(
                color: widget.ringColor.withValues(alpha: 0.35),
                blurRadius: 24 + _pulse.value * 16,
              ),
            ],
          ),
          child: child,
        );
      },
      child: ClipOval(
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : Container(
                color: AppColors.surfaceHi,
                child: Icon(Icons.person,
                    size: widget.size * 0.6, color: AppColors.inkSub),
              ),
      ),
    );
  }
}
