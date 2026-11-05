import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../data/lines.dart';
import '../models/parent_profile.dart';
import '../services/audio_service.dart';
import '../services/recorder_service.dart';
import '../services/storage_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/parent_avatar.dart';
import 'home_screen.dart';

/// 부모가 하는 최초 설정 (4단계).
///  1. 누구인지 + 아이 호칭
///  2. 사진
///  3. 동의 + 목소리 녹음
///  4. 가상 부모 만들기 (복제 + 멘트 30개 생성)
class SetupScreen extends StatefulWidget {
  /// 다시 설정할 때 기존 정보 (교체 후 예전 목소리를 지운다).
  final ParentProfile? previous;
  const SetupScreen({super.key, this.previous});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

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
  bool _working = false;
  // 복제는 성공했는데 말 만들기에서 실패한 경우, 다시 시도할 때 복제를 반복하지 않는다.
  String? _clonedVoiceId;
  String _workLabel = '';
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.previous;
    if (p != null) {
      _role = p.role;
      _callCtrl.text = p.childCall;
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _audio.dispose();
    _callCtrl.dispose();
    super.dispose();
  }

  // ───────── 동작 ─────────

  Future<void> _pickPhoto(ImageSource source) async {
    final x = await ImagePicker()
        .pickImage(source: source, maxWidth: 900, imageQuality: 85);
    if (x == null) return;
    final docs = await getApplicationDocumentsDirectory();
    final dest =
        '${docs.path}/parent_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(x.path).copy(dest);
    setState(() => _photoPath = dest);
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
      _clonedVoiceId = null;
    });
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _recordSec++);
      if (_recordSec >= _maxRecordSec) _stopRecord();
    });
  }

  Future<void> _stopRecord() async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    setState(() {
      _recording = false;
      if (_recordSec < _minRecordSec) {
        _voicePath = null;
      } else {
        _voicePath = path;
      }
    });
    if (_recordSec < _minRecordSec) {
      _snack('조금 더 길게 녹음해 주세요. (최소 $_minRecordSec초)');
    }
  }

  Future<void> _create() async {
    final voicePath = _voicePath;
    final photo = _photoPath;
    if (voicePath == null || photo == null) return;
    final service = VoiceService();
    final childCall = _callCtrl.text.trim();
    setState(() {
      _working = true;
      _error = null;
      _progress = 0;
      _workLabel = '$_role 목소리를 복제하는 중…';
    });
    try {
      final voiceId = _clonedVoiceId ??= await service.cloneVoice(
          name: '공부해라-$_role-${DateTime.now().millisecondsSinceEpoch}',
          audioPath: voicePath);
      await LineLibrary.generateAll(
        service: service,
        voiceId: voiceId,
        childCall: childCall,
        role: _role,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progress = done / total;
            _workLabel = '$_role 목소리로 말 만드는 중… ($done/$total)';
          });
        },
      );
      final profile = ParentProfile(
          role: _role,
          childCall: childCall,
          photoPath: photo,
          voiceId: voiceId);
      await StorageService.saveProfile(profile);

      // 다시 설정한 경우 예전 목소리 정리
      final prev = widget.previous;
      if (prev != null && prev.voiceId != voiceId) {
        unawaited(service.deleteVoice(prev.voiceId));
        unawaited(LineLibrary.deleteFiles(prev.voiceId));
      }

      // 완성 기념으로 첫 인사 들려주기
      final lib = LineLibrary(voiceId);
      await _audio.playFileAndWait(await lib.pick(LineKind.start));

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeScreen(profile: profile)),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = e.toString();
      });
    }
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('가상 부모 만들기 (${_step + 1}/4)',
            style: AppText.base(18, w: FontWeight.w700)),
        leading: _step > 0 && !_working
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _step--))
            : (widget.previous != null && !_working
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop())
                : null),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
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
                BigButton(
                  label: '다음',
                  onPressed:
                      _canNext ? () => setState(() => _step++) : null,
                )
              else if (!_working)
                BigButton(
                  label: _error == null ? '가상 $_role 만들기' : '다시 시도',
                  onPressed: _create,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t, style: AppText.base(24, w: FontWeight.w800, height: 1.3)),
            if (sub != null) ...[
              const SizedBox(height: 8),
              Text(sub,
                  style: AppText.base(15, c: AppColors.inkSub, height: 1.5)),
            ],
          ],
        ),
      );

  Widget _stepWho() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('누가 지켜볼까요?', '이 설정은 부모님이 직접 해 주세요.'),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
                value: '엄마', label: Text('엄마', style: AppText.base(18))),
            ButtonSegment(
                value: '아빠', label: Text('아빠', style: AppText.base(18))),
          ],
          selected: {_role},
          onSelectionChanged: (s) => setState(() => _role = s.first),
        ),
        const SizedBox(height: 32),
        Text('아이를 뭐라고 부르세요?', style: AppText.base(18, w: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('평소 부르는 그대로 써 주세요. 예) 민준아, 서연아',
            style: AppText.base(14, c: AppColors.inkSub)),
        const SizedBox(height: 12),
        TextField(
          controller: _callCtrl,
          style: AppText.base(20),
          maxLength: 10,
          decoration: InputDecoration(
            hintText: '민준아',
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _stepPhoto() {
    return Column(
      children: [
        _title('$_role 사진을 골라 주세요', '얼굴이 정면으로 크게 나온 사진이 좋아요.'),
        ParentAvatar(photoPath: _photoPath ?? '', size: 180),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text('앨범에서', style: AppText.base(16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text('지금 찍기', style: AppText.base(16)),
              ),
            ),
          ],
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
        _title('$_role 목소리를 녹음해 주세요',
            '조용한 곳에서 아래 글을 평소 말투로 읽어 주세요. 1분 이상이면 더 비슷해져요.'),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16)),
          child: Text(voiceScript, style: AppText.base(17, height: 1.7)),
        ),
        const SizedBox(height: 20),
        CheckboxListTile(
          value: _consent,
          onChanged: _recording
              ? null
              : (v) => setState(() => _consent = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            '녹음하는 사람은 본인($_role)이며, 목소리 복제를 위해 녹음 파일이 '
            '음성 AI 서비스(ElevenLabs)로 전송되는 것에 동의합니다.',
            style: AppText.base(14, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              Text('$mm:$ss',
                  style: AppText.base(40,
                      w: FontWeight.w800,
                      c: _recording ? AppColors.away : AppColors.ink)),
              Text(
                  _recording
                      ? '녹음 중… 다 읽으면 다시 눌러 주세요'
                      : (_voicePath != null
                          ? '녹음 완료! 다시 하려면 버튼을 누르세요'
                          : '최소 $_minRecordSec초'),
                  style: AppText.base(14, c: AppColors.inkSub)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _consent ? _toggleRecord : null,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !_consent
                        ? AppColors.surfaceHi
                        : (_recording ? AppColors.away : AppColors.accent),
                  ),
                  child: Icon(_recording ? Icons.stop : Icons.mic,
                      size: 48,
                      color: _consent ? Colors.black : AppColors.inkSub),
                ),
              ),
              if (_voicePath != null && !_recording)
                TextButton.icon(
                  onPressed: () => _audio.playFile(_voicePath!),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('들어보기', style: AppText.base(16)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepCreate() {
    return Column(
      children: [
        _title('가상 $_role를 만들어요',
            '목소리 복제와 말 $totalLineCount개 만들기에 1~2분 정도 걸려요. 앱을 끄지 말아 주세요.'),
        ParentAvatar(
            photoPath: _photoPath ?? '', size: 160, speaking: _working),
        const SizedBox(height: 32),
        if (_working) ...[
          LinearProgressIndicator(
            value: _progress == 0 ? null : _progress,
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
          const SizedBox(height: 14),
          Text(_workLabel, style: AppText.base(16, c: AppColors.inkSub)),
        ],
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.away.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12)),
            child: Text('만들지 못했어요.\n$_error',
                style: AppText.base(15, c: AppColors.away, height: 1.5)),
          ),
      ],
    );
  }
}
