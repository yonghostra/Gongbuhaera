/// 런타임 설정.
///
/// 보안: ElevenLabs·HeyGen 키는 앱에 넣지 않는다. 모든 호출은 Supabase Edge Function
/// 프록시(`gongbuhaera-proxy`)를 거치며, 앱은 프록시 URL과 앱 시크릿만 갖는다.
/// 빌드 시 주입:
///   --dart-define=PROXY_URL=`https://<ref>.supabase.co/functions/v1/gongbuhaera-proxy`
///   --dart-define=APP_SECRET=...
class Config {
  static const proxyUrl = String.fromEnvironment('PROXY_URL');
  static const appSecret = String.fromEnvironment('APP_SECRET');

  // ElevenLabs (목소리)
  static String get cloneUrl => '$proxyUrl/clone';
  static String get ttsUrl => '$proxyUrl/tts';
  static String get deleteVoiceUrl => '$proxyUrl/delete-voice';

  // HeyGen (말하는 아바타 영상)
  static String get heygenPhotoUrl => '$proxyUrl/heygen/photo';
  static String get heygenVideoUrl => '$proxyUrl/heygen/video';
  static String get heygenStatusUrl => '$proxyUrl/heygen/status';

  static Map<String, String> get authHeaders => {'x-app-secret': appSecret};

  static bool get hasProxy => proxyUrl.isNotEmpty && appSecret.isNotEmpty;
}
