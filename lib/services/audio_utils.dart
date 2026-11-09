/// 음성 파일 도우미 (순수 Dart, 테스트 있음).
///
/// ElevenLabs 에서 PCM(16bit 모노 원음)으로 받아
///  1) 앞에 WAV 헤더를 붙여 재생 가능한 파일로 만들고
///  2) 말하는 동안 사진 테두리·파형을 실제 목소리 크기에 맞춰 움직이도록
///     짧은 구간마다 소리 크기(0~1)를 계산한다.
library;

import 'dart:math';
import 'dart:typed_data';

const int pcmSampleRate = 24000;
const int wavHeaderBytes = 44;

/// 16bit 모노 PCM → WAV 파일 바이트.
Uint8List pcmToWav(Uint8List pcm, {int sampleRate = pcmSampleRate}) {
  final dataLen = pcm.length - (pcm.length % 2); // 16bit 정렬
  final out = Uint8List(wavHeaderBytes + dataLen);
  final b = ByteData.sublistView(out);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out[offset + i] = s.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // fmt 블록 크기
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // 모노
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 2, Endian.little); // 초당 바이트
  b.setUint16(32, 2, Endian.little); // 블록 정렬
  b.setUint16(34, 16, Endian.little); // 16bit
  ascii(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  out.setRange(wavHeaderBytes, wavHeaderBytes + dataLen, pcm);
  return out;
}

/// 소리 크기 흐름. [levels] 의 i 번째 값이 [frameMs] * i 시점의 크기(0~1).
class VoiceEnvelope {
  final List<double> levels;
  final int frameMs;
  const VoiceEnvelope(this.levels, this.frameMs);

  static const silent = VoiceEnvelope([], 40);

  Duration get duration => Duration(milliseconds: levels.length * frameMs);

  /// 재생 시작 후 [t] 시점의 소리 크기.
  double at(Duration t) {
    if (levels.isEmpty) return 0;
    final i = t.inMilliseconds ~/ frameMs;
    if (i < 0 || i >= levels.length) return 0;
    return levels[i];
  }
}

/// 우리가 만든 WAV(헤더 44바이트 + 16bit 모노)에서 소리 크기 흐름을 계산한다.
///
/// 구간마다 RMS 를 구하고, 그 클립에서 가장 큰 값을 1로 맞춘 뒤
/// 작은 소리도 눈에 보이도록 제곱근으로 살짝 끌어올린다.
VoiceEnvelope envelopeFromWav(Uint8List wav,
    {int sampleRate = pcmSampleRate, int frameMs = 40}) {
  if (wav.length <= wavHeaderBytes) return VoiceEnvelope.silent;
  final data = ByteData.sublistView(wav, wavHeaderBytes);
  final samples = data.lengthInBytes ~/ 2;
  final perFrame = max(1, sampleRate * frameMs ~/ 1000);
  final rms = <double>[];
  for (var start = 0; start < samples; start += perFrame) {
    final end = min(samples, start + perFrame);
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      final v = data.getInt16(i * 2, Endian.little) / 32768.0;
      sum += v * v;
    }
    rms.add(sqrt(sum / (end - start)));
  }
  final peak = rms.fold<double>(0, max);
  if (peak < 1e-4) {
    return VoiceEnvelope(List.filled(rms.length, 0), frameMs);
  }
  return VoiceEnvelope(
    [for (final r in rms) sqrt((r / peak).clamp(0.0, 1.0))],
    frameMs,
  );
}
