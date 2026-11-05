import 'package:flutter_test/flutter_test.dart';
import 'package:gongbuhaera/services/attention_engine.dart';

const focusedFace =
    FaceSample(facePresent: true, leftEyeOpen: 0.9, rightEyeOpen: 0.9, headYaw: 0);
const closedEyes =
    FaceSample(facePresent: true, leftEyeOpen: 0.05, rightEyeOpen: 0.1, headYaw: 0);
const sideLook =
    FaceSample(facePresent: true, leftEyeOpen: 0.9, rightEyeOpen: 0.9, headYaw: 60);

/// [from]초부터 [to]초까지 0.5초 간격으로 같은 샘플을 넣고, 나온 이벤트를 모은다.
List<AttentionEvent> feed(AttentionEngine e, FaceSample s, double from, double to) {
  final out = <AttentionEvent>[];
  for (var t = from; t < to; t += 0.5) {
    out.addAll(e.update(s, Duration(milliseconds: (t * 1000).round())));
  }
  return out;
}

void main() {
  test('잠깐 눈 깜빡임은 무시한다', () {
    final e = AttentionEngine();
    feed(e, focusedFace, 0, 5);
    final ev = feed(e, closedEyes, 5, 6); // 1초만 감음
    expect(ev, isEmpty);
    expect(e.status, AttentionStatus.focused);
  });

  test('3초 이상 눈을 감으면 졸음 지적', () {
    final e = AttentionEngine();
    feed(e, focusedFace, 0, 5);
    final ev = feed(e, closedEyes, 5, 9);
    expect(ev, [AttentionEvent.drowsy]);
    expect(e.status, AttentionStatus.drowsy);
  });

  test('10초 이상 얼굴이 없으면 자리 비움, 타이머 멈춤, 돌아오면 반겨줌', () {
    final e = AttentionEngine();
    feed(e, focusedFace, 0, 5);
    expect(feed(e, FaceSample.none, 5, 14), isEmpty); // 9초까지는 봐줌
    expect(e.shouldCountTime, isTrue);
    expect(feed(e, FaceSample.none, 14, 16), [AttentionEvent.away]);
    expect(e.shouldCountTime, isFalse);
    expect(feed(e, focusedFace, 16, 17), [AttentionEvent.returned]);
    expect(e.shouldCountTime, isTrue);
  });

  test('자리 비움이 계속되면 30초마다 다시 지적', () {
    final e = AttentionEngine();
    final ev = feed(e, FaceSample.none, 0, 75);
    // 10초에 첫 지적, 40초, 70초에 반복
    expect(ev, [AttentionEvent.away, AttentionEvent.away, AttentionEvent.away]);
  });

  test('8초 이상 고개를 돌리면 딴짓 지적', () {
    final e = AttentionEngine();
    feed(e, focusedFace, 0, 5);
    expect(feed(e, sideLook, 5, 12), isEmpty);
    expect(feed(e, sideLook, 12, 14), [AttentionEvent.distracted]);
  });

  test('10분 동안 집중하면 칭찬', () {
    final e = AttentionEngine();
    final ev = feed(e, focusedFace, 0, 601);
    expect(ev, [AttentionEvent.praise]);
  });

  test('지적 직후에는 최소 8초 동안 다른 말을 하지 않는다', () {
    final e = AttentionEngine(
        config: const AttentionConfig(lookAwayAfter: Duration(seconds: 2)));
    feed(e, focusedFace, 0, 2);
    expect(feed(e, closedEyes, 2, 6), [AttentionEvent.drowsy]); // 5초에 지적
    // 6초부터 고개 돌림 → 8초에 딴짓 상태가 되지만, 8초 간격 규칙 때문에 13초에 말함
    final out = <double>[];
    for (var t = 6.0; t < 16; t += 0.5) {
      if (e.update(sideLook, Duration(milliseconds: (t * 1000).round()))
          .contains(AttentionEvent.distracted)) {
        out.add(t);
      }
    }
    expect(out, [13.0]);
  });
}
