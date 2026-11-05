/// 가상 부모 정보. 기기 안(shared_preferences)에만 저장된다.
class ParentProfile {
  /// '엄마' 또는 '아빠' — 멘트 속 자기 호칭으로 쓰인다.
  final String role;

  /// 아이를 부르는 말 그대로 (예: '민준아', '서연아').
  final String childCall;

  /// 앱 문서 폴더에 복사해 둔 부모 사진 경로.
  final String photoPath;

  /// ElevenLabs 에 만들어진 복제 목소리 ID.
  final String voiceId;

  const ParentProfile({
    required this.role,
    required this.childCall,
    required this.photoPath,
    required this.voiceId,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'childCall': childCall,
        'photoPath': photoPath,
        'voiceId': voiceId,
      };

  factory ParentProfile.fromJson(Map<String, dynamic> j) => ParentProfile(
        role: j['role'] as String,
        childCall: j['childCall'] as String,
        photoPath: j['photoPath'] as String,
        voiceId: j['voiceId'] as String,
      );
}
