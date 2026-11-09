import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config.dart';
import '../services/audio_service.dart';
import '../services/audio_utils.dart';
import '../theme.dart';

/// 가상 부모 말하기 관리.
///
/// 기본(사진 모드): 부모 사진 + 복제 목소리(wav). 말하는 동안 [level] 에
///   실제 목소리 크기(0~1)를 흘려보내 테두리·파형이 따라 움직인다.
/// HeyGen 모드(Config.useVideoAvatar): 대기 영상을 반복하다가 멘트 영상을 재생.
class AvatarController extends ChangeNotifier {
  final AudioService _audio = AudioService();

  /// 지금 목소리 크기 (0~1). 말하지 않으면 0.
  final ValueNotifier<double> level = ValueNotifier(0);

  VideoPlayerController? _idle;
  VideoPlayerController? _talk;
  bool _audioTalking = false;
  String? _caption;
  Timer? _levelTimer;
  int _seq = 0; // 말 끊기용 순번
  bool _disposed = false;

  VideoPlayerController? get idle => _idle;
  VideoPlayerController? get talk => _talk;
  String? get caption => _caption;
  bool get speaking => _talk != null || _audioTalking;

  /// HeyGen 모드에서만 대기 영상을 켠다. 사진 모드에서는 아무 일도 안 함.
  Future<void> init(String idlePath) async {
    if (!Config.useVideoAvatar || !File(idlePath).existsSync()) return;
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

  /// 한마디 하기. 끝날 때까지 기다리고 싶으면 반환값을 await.
  Future<void> say(
      {required String video, required String audio, required String text}) async {
    await stopTalking();
    if (_disposed) return;
    if (Config.useVideoAvatar && File(video).existsSync()) {
      await _sayVideo(video, text);
    } else if (File(audio).existsSync()) {
      await _sayAudio(audio, text);
    }
  }

  Future<void> _sayAudio(String path, String text) async {
    final my = ++_seq;
    final env = envelopeFromWav(await File(path).readAsBytes());
    if (_disposed || my != _seq) return;
    final done = _audio.completed.first;
    _audioTalking = true;
    _caption = text;
    notifyListeners();
    try {
      await _audio.playFile(path);
      final clock = Stopwatch()..start();
      _levelTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        // 살짝 부드럽게 따라가도록 이전 값과 섞는다
        level.value = level.value * 0.45 + env.at(clock.elapsed) * 0.55;
      });
      await done.timeout(env.duration + const Duration(seconds: 2),
          onTimeout: () {});
    } catch (_) {
      // 재생 실패·화면 닫힘 → 조용히 끝낸다
    }
    if (my == _seq && !_disposed) await stopTalking();
  }

  Future<void> _sayVideo(String path, String text) async {
    final my = ++_seq;
    final c = VideoPlayerController.file(File(path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    final done = Completer<void>();
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      return;
    }
    if (_disposed || my != _seq) {
      await c.dispose();
      return;
    }
    c.addListener(() {
      final v = c.value;
      final ended = v.isInitialized &&
          !v.isPlaying &&
          v.duration > Duration.zero &&
          v.position >= v.duration - const Duration(milliseconds: 150);
      if (ended && !done.isCompleted) done.complete();
    });
    _talk = c;
    _caption = text;
    notifyListeners();
    await c.setVolume(1);
    await c.play();
    await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    if (my == _seq && !_disposed) await stopTalking();
  }

  Future<void> stopTalking() async {
    _seq++;
    _levelTimer?.cancel();
    _levelTimer = null;
    level.value = 0;
    final wasAudio = _audioTalking;
    final c = _talk;
    _talk = null;
    _audioTalking = false;
    final hadCaption = _caption != null;
    _caption = null;
    if (!_disposed && (wasAudio || c != null || hadCaption)) notifyListeners();
    if (wasAudio) await _audio.stop();
    if (c != null) {
      await c.pause();
      await c.dispose();
    }
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
    _levelTimer?.cancel();
    _talk?.dispose();
    _idle?.dispose();
    _audio.dispose();
    level.dispose();
    super.dispose();
  }
}

/// 둥근 사각 프레임 안의 가상 부모.
///
/// 사진 모드 연출
///  · 평소: 숨 쉬듯 아주 살짝 커졌다 작아짐
///  · 말할 때: 테두리 두께·빛이 목소리 크기를 따라 출렁 + 아래쪽 파형 막대
class AvatarView extends StatefulWidget {
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
  State<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends State<AvatarView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 3600))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final listenable = c == null
        ? _breath
        : Listenable.merge([c, c.level, _breath]);
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) {
        final lvl = c?.level.value ?? 0;
        final speaking = c?.speaking ?? false;
        final ring = 3.0 + lvl * 5;
        final radius = BorderRadius.circular(widget.width * 0.16);
        final breathe = 1.0 + Curves.easeInOut.transform(_breath.value) * 0.015;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: widget.ringColor, width: ring),
            boxShadow: [
              if (widget.glow)
                BoxShadow(
                    color: widget.ringColor.withValues(alpha: 0.14),
                    spreadRadius: 10),
              BoxShadow(
                color: widget.ringColor.withValues(alpha: 0.25 + lvl * 0.35),
                blurRadius: 50 + lvl * 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius - BorderRadius.all(Radius.circular(ring)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (c?.idle != null)
                  _video(c!.idle!)
                else
                  Transform.scale(scale: breathe, child: _photo()),
                if (c?.talk != null) _video(c!.talk!),
                // 사진 모드에서 말하는 중이면 아래쪽에 파형
                if (speaking && c?.talk == null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: widget.height * 0.32,
                    child: _VoiceWave(level: lvl, maxHeight: widget.height * 0.14),
                  ),
              ],
            ),
          ),
        );
      },
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
    final f = File(widget.photoPath);
    if (widget.photoPath.isNotEmpty && f.existsSync()) {
      return Image.file(f, fit: BoxFit.cover);
    }
    return Container(
      color: AppColors.surface,
      child: Icon(Icons.person_outline_rounded,
          size: widget.width * 0.45, color: AppColors.inkFaint),
    );
  }
}

/// 목소리 크기를 따라 움직이는 막대 7개 (아래쪽 어두운 그라데이션 위).
class _VoiceWave extends StatelessWidget {
  final double level;
  final double maxHeight;
  const _VoiceWave({required this.level, required this.maxHeight});

  static const _shape = [0.45, 0.7, 0.9, 1.0, 0.9, 0.7, 0.45];

  @override
  Widget build(BuildContext context) {
    final t = DateTime.now().millisecondsSinceEpoch / 110.0;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00121110), Color(0xCC121110)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _shape.length; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Container(
                width: 6,
                // 막대마다 살짝 다른 박자로 흔들려 살아 있는 느낌
                height: 6 +
                    maxHeight *
                        level *
                        _shape[i] *
                        (0.7 + 0.3 * sin(t + i * 1.3)),
                decoration: BoxDecoration(
                  color: AppColors.siennaLight,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
