import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../data/lines.dart';
import 'audio_utils.dart';
import 'avatar_service.dart';
import 'voice_service.dart';

/// 아바타 클립 하나 = 멘트 하나 (또는 말없는 대기 영상).
class AvatarClip {
  final LineKind? kind; // null 이면 대기 영상
  final int index;
  const AvatarClip(this.kind, this.index);
  static const idle = AvatarClip(null, 0);

  String get name => kind == null ? 'idle' : '${kind!.name}_$index';

  static List<AvatarClip> get lines => [
        for (final e in lineTemplates.entries)
          for (var i = 0; i < e.value.length; i++) AvatarClip(e.key, i),
      ];

  /// 대기 영상 + 멘트 30개
  static List<AvatarClip> get all => [idle, ...lines];
}

/// 기기에 저장된 가상 부모 파일 관리 + 생성 파이프라인.
///
/// 위치: <앱 문서 폴더>/avatar/<voiceId>/
///   <kind>_<n>.wav  부모 목소리 (ElevenLabs PCM → WAV)
///   ── 아래는 HeyGen 을 켰을 때만 (Config.useVideoAvatar) ──
///   <kind>_<n>.mp4  말하는 아바타 영상 (HeyGen, 소리 포함)
///   idle.mp4        말없이 끄덕이는 대기 영상 (반복 재생)
///   jobs.json       진행 중인 HeyGen 작업 (앱을 껐다 켜도 이어서 진행)
class AvatarLibrary {
  final String voiceId;
  AvatarLibrary(this.voiceId);

  static const _maxConcurrent = 3;
  static const _pollEvery = Duration(seconds: 8);

  static Future<Directory> dirOf(String voiceId) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/avatar/$voiceId');
  }

  static Future<File> _file(String voiceId, AvatarClip c, String ext) async =>
      File('${(await dirOf(voiceId)).path}/${c.name}.$ext');

  // ───────── 1) 목소리 30개 ─────────

  static Future<void> generateVoices({
    required VoiceService service,
    required String voiceId,
    required String childCall,
    required String role,
    required void Function(int done, int total) onProgress,
  }) async {
    await (await dirOf(voiceId)).create(recursive: true);
    final clips = AvatarClip.lines;
    var done = 0;
    for (final c in clips) {
      final f = await _file(voiceId, c, 'wav');
      if (!await f.exists()) {
        final text = fillLine(lineTemplates[c.kind]![c.index],
            childCall: childCall, role: role);
        final pcm = await _retry(() => service.tts(voiceId, text));
        await f.writeAsBytes(pcmToWav(pcm), flush: true);
      }
      onProgress(++done, clips.length);
    }
  }

  // ───────── 2) 아바타 영상 31개 ─────────

  static Future<void> generateVideos({
    required AvatarService service,
    required String voiceId,
    required String talkingPhotoId,
    required void Function(int done, int total) onProgress,
  }) async {
    final dir = await dirOf(voiceId);
    await dir.create(recursive: true);
    final jobsFile = File('${dir.path}/jobs.json');
    final Map<String, String> jobs = await jobsFile.exists()
        ? Map<String, String>.from(
            jsonDecode(await jobsFile.readAsString()) as Map)
        : {};
    Future<void> saveJobs() => jobsFile.writeAsString(jsonEncode(jobs));

    final clips = AvatarClip.all;
    final pending = <AvatarClip>[];
    for (final c in clips) {
      if (!await (await _file(voiceId, c, 'mp4')).exists()) pending.add(c);
    }
    final failures = <String, int>{};
    void report() => onProgress(clips.length - pending.length, clips.length);
    report();

    while (pending.isNotEmpty) {
      // 동시에 최대 3개까지 요청
      final running = pending.where((c) => jobs.containsKey(c.name)).length;
      var slots = _maxConcurrent - running;
      for (final c in pending) {
        if (slots <= 0) break;
        if (jobs.containsKey(c.name)) continue;
        final audio = c.kind == null ? null : (await _file(voiceId, c, 'wav')).path;
        jobs[c.name] = await _retry(() => service.createVideo(
            talkingPhotoId: talkingPhotoId, audioPath: audio));
        await saveJobs();
        slots--;
      }

      await Future.delayed(_pollEvery);

      // 진행 중인 작업 확인
      for (final c in List<AvatarClip>.of(pending)) {
        final videoId = jobs[c.name];
        if (videoId == null) continue;
        final st = await _retry(() => service.status(videoId));
        if (st.isDone) {
          await _retry(() async =>
              service.download(st.videoUrl!, await _file(voiceId, c, 'mp4')));
          jobs.remove(c.name);
          pending.remove(c);
          await saveJobs();
          report();
        } else if (st.isFailed) {
          jobs.remove(c.name);
          await saveJobs();
          final n = (failures[c.name] ?? 0) + 1;
          failures[c.name] = n;
          if (n >= 3) {
            throw VoiceException('아바타 영상을 만들지 못했어요. ${st.error ?? ''}'.trim());
          }
        }
      }
    }
    if (await jobsFile.exists()) await jobsFile.delete();
  }

  static Future<T> _retry<T>(Future<T> Function() f) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await f();
      } catch (e) {
        if (attempt >= 2) rethrow;
        await Future.delayed(Duration(seconds: 3 * (attempt + 1)));
      }
    }
  }

  // ───────── 상태 ─────────

  /// 가상 부모가 다 준비됐는지. (목소리 30개 + HeyGen 을 켰다면 영상 31개)
  static Future<bool> isComplete(String voiceId) async {
    for (final c in AvatarClip.lines) {
      if (!await (await _file(voiceId, c, 'wav')).exists()) return false;
    }
    if (Config.useVideoAvatar) {
      for (final c in AvatarClip.all) {
        if (!await (await _file(voiceId, c, 'mp4')).exists()) return false;
      }
    }
    return true;
  }

  static Future<void> deleteFiles(String voiceId) async {
    final d = await dirOf(voiceId);
    if (await d.exists()) await d.delete(recursive: true);
  }

  // ───────── 재생용 ─────────

  final _rand = Random();
  final Map<LineKind, int> _last = {};

  Future<String> idleVideo() async => (await _file(voiceId, AvatarClip.idle, 'mp4')).path;

  /// 종류별로 랜덤 클립 (직전과 같은 것은 피함).
  /// 영상 경로(HeyGen 을 껐으면 없는 파일), 음성 경로, 자막 문장.
  Future<({String video, String audio, String text})> pick(LineKind kind,
      {required String childCall, required String role}) async {
    final n = lineTemplates[kind]!.length;
    var i = _rand.nextInt(n);
    if (n > 1 && i == _last[kind]) i = (i + 1) % n;
    _last[kind] = i;
    final clip = AvatarClip(kind, i);
    return (
      video: (await _file(voiceId, clip, 'mp4')).path,
      audio: (await _file(voiceId, clip, 'wav')).path,
      text: fillLine(lineTemplates[kind]![i], childCall: childCall, role: role),
    );
  }
}
