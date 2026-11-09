import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/lines.dart';
import '../models/parent_profile.dart';
import '../models/study_record.dart';
import '../services/attention_engine.dart';
import '../services/avatar_library.dart';
import '../services/face_monitor.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../widgets/avatar_view.dart';
import '../widgets/ui.dart';

/// 공부 화면: 타이머 + 카메라 감시 + 말하는 가상 부모 (사진 + 복제 목소리).
///
/// 규칙
///  · 자리에 있을 때만 시간이 줄어든다 (자리 비우면 멈춤).
///  · 졸음/자리 비움/딴짓을 감지하면 가상 부모가 부모 목소리로 지적, 집중하면 가끔 칭찬.
///  · 공부 중 다른 앱으로 나가면 시간이 멈추고, 돌아오면 한마디 듣는다.
class StudyScreen extends StatefulWidget {
  final ParentProfile profile;
  final int minutes;
  const StudyScreen({super.key, required this.profile, required this.minutes});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> with WidgetsBindingObserver {
  final _monitor = FaceMonitor();
  final _engine = AttentionEngine();
  final _avatar = AvatarController();
  late final _lib = AvatarLibrary(widget.profile.voiceId);
  final _clock = Stopwatch();
  final _startedAt = DateTime.now();

  StreamSubscription<FaceSample>? _sampleSub;
  Timer? _ticker;

  late int _remaining = widget.minutes * 60;
  int _studied = 0;
  int _drowsy = 0, _away = 0, _distracted = 0;
  bool _muted = false;

  bool _cameraReady = false;
  bool _gotFirstSample = false;
  String? _cameraError;
  bool _appPaused = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _sampleSub = _monitor.samples.listen(_onSample);
    _begin();
  }

  Future<void> _begin() async {
    await _avatar.init(await _lib.idleVideo());
    try {
      await _monitor.start();
      if (!mounted) return;
      setState(() => _cameraReady = true);
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _cameraError = '카메라를 켤 수 없어요.\n설정에서 카메라 권한을 허용해 주세요.');
      return;
    }
    _clock.start();
    _say(LineKind.start);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (_finished || _appPaused || !_gotFirstSample) return;
    if (!_engine.shouldCountTime) {
      setState(() {}); // 멈춤 표시만 갱신
      return;
    }
    setState(() {
      _remaining--;
      _studied++;
    });
    if (_remaining <= 0) _finish(completed: true);
  }

  void _onSample(FaceSample s) {
    if (_finished || _appPaused) return;
    final events = _engine.update(s, _clock.elapsed);
    setState(() => _gotFirstSample = true);
    if (events.isEmpty) return;
    for (final e in events) {
      switch (e) {
        case AttentionEvent.drowsy:
          _drowsy++;
        case AttentionEvent.away:
          _away++;
        case AttentionEvent.distracted:
          _distracted++;
        case AttentionEvent.returned:
        case AttentionEvent.praise:
          break;
      }
    }
    // 한 번에 여러 개면 마지막 것만 말한다 (보통 하나)
    _say(_kindFor(events.last));
  }

  static LineKind _kindFor(AttentionEvent e) => switch (e) {
        AttentionEvent.drowsy => LineKind.drowsy,
        AttentionEvent.away => LineKind.away,
        AttentionEvent.distracted => LineKind.distracted,
        AttentionEvent.returned => LineKind.returned,
        AttentionEvent.praise => LineKind.praise,
      };

  Future<void> _say(LineKind kind) async {
    if (_muted) return;
    try {
      final clip = await _lib.pick(kind,
          childCall: widget.profile.childCall, role: widget.profile.role);
      await _avatar.say(video: clip.video, audio: clip.audio, text: clip.text);
    } catch (_) {}
  }

  // 다른 앱으로 나가면 멈춤 → 돌아오면 "핸드폰 보는 거 아니지?"
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_finished || !_cameraReady) return;
    if (state == AppLifecycleState.paused) {
      _appPaused = true;
      _avatar.pauseAll();
      _monitor.stop();
    } else if (state == AppLifecycleState.resumed && _appPaused) {
      _resume();
    }
  }

  Future<void> _resume() async {
    try {
      await _monitor.start();
    } catch (_) {}
    await _avatar.resumeIdle();
    if (!mounted) return;
    setState(() {
      _appPaused = false;
      _distracted++;
    });
    _say(LineKind.distracted);
  }

  Future<void> _finish({required bool completed}) async {
    if (_finished) return;
    _finished = true;
    _ticker?.cancel();
    _clock.stop();
    await _monitor.stop();

    final record = StudyRecord(
      startedAt: _startedAt,
      plannedMinutes: widget.minutes,
      studiedSeconds: _studied,
      drowsyCount: _drowsy,
      awayCount: _away,
      distractedCount: _distracted,
      completed: completed,
    );
    await StorageService.addRecord(record);

    if (completed) {
      _muted = false;
      await _say(LineKind.finish);
    } else {
      await _avatar.stopTalking();
    }
    if (!mounted) return;
    await _showResult(record);
    if (mounted) Navigator.of(context).pop(record);
  }

  Future<void> _confirmQuit() async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('정말 그만할까?', style: AppText.base(20, w: FontWeight.w800)),
        content: Text('아직 ${_fmt(_remaining)} 남았어.',
            style: AppText.base(16, c: AppColors.inkSub)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('그만하기',
                  style: AppText.base(16, c: AppColors.inkSub))),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.sienna, shape: const StadiumBorder()),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('계속 할래',
                  style: AppText.base(16, w: FontWeight.w800, c: Colors.white))),
        ],
      ),
    );
    if (quit == true) await _finish(completed: false);
  }

  Future<void> _showResult(StudyRecord r) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(r.completed ? '목표 달성!' : '오늘은 여기까지',
            style: AppText.base(24, w: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.studiedSeconds ~/ 60}분',
                style: AppText.number(56, c: AppColors.siennaLight)),
            Text('목표 ${r.plannedMinutes}분 중',
                style: AppText.base(14, c: AppColors.inkSub)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: CountCard(count: r.drowsyCount, label: '졸음')),
                const SizedBox(width: 8),
                Expanded(child: CountCard(count: r.awayCount, label: '자리 비움')),
                const SizedBox(width: 8),
                Expanded(child: CountCard(count: r.distractedCount, label: '딴짓')),
              ],
            ),
          ],
        ),
        actions: [
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.sienna, shape: const StadiumBorder()),
              onPressed: () => Navigator.pop(ctx),
              child: Text('확인',
                  style: AppText.base(16, w: FontWeight.w800, c: Colors.white))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _ticker?.cancel();
    _sampleSub?.cancel();
    _monitor.dispose();
    _avatar.dispose();
    super.dispose();
  }

  // ───────── 화면 ─────────

  static String _fmt(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  ({String label, Color color}) get _statusView {
    if (_cameraError != null) return (label: '카메라 오류', color: AppColors.away);
    if (!_gotFirstSample) return (label: '카메라 준비 중', color: AppColors.inkSub);
    if (_appPaused) return (label: '멈춤', color: AppColors.away);
    return switch (_engine.status) {
      AttentionStatus.focused => (label: '집중 중', color: AppColors.focused),
      AttentionStatus.drowsy => (label: '졸음 감지', color: AppColors.drowsy),
      AttentionStatus.away => (label: '자리 비움 · 시간 멈춤', color: AppColors.away),
      AttentionStatus.lookingAway =>
        (label: '딴짓 감지', color: AppColors.distracted),
    };
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusView;
    final warn = _gotFirstSample && _engine.status != AttentionStatus.focused;
    final paused = _gotFirstSample && !_engine.shouldCountTime;
    final p = widget.profile;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_finished) _confirmQuit();
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusChip(
                        label: status.label,
                        color: status.color,
                        filled: true,
                        fontSize: 15),
                    const Spacer(),
                    if (_cameraReady && _monitor.controller != null)
                      _CameraThumb(controller: _monitor.controller!),
                  ],
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _avatar,
                    builder: (context, _) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AvatarView(
                          controller: _avatar,
                          photoPath: p.photoPath,
                          width: 260,
                          height: 300,
                          ringColor: warn ? status.color : AppColors.sienna,
                          glow: warn,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 80,
                          child: Center(
                            child: _avatar.caption != null
                                ? SpeechBubble(text: _avatar.caption!)
                                : Text('${p.role}가 보고 있어요',
                                    style: AppText.base(13,
                                        c: AppColors.inkSub)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                    _cameraError ??
                        (paused ? '자리로 돌아오면 다시 흘러가요' : '남은 시간'),
                    textAlign: TextAlign.center,
                    style: AppText.base(13,
                        w: FontWeight.w500,
                        c: _cameraError != null || paused
                            ? AppColors.away
                            : AppColors.inkSub)),
                Text(_fmt(_remaining),
                    style: AppText.number(76,
                        c: paused ? AppColors.away : AppColors.ink)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: CountCard(
                            count: _drowsy,
                            label: '졸음',
                            highlight: _engine.status == AttentionStatus.drowsy
                                ? AppColors.drowsy
                                : null)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: CountCard(
                            count: _away,
                            label: '자리 비움',
                            highlight: _engine.status == AttentionStatus.away
                                ? AppColors.away
                                : null)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: CountCard(
                            count: _distracted,
                            label: '딴짓',
                            highlight:
                                _engine.status == AttentionStatus.lookingAway
                                    ? AppColors.distracted
                                    : null)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    RoundIconButton(
                      icon: _muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      tooltip: _muted ? '소리 켜기' : '소리 끄기',
                      onPressed: () {
                        setState(() => _muted = !_muted);
                        if (_muted) _avatar.stopTalking();
                      },
                    ),
                    const SizedBox(width: 16),
                    RoundIconButton(
                      icon: Icons.stop_rounded,
                      tooltip: '그만하기',
                      onPressed: _cameraError != null
                          ? () => Navigator.of(context).pop()
                          : _confirmQuit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 아이가 "보고 있다"는 걸 알 수 있게 작은 카메라 화면.
class _CameraThumb extends StatelessWidget {
  final CameraController controller;
  const _CameraThumb({required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = controller.value.previewSize;
    if (!controller.value.isInitialized || size == null) {
      return const SizedBox.shrink();
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.5),
        child: SizedBox(
          width: 72,
          height: 96,
          child: FittedBox(
            fit: BoxFit.cover,
            // previewSize 는 가로 기준이라 세로 화면에서는 뒤집어 쓴다
            child: SizedBox(
              width: size.height,
              height: size.width,
              child: CameraPreview(controller),
            ),
          ),
        ),
      ),
    );
  }
}
