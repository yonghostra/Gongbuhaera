import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gongbuhaera/services/audio_utils.dart';

/// [seconds] 길이의 PCM. 앞 절반은 무음, 뒤 절반은 440Hz 소리.
Uint8List halfSilentPcm(double seconds) {
  final n = (pcmSampleRate * seconds).round();
  final b = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    final v = i < n ~/ 2 ? 0 : (sin(2 * pi * 440 * i / pcmSampleRate) * 12000).round();
    b.setInt16(i * 2, v, Endian.little);
  }
  return b.buffer.asUint8List();
}

void main() {
  test('PCM 에 WAV 헤더를 정확히 붙인다', () {
    final pcm = halfSilentPcm(1);
    final wav = pcmToWav(pcm);
    final b = ByteData.sublistView(wav);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    expect(b.getUint32(24, Endian.little), pcmSampleRate);
    expect(b.getUint32(40, Endian.little), pcm.length);
    expect(b.getUint32(4, Endian.little), wav.length - 8);
    expect(wav.length, pcm.length + wavHeaderBytes);
  });

  test('홀수 바이트 PCM 은 16bit 에 맞춰 잘라낸다', () {
    final wav = pcmToWav(Uint8List(11));
    expect(wav.length, wavHeaderBytes + 10);
  });

  test('소리 크기: 무음 구간은 0, 소리 구간은 1에 가깝다', () {
    final env = envelopeFromWav(pcmToWav(halfSilentPcm(2)));
    expect(env.duration.inMilliseconds, closeTo(2000, 40));
    expect(env.at(const Duration(milliseconds: 300)), 0);
    expect(env.at(const Duration(milliseconds: 1600)), greaterThan(0.95));
    // 재생 시간을 넘어가면 0
    expect(env.at(const Duration(seconds: 5)), 0);
  });

  test('완전 무음 파일도 오류 없이 0', () {
    final env = envelopeFromWav(pcmToWav(Uint8List(pcmSampleRate * 2)));
    expect(env.levels.every((v) => v == 0), isTrue);
    expect(envelopeFromWav(Uint8List(10)).levels, isEmpty);
  });
}
