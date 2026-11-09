import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';

class VoiceException implements Exception {
  final String message;
  VoiceException(this.message);
  @override
  String toString() => message;
}

/// ElevenLabs 목소리 복제 + 멘트 음성 생성 (프록시 경유).
class VoiceService {
  /// 녹음 파일로 목소리를 복제하고 voice_id 를 돌려준다.
  Future<String> cloneVoice(
      {required String name, required String audioPath}) async {
    _checkConfig();
    final req = http.MultipartRequest('POST', Uri.parse(Config.cloneUrl))
      ..headers.addAll(Config.authHeaders)
      ..fields['name'] = name
      ..fields['remove_background_noise'] = 'true'
      ..files.add(await http.MultipartFile.fromPath('files', audioPath,
          filename: 'voice.m4a', contentType: MediaType('audio', 'mp4')));
    final res = await http.Response.fromStream(
        await req.send().timeout(const Duration(minutes: 2)));
    if (res.statusCode != 200) throw VoiceException(_errorText(res));
    final id = (jsonDecode(res.body) as Map<String, dynamic>)['voice_id'];
    if (id is! String || id.isEmpty) {
      throw VoiceException('목소리 ID를 받지 못했어요.');
    }
    return id;
  }

  /// 문장 하나를 복제 목소리로 읽은 PCM(24kHz 16bit 모노 원음).
  /// WAV 로 감싸는 건 audio_utils.pcmToWav.
  Future<Uint8List> tts(String voiceId, String text) async {
    _checkConfig();
    final res = await http
        .post(Uri.parse(Config.ttsUrl),
            headers: {
              ...Config.authHeaders,
              'Content-Type': 'application/json'
            },
            body: jsonEncode(
                {'voice_id': voiceId, 'text': text, 'format': 'pcm_24000'}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw VoiceException(_errorText(res));
    return res.bodyBytes;
  }

  /// 예전 목소리 삭제 (ElevenLabs 계정의 목소리 개수 제한 때문). 실패해도 무시.
  Future<void> deleteVoice(String voiceId) async {
    if (!Config.hasProxy) return;
    try {
      await http
          .post(Uri.parse(Config.deleteVoiceUrl),
              headers: {
                ...Config.authHeaders,
                'Content-Type': 'application/json'
              },
              body: jsonEncode({'voice_id': voiceId}))
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  void _checkConfig() {
    if (!Config.hasProxy) {
      throw VoiceException(
          '서버 설정이 없어요. PROXY_URL / APP_SECRET 을 넣고 빌드해 주세요.');
    }
  }

  String _errorText(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      final detail = j is Map ? (j['error'] ?? j['detail']) : null;
      return '음성 서버 오류 (${r.statusCode}) ${detail ?? ''}'.trim();
    } catch (_) {
      return '음성 서버 오류 (${r.statusCode})';
    }
  }
}
