import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../data/lines.dart';

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

  /// 문장 하나를 복제 목소리로 읽은 mp3.
  Future<Uint8List> tts(String voiceId, String text) async {
    _checkConfig();
    final res = await http
        .post(Uri.parse(Config.ttsUrl),
            headers: {
              ...Config.authHeaders,
              'Content-Type': 'application/json'
            },
            body: jsonEncode({'voice_id': voiceId, 'text': text}))
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

/// 기기에 저장된 부모 멘트 음성 파일 관리.
///
/// 파일 위치: <앱 문서 폴더>/voice/<voiceId>/<kind>_<번호>.mp3
/// voiceId 별로 폴더를 나눠, 다시 설정해도 예전 파일과 섞이지 않는다.
class LineLibrary {
  final String voiceId;
  LineLibrary(this.voiceId);

  final _rand = Random();
  final Map<LineKind, int> _lastIndex = {};

  static Future<Directory> _dir(String voiceId) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/voice/$voiceId');
  }

  /// 30개 멘트를 모두 만들어 저장. [onProgress] 로 (완료 개수, 전체) 알림.
  static Future<void> generateAll({
    required VoiceService service,
    required String voiceId,
    required String childCall,
    required String role,
    required void Function(int done, int total) onProgress,
  }) async {
    final dir = await _dir(voiceId);
    await dir.create(recursive: true);
    final total = totalLineCount;
    var done = 0;
    for (final entry in lineTemplates.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final file = File('${dir.path}/${entry.key.name}_$i.mp3');
        if (!await file.exists()) {
          final text =
              fillLine(entry.value[i], childCall: childCall, role: role);
          final bytes = await _withRetry(() => service.tts(voiceId, text));
          await file.writeAsBytes(bytes, flush: true);
        }
        done++;
        onProgress(done, total);
      }
    }
  }

  static Future<T> _withRetry<T>(Future<T> Function() f) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await f();
      } catch (e) {
        if (attempt >= 2) rethrow;
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
  }

  /// 모든 멘트 파일이 다 있는지.
  static Future<bool> isComplete(String voiceId) async {
    final dir = await _dir(voiceId);
    for (final entry in lineTemplates.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        if (!await File('${dir.path}/${entry.key.name}_$i.mp3').exists()) {
          return false;
        }
      }
    }
    return true;
  }

  /// 예전 목소리 파일 정리.
  static Future<void> deleteFiles(String voiceId) async {
    final dir = await _dir(voiceId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 종류별로 랜덤 멘트 파일 경로 (직전과 같은 멘트는 피함).
  Future<String> pick(LineKind kind) async {
    final n = lineTemplates[kind]!.length;
    var i = _rand.nextInt(n);
    if (n > 1 && i == _lastIndex[kind]) i = (i + 1) % n;
    _lastIndex[kind] = i;
    final dir = await _dir(voiceId);
    return '${dir.path}/${kind.name}_$i.mp3';
  }
}
