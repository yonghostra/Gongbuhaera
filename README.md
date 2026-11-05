# 공부해라 (Gongbuhaera)

엄마·아빠 목소리를 복제한 **가상 부모**가 카메라로 아이의 공부를 지켜보는 앱 (Flutter, iOS + Android).
졸거나, 자리를 비우거나, 딴짓하면 부모 목소리로 지적하고, 집중하면 칭찬합니다.

> 현재 단계: **1단계 MVP** (사진 + 복제 목소리). 말하는 영상 아바타는 2단계에서 추가합니다.

## 무엇을 하나
1. **부모 설정** (부모가 직접, 최초 1회)
   - 엄마/아빠 선택 + 아이 호칭(예: "민준아")
   - 부모 사진
   - 동의 체크 → 대본 읽으며 목소리 녹음 (30초~3분)
   - ElevenLabs로 목소리 복제 → 멘트 30개를 부모 목소리로 **미리 생성해 폰에 저장**
2. **공부하기**
   - 시간 선택 (10/25/50/90분) → 시작
   - 전면 카메라로 얼굴을 보고 상태를 판단 (폰 안에서만 처리)
   - 자리에 있을 때만 타이머가 줄어듦 (자리 비우면 멈춤)
   - 다른 앱으로 나가면 멈추고, 돌아오면 "핸드폰 보는 거 아니지?"
3. **기록**: 회차별 공부 시간 · 지적 횟수, 최근 7일 합계

## 감지 규칙 (`lib/services/attention_engine.dart`)
| 상황 | 조건 | 반응 |
|---|---|---|
| 졸음 | 두 눈을 3초 이상 감음 | 졸음 지적 |
| 자리 비움 | 얼굴이 10초 이상 안 보임 | 지적 + **타이머 멈춤** |
| 딴짓 | 고개를 35° 넘게 8초 이상 돌림 | 딴짓 지적 |
| 복귀 | 자리 비움 후 얼굴이 다시 보임 | "왔구나, 다시 시작하자" |
| 집중 | 10분 동안 문제없음 | 칭찬 |

- 같은 상태가 계속되면 30초마다 다시 지적, 어떤 말이든 최소 8초 간격 (잔소리 폭탄 방지)
- 숫자는 `AttentionConfig` 기본값이며 실제 아이로 테스트하며 조정할 예정
- 한계: 고개 숙여 책 보기 vs 폰 보기는 카메라만으로 구분이 어려워 MVP에서는 판단하지 않음

## 개인정보
- **카메라 영상**: 폰 안의 Google ML Kit로만 분석. 저장·전송하지 않음.
- **부모 목소리 녹음**: 복제를 위해 ElevenLabs로 전송됨 (설정 화면에서 동의 받음).
- 사진·기록·멘트 음성: 폰 안에만 저장.

## 구조
```
lib/
  main.dart                 설정 여부에 따라 설정/홈 화면으로
  config.dart               프록시 주소 (빌드 시 주입)
  data/lines.dart           가상 부모 멘트 30개 + 녹음 대본
  services/
    attention_engine.dart   감지 판단 로직 (순수 Dart, 테스트 있음)
    face_monitor.dart       카메라 + ML Kit 얼굴 인식
    voice_service.dart      목소리 복제/멘트 생성, 멘트 파일 관리
    audio_service.dart      재생 (말벗에서 검증한 iOS/Android 설정)
    recorder_service.dart   녹음
    storage_service.dart    기기 저장 (프로필, 기록)
  screens/                  setup / home / study / history
supabase/functions/gongbuhaera-proxy/   ElevenLabs 키를 숨기는 서버 중계
tools/setup_platforms.sh                iOS/Android 폴더 생성 + 권한 자동 설정
```

## 처음 준비 (맥에서 1회)

### 1) 서버(프록시) 배포
ElevenLabs 키는 앱에 넣지 않고 Supabase 서버 함수에만 둡니다. (말벗의 `hoehwa100-proxy`와 같은 방식)

```bash
# Supabase 대시보드 → Edge Functions → Secrets 에 등록
#   ELEVENLABS_API_KEY = (ElevenLabs 키)
#   APP_SECRET         = (아무 긴 랜덤 문자열, 예: openssl rand -hex 24)
supabase functions deploy gongbuhaera-proxy --no-verify-jwt --project-ref <프로젝트 ref>
```
- ElevenLabs **목소리 복제(Instant Voice Cloning)는 유료 플랜(Starter 이상)** 이 필요합니다.
- 멘트 30개 생성 ≈ 한글 약 700자 → 설정 1회당 크레딧 소모가 적습니다.

### 2) iOS/Android 폴더 만들기
```bash
bash tools/setup_platforms.sh
```
(`flutter create` 실행 + 카메라/마이크/사진 권한 문구, 앱 이름, iOS 최소 버전 15.5 자동 설정)

## 실행하기
```bash
flutter test     # 감지 로직 테스트

flutter run --release \
  --dart-define=PROXY_URL=https://<ref>.supabase.co/functions/v1/gongbuhaera-proxy \
  --dart-define=APP_SECRET=<앱 시크릿>
```
- 실제 폰에서 테스트하세요 (시뮬레이터는 카메라 없음).
- iOS 서명 팀은 Xcode에서 STRA Co,. Ltd. 로 설정.

## 다음 단계 (예정)
- 2단계: 부모 사진이 말하는 립싱크 영상 아바타 (STRA 립싱크 활용), 멘트 직접 추가/수정
- 3단계: 공부 완료 시 부모 폰으로 알림
- 설정 화면 잠금 (아이가 못 바꾸게)
