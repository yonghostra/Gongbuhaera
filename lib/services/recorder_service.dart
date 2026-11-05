import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// 목소리 복제용 녹음. m4a(AAC)로 저장.
class RecorderService {
  final AudioRecorder _rec = AudioRecorder();

  Future<bool> hasPermission() => _rec.hasPermission();

  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        // iOS 주의(말벗에서 확인): AAC 16kHz 녹음은 아이폰에서 통째로 무음이 된다.
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 128000,
      ),
      path: path,
    );
  }

  /// 녹음 종료 → 파일 경로.
  Future<String?> stop() => _rec.stop();

  Future<void> cancel() => _rec.cancel();

  void dispose() => _rec.dispose();
}
