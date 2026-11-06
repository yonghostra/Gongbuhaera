import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../data/lines.dart';
import '../models/parent_profile.dart';
import '../services/audio_service.dart';
import '../services/avatar_library.dart';
import '../services/avatar_service.dart';
import '../services/recorder_service.dart';
import '../services/storage_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/avatar_view.dart';
import '../widgets/ui.dart';
import 'home_screen.dart';

/// 부모가 하는 최초 설정 (4단계).
///  1. 누구인지 + 아이 호칭
///  2. 사진
///  3. 동의 + 목소리 녹음
///  4. 가상 부모 만들기
///     목소리 복제(ElevenLabs) → 멘트 30개 → 사진 아바타 등록(HeyGen) → 말하는 영상 31개
class SetupScreen extends StatefulWidget {
  /// 다시 만들 때 기존 정보 (완성 후 예전 목소리를 지운다).
  final ParentProfile? previous;

  /// 만들다 중단된 정보 (앱을 다시 켜면 이어서 만든다).
  final ParentProfile? resume;

  const SetupScreen({super.key, this.previous, this.resume});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

enum _Stage { ready, voice, lines, avatar, done }

class _SetupScreenState extends State<SetupScreen> {
  static const _minRecordSec = 30;
  static const _maxRecordSec = 180;

  int _step = 0;

  // 1단계
  String _role = '엄마';
  final _callCtrl = TextEditingController();

  // 2단계
  String? _photoPath;

  // 3단계
  bool _consent = false;
  final _recorder = RecorderService();
  final _audio = AudioService();
  bool _recording = false;
  int _recordSec = 0;
  Timer? _recordTimer;
  String? _voicePath;

  // 4단계
  _Stage _stage = _Stage.ready;
  String? _voiceId;
  String? _talkingPhotoId;
  int _linesDone = 0;
  int _videosDone = 0;
  String? _error;
  ParentProfile? _finished;
  AvatarController? _preview;

  bool get _working => _stage != _Stage.ready && _stage != _Stage.done && _error == null;

  @override
  void initState() {
    super.initState();
    final p = widget.resume ?? widget.previous;
    if (p != null) {
      _role = p.role;
      _callCtrl.text = p.childCall;
    }
    final r = widget.resume;
    if (r != null) {
      // 이어서 만들기: 녹음·업로드는 이미 끝났으니 바로 4단계로
      _photoPath = r.photoPath;
      _voiceId = r.voiceId;
      _talkingPhotoId = r.talkingPhotoId;
      _consent = true;
      _step = 3;
      WidgetsBinding.instance.addPostFrameCallback((_) => _create());
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _audio.dispose();
    _preview?.dispose();
    _callCtrl.dispose();
    super.dispose();
  }

  // ───────── 동작 ─────────

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, maxWidth: 1280, imageQuality: 90);
    if (x == null) return;
    final docs = await getApplicationDocumentsDirectory();
    final dest =
        '${docs.path}/parent_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy(dest);
    setState(() {
      _photoPath = dest;
      _talkingPhotoId = null; // 사진이 바뀌면 아바타도 새로
    });
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecord();
      return;
    }
    if (!await _recorder.hasPermission()) {
      _snack('마이크 권한이 필요해요. 설정에서 허용해 주세요.');
      return;
    }
    await _audio.stop();
    await _recorder.start();
    setState(() {
      _recording = true;
      _recordSec = 0;
      _voicePath = null;
      _voiceId = null; // 새로 녹음하면 복제도 새로
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordSec++);
      if (_recordSec >= _maxRecordSec) _stopRecord();
    });
  }

  Future<void> _stopRecord() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    final ok = _recordSec >= _minRecordSec;
    setState(() {
      _recording = false;
      _voicePath = ok ? path : null;
    });
    if (!ok) _snack('조금 더 길게 녹음해 주세요. (최소 $_minRecordSec초)');
  }

  Future<void> _create() async {
    final photo = _photoPath;
    if (photo == null) return;
    final voice = VoiceService();
    final avatar = AvatarService();
    final childCall = _callCtrl.text.trim();
    setState(() => _error = null);
    try {
      // 1) 목소리 복제
      setState(() => _stage = _Stage.voice);
      if (_voiceId == null) {
        final rec = _voicePath;
        if (rec == null) throw VoiceException('목소리 녹음이 없어요. 3단계에서 다시 녹음해 주세요.');
        _voiceId = await voice.cloneVoice(
            name: '공부해라-$_role-${DateTime.now().millisecondsSinceEpoch}',
            audioPath: rec);
      }
      final voiceId = _voiceId!;

      // 2) 멘트 30개
      setState(() => _stage = _Stage.lines);
      await AvatarLibrary.generateVoices(
        service: voice,
        voiceId: voiceId,
        childCall: childCall,
        role: _role,
        onProgress: (d, _) {
          if (mounted) setState(() => _linesDone = d);
        },
      );

      // 3) 사진 아바타 등록 → 진행 정보 저장 (앱을 꺼도 이어서 만들 수 있게)
      setState(() => _stage = _Stage.avatar);
      _talkingPhotoId ??= await avatar.uploadPhoto(photo);
      final profile = ParentProfile(
        role: _role,
        childCall: childCall,
        photoPath: photo,
        voiceId: voiceId,
        talkingPhotoId: _talkingPhotoId,
      );
      await StorageService.saveProfile(profile);

      // 4) 말하는 영상 31개
      await AvatarLibrary.generateVideos(
        service: avatar,
        voiceId: voiceId,
        talkingPhotoId: _talkingPhotoId!,
        onProgress: (d, _) {
          if (mounted) setState(() => _videosDone = d);
        },
      );

      // 다시 만든 경우 예전 것 정리
      final prev = widget.previous;
      if (prev != null && prev.voiceId != voiceId) {
        unawaited(voice.deleteVoice(prev.voiceId));
        unawaited(AvatarLibrary.deleteFiles(prev.voiceId));
      }

      if (!mounted) return;
      setState(() {
        _stage = _Stage.done;
        _finished = profile;
      });

      // 완성! 첫인사
      final lib = AvatarLibrary(voiceId);
      final ctrl = AvatarController();
      setState(() => _preview = ctrl);
      await ctrl.init(await lib.idleVideo());
      final hello = await lib.pick(LineKind.start, childCall: childCall, role: _role);
      await ctrl.say(hello.video, hello.text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _goHome() {
    final p = _finished;
    if (p == null) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeScreen(profile: p)),
      (_) => false,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg, style: AppText.base(15))));
  }

  bool get _canNext => switch (_step) {
        0 => _callCtrl.text.trim().isNotEmpty,
        1 => _photoPath != null,
        2 => _consent && _voicePath != null && !_recording,
        _ => false,
      };

  // ───────── 화면 ─────────

  @override
  Widget build(BuildContext context) {
    final canBack = !_working && _stage != _Stage.done;
    return PopScope(
      canPop: !_working,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (canBack && (_step > 0 || widget.previous != null))
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: RoundIconButton(
                          icon: _step > 0
                              ? Icons.arrow_back_rounded
                              : Icons.close_rounded,
                          tooltip: '뒤로',
                          size: 40,
                          onPressed: () => _step > 0
                              ? setState(() => _step--)
                              : Navigator.of(context).pop(),
                        ),
                      ),
                    Expanded(child: _progressBar()),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: switch (_step) {
                      0 => _stepWho(),
                      1 => _stepPhoto(),
                      2 => _stepVoice(),
                      _ => _stepCreate(),
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (_step < 3)
                  PillButton(
                    label: '다음',
                    onPressed: _canNext ? () => setState(() => _step++) : null,
                  )
                else if (_stage == _Stage.done)
                  PillButton(label: '시작하기', onPressed: _goHome)
                else if (_stage == _Stage.ready || _error != null)
                  PillButton(
                    label: _error == null ? '가상 $_role 만들기' : '이어서 다시 시도',
                    onPressed: _create,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressBar() => Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 6,
                decoration: BoxDecoration(
                  color: i <= _step ? AppColors.sienna : AppColors.surfaceHi,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      );

  Widget _stepWho() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ScreenTitle(
            title: '누가 지켜볼까요?', sub: '이 설정은 부모님이 직접 해 주세요.'),
        const SizedBox(height: 28),
        PillTabs<String>(
          values: const ['엄마', '아빠'],
          selected: _role,
          labelOf: (v) => v,
          onChanged: (v) => setState(() => _role = v),
        ),
        const SizedBox(height: 36),
        Text('아이를 뭐라고 부르세요?', style: AppText.base(18, w: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('평소 부르는 그대로 · 예) 민준아, 서연아',
            style: AppText.base(14, c: AppColors.inkSub)),
        const SizedBox(height: 14),
        TextField(
          controller: _callCtrl,
          style: AppText.base(20, w: FontWeight.w700),
          maxLength: 10,
          decoration: InputDecoration(
            hintText: '민준아',
            hintStyle: AppText.base(20, c: AppColors.inkFaint),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide:
                    const BorderSide(color: AppColors.siennaLight, width: 1.5)),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _stepPhoto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenTitle(
            title: '$_role 사진을\n골라 주세요',
            sub: '이 사진이 말하는 아바타가 돼요. 얼굴이 정면으로 크고 밝게 나온 사진이 좋아요.'),
        const SizedBox(height: 28),
        Center(
          child: AvatarView(
              controller: null,
              photoPath: _photoPath ?? '',
              width: 220,
              height: 260,
              ringColor: _photoPath == null ? AppColors.line : AppColors.sienna),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RoundIconButton(
                icon: Icons.photo_library_outlined,
                tooltip: '앨범에서 고르기',
                onPressed: () => _pickPhoto(ImageSource.gallery)),
            const SizedBox(width: 16),
            RoundIconButton(
                icon: Icons.photo_camera_outlined,
                tooltip: '지금 찍기',
                onPressed: () => _pickPhoto(ImageSource.camera)),
          ],
        ),
        const SizedBox(height: 10),
        Center(
          child: Text('앨범 · 카메라',
              style: AppText.base(13, c: AppColors.inkSub)),
        ),
      ],
    );
  }

  Widget _stepVoice() {
    final mm = (_recordSec ~/ 60).toString();
    final ss = (_recordSec % 60).toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenTitle(
            title: '$_role 목소리를\n녹음해 주세요',
            sub: '조용한 곳에서 평소 말투로 읽어 주세요. 1분 이상이면 더 비슷해져요.'),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20)),
          child: Text(voiceScript, style: AppText.base(16, height: 1.75)),
        ),
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _recording ? null : () => setState(() => _consent = !_consent),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _consent,
                  activeColor: AppColors.sienna,
                  onChanged: _recording
                      ? null
                      : (v) => setState(() => _consent = v ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '녹음하는 사람은 본인($_role)이며, 가상 부모를 만들기 위해 '
                      '내 목소리 녹음과 사진이 음성·영상 AI 서비스(ElevenLabs, HeyGen)로 '
                      '전송되는 것에 동의합니다.',
                      style: AppText.base(13, c: AppColors.inkSub, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              Text('$mm:$ss',
                  style: AppText.number(44,
                      c: _recording ? AppColors.away : AppColors.ink)),
              const SizedBox(height: 4),
              Text(
                  _recording
                      ? '녹음 중 · 다 읽으면 다시 눌러 주세요'
                      : (_voicePath != null
                          ? '녹음 완료 · 다시 하려면 누르세요'
                          : (_consent ? '최소 $_minRecordSec초' : '먼저 동의에 체크해 주세요')),
                  style: AppText.base(13, c: AppColors.inkSub)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    button: true,
                    label: _recording ? '녹음 멈추기' : '녹음 시작',
                    child: GestureDetector(
                      onTap: _consent ? _toggleRecord : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: !_consent
                              ? AppColors.surface
                              : (_recording ? AppColors.away : AppColors.sienna),
                        ),
                        child: Icon(
                            _recording ? Icons.stop_rounded : Icons.mic_rounded,
                            size: 40,
                            color: _consent ? Colors.white : AppColors.inkFaint),
                      ),
                    ),
                  ),
                  if (_voicePath != null && !_recording) ...[
                    const SizedBox(width: 16),
                    RoundIconButton(
                        icon: Icons.play_arrow_rounded,
                        tooltip: '들어보기',
                        onPressed: () => _audio.playFile(_voicePath!)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepCreate() {
    final total = AvatarClip.all.length;
    final linesTotal = AvatarClip.lines.length;
    if (_stage == _Stage.done) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ScreenTitle(title: '가상 $_role 완성!', sub: '이제 공부할 때 $_role가 지켜봐 줄 거예요.'),
          const SizedBox(height: 28),
          Center(
            child: AvatarView(
                controller: _preview,
                photoPath: _photoPath ?? '',
                width: 260,
                height: 300),
          ),
          const SizedBox(height: 18),
          if (_preview != null)
            ListenableBuilder(
              listenable: _preview!,
              builder: (_, _) => _preview!.caption == null
                  ? const SizedBox(height: 60)
                  : Center(child: SpeechBubble(text: _preview!.caption!)),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScreenTitle(
            title: _working ? '$_role 아바타를\n만들고 있어요' : '가상 $_role를\n만들어요',
            sub: '10~15분 정도 걸려요. 화면을 켜 둔 채로 기다려 주세요. 중간에 꺼져도 다시 열면 이어서 만들어요.'),
        const SizedBox(height: 24),
        Center(
          child: AvatarView(
              controller: null,
              photoPath: _photoPath ?? '',
              width: 180,
              height: 212),
        ),
        const SizedBox(height: 24),
        _task('목소리 복제',
            done: _stage.index > _Stage.voice.index,
            active: _stage == _Stage.voice),
        const SizedBox(height: 8),
        _task('$_role 목소리로 말 $linesTotal개',
            done: _stage.index > _Stage.lines.index,
            active: _stage == _Stage.lines,
            count: '$_linesDone / $linesTotal',
            progress: _linesDone / linesTotal),
        const SizedBox(height: 8),
        _task('말하는 아바타 영상',
            done: false,
            active: _stage == _Stage.avatar,
            count: '$_videosDone / $total',
            progress: _videosDone / total),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.away.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18)),
            child: Text('잠깐 멈췄어요. 다시 시도하면 이어서 만들어요.\n$_error',
                style: AppText.base(14, c: AppColors.away, height: 1.5)),
          ),
        ],
      ],
    );
  }

  Widget _task(String label,
      {required bool done,
      required bool active,
      String? count,
      double? progress}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: active
            ? AppColors.sienna.withValues(alpha: 0.16)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: active
            ? Border.all(
                color: AppColors.siennaLight.withValues(alpha: 0.55),
                width: 1.5)
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? AppColors.sienna : Colors.transparent,
                  border: done
                      ? null
                      : Border.all(
                          color: active
                              ? AppColors.siennaLight
                              : AppColors.line,
                          width: 2.5),
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 18, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(label,
                      style: AppText.base(15,
                          w: FontWeight.w700,
                          c: done || active ? AppColors.ink : AppColors.inkSub))),
              if (done)
                Text('완료', style: AppText.base(13, c: AppColors.inkSub))
              else if (active && count != null)
                Text(count,
                    style: AppText.number(15, c: AppColors.siennaLight)),
            ],
          ),
          if (active && progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress == 0 ? null : progress,
                minHeight: 8,
                color: AppColors.siennaLight,
                backgroundColor: AppColors.surfaceHi,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
