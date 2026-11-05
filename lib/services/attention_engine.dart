/// 카메라 얼굴 인식 결과를 받아 "지금 아이가 어떤 상태인지" 판단하고,
/// 언제 가상 부모가 말해야 하는지(이벤트)를 정하는 순수 로직.
///
/// Flutter·카메라와 분리돼 있어 단위 테스트로 검증할 수 있다.
library;

/// 화면에 보여줄 현재 상태.
enum AttentionStatus { focused, drowsy, away, lookingAway }

/// 가상 부모가 말해야 하는 순간.
enum AttentionEvent { drowsy, away, distracted, returned, praise }

/// 카메라 프레임 한 장에서 얻은 얼굴 정보.
class FaceSample {
  final bool facePresent;

  /// 눈 뜸 확률 0~1 (ML Kit). 모르면 null.
  final double? leftEyeOpen;
  final double? rightEyeOpen;

  /// 고개 좌우 회전 각도(도). 정면이 0.
  final double? headYaw;

  const FaceSample({
    required this.facePresent,
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.headYaw,
  });

  static const none = FaceSample(facePresent: false);
}

/// 판단 기준. MVP 기본값이며, 실제 아이들로 테스트하며 조정한다.
class AttentionConfig {
  /// 눈을 이만큼 계속 감고 있으면 졸음.
  final Duration drowsyAfter;

  /// 얼굴이 이만큼 계속 안 보이면 자리 비움 (이때부터 타이머 멈춤).
  final Duration awayAfter;

  /// 고개를 이만큼 계속 옆으로 돌리고 있으면 딴짓.
  final Duration lookAwayAfter;

  /// 이 각도보다 고개를 돌리면 "옆을 본다"고 판단.
  final double yawLimitDeg;

  /// 두 눈 뜸 확률이 모두 이 값보다 낮으면 "눈 감음".
  final double eyeClosedBelow;

  /// 같은 상태가 계속되면 이 간격마다 다시 지적.
  final Duration repeatNagEvery;

  /// 어떤 말이든 최소 이 간격은 두고 말한다 (잔소리 폭탄 방지).
  final Duration minGapBetweenLines;

  /// 이만큼 쭉 집중하면 칭찬.
  final Duration praiseEvery;

  const AttentionConfig({
    this.drowsyAfter = const Duration(seconds: 3),
    this.awayAfter = const Duration(seconds: 10),
    this.lookAwayAfter = const Duration(seconds: 8),
    this.yawLimitDeg = 35,
    this.eyeClosedBelow = 0.3,
    this.repeatNagEvery = const Duration(seconds: 30),
    this.minGapBetweenLines = const Duration(seconds: 8),
    this.praiseEvery = const Duration(minutes: 10),
  });
}

class AttentionEngine {
  final AttentionConfig config;
  AttentionEngine({this.config = const AttentionConfig()});

  AttentionStatus _status = AttentionStatus.focused;
  AttentionStatus get status => _status;

  /// 공부 타이머가 흘러가야 하는지. 자리를 비우면 멈춘다.
  bool get shouldCountTime => _status != AttentionStatus.away;

  // 각 조건이 시작된 시각 (조건이 풀리면 null)
  Duration? _noFaceSince;
  Duration? _eyesClosedSince;
  Duration? _lookAwaySince;

  // 현재 상태에서 마지막으로 지적한 시각 (상태가 바뀌면 null)
  Duration? _nagAt;
  // 어떤 말이든 마지막으로 한 시각
  Duration? _lastLineAt;
  // 칭찬 기준 시각 (집중이 끊기면 null)
  Duration? _praiseAnchor;

  final Map<AttentionEvent, int> counts = {
    for (final e in AttentionEvent.values) e: 0,
  };

  /// 프레임마다 호출. [now] 는 공부 시작 후 흐른 시간(단조 증가).
  /// 이번에 가상 부모가 말해야 할 이벤트 목록을 돌려준다.
  List<AttentionEvent> update(FaceSample s, Duration now) {
    final events = <AttentionEvent>[];

    // 1) 원시 조건
    final noFace = !s.facePresent;
    final eyesClosed = s.facePresent &&
        s.leftEyeOpen != null &&
        s.rightEyeOpen != null &&
        s.leftEyeOpen! < config.eyeClosedBelow &&
        s.rightEyeOpen! < config.eyeClosedBelow;
    final lookingAway = s.facePresent &&
        !eyesClosed &&
        s.headYaw != null &&
        s.headYaw!.abs() > config.yawLimitDeg;

    _noFaceSince = noFace ? (_noFaceSince ?? now) : null;
    _eyesClosedSince = eyesClosed ? (_eyesClosedSince ?? now) : null;
    _lookAwaySince = lookingAway ? (_lookAwaySince ?? now) : null;

    // 2) 일정 시간 이상 이어졌을 때만 상태로 인정 (순간 깜빡임·고개 돌림 무시)
    AttentionStatus next;
    if (_noFaceSince != null && now - _noFaceSince! >= config.awayAfter) {
      next = AttentionStatus.away;
    } else if (_eyesClosedSince != null &&
        now - _eyesClosedSince! >= config.drowsyAfter) {
      next = AttentionStatus.drowsy;
    } else if (_lookAwaySince != null &&
        now - _lookAwaySince! >= config.lookAwayAfter) {
      next = AttentionStatus.lookingAway;
    } else {
      next = AttentionStatus.focused;
    }

    // 3) 상태 변화 처리
    final prev = _status;
    if (next != prev) {
      _status = next;
      _nagAt = null;
      if (prev == AttentionStatus.away) {
        _emit(events, AttentionEvent.returned, now);
      }
    }

    // 4) 지적 (처음 + 계속되면 반복)
    if (_status != AttentionStatus.focused) {
      _praiseAnchor = null;
      final gapOk = _lastLineAt == null ||
          now - _lastLineAt! >= config.minGapBetweenLines;
      final repeatOk =
          _nagAt == null || now - _nagAt! >= config.repeatNagEvery;
      if (gapOk && repeatOk) {
        _emit(events, _eventFor(_status), now);
        _nagAt = now;
      }
    } else {
      // 5) 칭찬
      _praiseAnchor ??= now;
      if (now - _praiseAnchor! >= config.praiseEvery) {
        _emit(events, AttentionEvent.praise, now);
        _praiseAnchor = now;
      }
    }

    return events;
  }

  void _emit(List<AttentionEvent> out, AttentionEvent e, Duration now) {
    out.add(e);
    counts[e] = counts[e]! + 1;
    _lastLineAt = now;
  }

  static AttentionEvent _eventFor(AttentionStatus s) => switch (s) {
        AttentionStatus.drowsy => AttentionEvent.drowsy,
        AttentionStatus.away => AttentionEvent.away,
        AttentionStatus.lookingAway => AttentionEvent.distracted,
        AttentionStatus.focused => AttentionEvent.praise,
      };
}
