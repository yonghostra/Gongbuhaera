import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// 부모 목소리 재생.
///
/// (말벗에서 실기기로 검증한 설정을 그대로 가져옴)
/// iOS: 녹음과 재생이 번갈아 되도록 playAndRecord 로 고정해야 녹음이 무음이 안 된다.
/// Android: usage=media 여야 무음 모드 폰에서도 소리가 난다.
class AudioService {
  static final AudioContext _ctx = AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playAndRecord,
      options: const {
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.allowBluetooth,
        AVAudioSessionOptions.allowBluetoothA2DP,
      },
    ),
    android: AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  static Future<void> configureSession() async {
    try {
      await AudioPlayer.global.setAudioContext(_ctx);
    } catch (_) {}
  }

  final AudioPlayer _player = AudioPlayer();
  bool _applied = false;

  /// 지금 말하는 중인지 (부모 사진 테두리 애니메이션용).
  Stream<bool> get speaking =>
      _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  Future<void> _ensureCtx() async {
    if (_applied) return;
    _applied = true;
    try {
      await _player.setAudioContext(_ctx);
    } catch (_) {}
  }

  Future<void> playFile(String path) async {
    await _ensureCtx();
    await _player.stop();
    await _player.play(DeviceFileSource(path));
  }

  /// 재생이 끝날 때까지 기다린다 (마지막 인사처럼 다 듣고 넘어가야 할 때).
  Future<void> playFileAndWait(String path) async {
    final done = _player.onPlayerComplete.first;
    await playFile(path);
    await done.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  Future<void> stop() => _player.stop();

  void dispose() => _player.dispose();
}
