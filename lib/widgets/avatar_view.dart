import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';

/// 가상 부모 영상 재생 관리.
///
/// 평소에는 말없이 끄덕이는 대기 영상(idle.mp4)을 소리 없이 반복하고,
/// [say] 를 부르면 해당 멘트 영상(소리 포함)을 위에 틀었다가 끝나면 대기 영상으로 돌아간다.
class AvatarController extends ChangeNotifier {
  VideoPlayerController? _idle;
  VideoPlayerController? _talk;
  String? _caption;
  bool _disposed = false;

  VideoPlayerController? get idle => _idle;
  VideoPlayerController? get talk => _talk;
  String? get caption => _caption;
  bool get speaking => _talk != null;

  Future<void> init(String idlePath) async {
    if (!File(idlePath).existsSync()) return;
    final c = VideoPlayerController.file(File(idlePath),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(true);
      await c.play();
    } catch (_) {
      await c.dispose();
      return;
    }
    if (_disposed) {
      await c.dispose();
      return;
    }
    _idle = c;
    notifyListeners();
  }

  /// 멘트 영상 재생. 끝날 때까지 기다리고 싶으면 반환값을 await.
  Future<void> say(String videoPath, String text) async {
    await stopTalking();
    if (!File(videoPath).existsSync()) return;
    final c = VideoPlayerController.file(File(videoPath),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    final done = Completer<void>();
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      return;
    }
    if (_disposed) {
      await c.dispose();
      return;
    }
    void listener() {
      final v = c.value;
      final ended = v.isInitialized &&
          !v.isPlaying &&
          v.duration > Duration.zero &&
          v.position >= v.duration - const Duration(milliseconds: 150);
      if (ended && !done.isCompleted) done.complete();
    }

    c.addListener(listener);
    _talk = c;
    _caption = text;
    notifyListeners();
    await c.setVolume(1);
    await c.play();
    await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    if (identical(_talk, c)) await stopTalking();
  }

  Future<void> stopTalking() async {
    final c = _talk;
    if (c == null) return;
    _talk = null;
    _caption = null;
    if (!_disposed) notifyListeners();
    await c.pause();
    await c.dispose();
  }

  /// 앱이 뒤로 갈 때 등
  Future<void> pauseAll() async {
    await stopTalking();
    await _idle?.pause();
  }

  Future<void> resumeIdle() async => _idle?.play();

  @override
  void dispose() {
    _disposed = true;
    _talk?.dispose();
    _idle?.dispose();
    super.dispose();
  }
}

/// 둥근 사각 프레임 안의 가상 부모. 영상이 없으면 사진을 보여준다.
class AvatarView extends StatelessWidget {
  final AvatarController? controller;
  final String photoPath;
  final double width;
  final double height;
  final Color ringColor;
  final bool glow;

  const AvatarView({
    super.key,
    required this.controller,
    required this.photoPath,
    this.width = 270,
    this.height = 320,
    this.ringColor = AppColors.sienna,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width * 0.16);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: ringColor, width: 3),
        boxShadow: [
          if (glow)
            BoxShadow(color: ringColor.withValues(alpha: 0.14), spreadRadius: 10),
          BoxShadow(
              color: ringColor.withValues(alpha: 0.28),
              blurRadius: 60,
              offset: const Offset(0, 24)),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius - const BorderRadius.all(Radius.circular(3)),
        child: controller == null
            ? _photo()
            : ListenableBuilder(
                listenable: controller!,
                builder: (context, _) {
                  final c = controller!;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (c.idle != null) _video(c.idle!) else _photo(),
                      if (c.talk != null) _video(c.talk!),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _video(VideoPlayerController v) => FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: v.value.size.width,
          height: v.value.size.height,
          child: VideoPlayer(v),
        ),
      );

  Widget _photo() {
    final f = File(photoPath);
    if (photoPath.isNotEmpty && f.existsSync()) {
      return Image.file(f, fit: BoxFit.cover);
    }
    return Container(
      color: AppColors.surface,
      child: Icon(Icons.person_outline_rounded,
          size: width * 0.45, color: AppColors.inkFaint),
    );
  }
}
