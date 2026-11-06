import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import 'voice_service.dart' show VoiceException;

/// HeyGen 영상 상태.
class AvatarVideoStatus {
  /// pending / processing / completed / failed
  final String status;
  final String? videoUrl;
  final String? error;
  const AvatarVideoStatus(this.status, {this.videoUrl, this.error});

  bool get isDone => status == 'completed' && videoUrl != null;
  bool get isFailed => status == 'failed';
}

/// HeyGen 사진 아바타로 "말하는 영상"을 만드는 클라이언트 (프록시 경유).
///
/// 흐름: 사진 업로드 → talking_photo_id
///      → (멘트 mp3 마다) 영상 생성 요청 → video_id
///      → 상태 확인 → 완료되면 video_url 에서 mp4 다운로드
class AvatarService {
  /// 부모 사진을 HeyGen 사진 아바타로 등록.
  Future<String> uploadPhoto(String imagePath) async {
    _checkConfig();
    final res = await http
        .post(Uri.parse(Config.heygenPhotoUrl),
            headers: {...Config.authHeaders, 'Content-Type': 'image/jpeg'},
            body: await File(imagePath).readAsBytes())
        .timeout(const Duration(minutes: 2));
    final j = _json(res);
    final id = j['talking_photo_id'];
    if (id is! String || id.isEmpty) {
      throw VoiceException('사진 아바타를 만들지 못했어요. 얼굴이 정면으로 잘 나온 사진인지 확인해 주세요.');
    }
    return id;
  }

  /// 말하는 영상 생성 요청. [audioPath] 가 없으면 [silenceSeconds] 동안 말없이 있는 대기 영상.
  Future<String> createVideo({
    required String talkingPhotoId,
    String? audioPath,
    int silenceSeconds = 6,
  }) async {
    _checkConfig();
    final uri = Uri.parse(Config.heygenVideoUrl).replace(queryParameters: {
      'talking_photo_id': talkingPhotoId,
      if (audioPath == null) 'silence': '$silenceSeconds',
    });
    final res = await http
        .post(uri,
            headers: {
              ...Config.authHeaders,
              'Content-Type':
                  audioPath == null ? 'application/octet-stream' : 'audio/mpeg',
            },
            body: audioPath == null
                ? <int>[]
                : await File(audioPath).readAsBytes())
        .timeout(const Duration(minutes: 1));
    final id = _json(res)['video_id'];
    if (id is! String || id.isEmpty) {
      throw VoiceException('아바타 영상 요청에 실패했어요.');
    }
    return id;
  }

  Future<AvatarVideoStatus> status(String videoId) async {
    _checkConfig();
    final uri = Uri.parse(Config.heygenStatusUrl)
        .replace(queryParameters: {'video_id': videoId});
    final res = await http
        .get(uri, headers: Config.authHeaders)
        .timeout(const Duration(seconds: 30));
    final j = _json(res);
    return AvatarVideoStatus(
      (j['status'] as String?) ?? 'pending',
      videoUrl: j['video_url'] as String?,
      error: j['error']?.toString(),
    );
  }

  /// 완성된 영상 내려받기 (HeyGen 이 준 임시 주소라 키가 필요 없다).
  Future<void> download(String url, File dest) async {
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) {
      throw VoiceException('아바타 영상 다운로드 실패 (${res.statusCode})');
    }
    final tmp = File('${dest.path}.part');
    await tmp.writeAsBytes(res.bodyBytes, flush: true);
    await tmp.rename(dest.path);
  }

  Map<String, dynamic> _json(http.Response r) {
    Map<String, dynamic>? j;
    try {
      j = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode != 200 || j == null) {
      final detail = j?['error'] ?? '';
      throw VoiceException('아바타 서버 오류 (${r.statusCode}) $detail'.trim());
    }
    return j;
  }

  void _checkConfig() {
    if (!Config.hasProxy) {
      throw VoiceException(
          '서버 설정이 없어요. PROXY_URL / APP_SECRET 을 넣고 빌드해 주세요.');
    }
  }
}
