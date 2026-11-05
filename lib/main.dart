import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/parent_profile.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'services/audio_service.dart';
import 'services/storage_service.dart';
import 'services/voice_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 세로 고정 — 얼굴 인식 회전 계산을 단순하게 유지한다.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AudioService.configureSession();

  // 부모 설정이 끝까지 된 경우에만 홈으로, 아니면 설정부터.
  ParentProfile? profile = await StorageService.loadProfile();
  if (profile != null && !await LineLibrary.isComplete(profile.voiceId)) {
    profile = null;
  }
  runApp(GongbuApp(profile: profile));
}

class GongbuApp extends StatelessWidget {
  final ParentProfile? profile;
  const GongbuApp({super.key, this.profile});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '공부해라',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
              textScaler: mq.textScaler
                  .clamp(minScaleFactor: 1.0, maxScaleFactor: 1.3)),
          child: child!,
        );
      },
      home: profile == null
          ? const SetupScreen()
          : HomeScreen(profile: profile!),
    );
  }
}
