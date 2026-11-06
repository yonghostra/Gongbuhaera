import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/parent_profile.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'services/audio_service.dart';
import 'services/storage_service.dart';
import 'services/avatar_library.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 세로 고정 — 얼굴 인식 회전 계산을 단순하게 유지한다.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await AudioService.configureSession();

  // 아바타가 끝까지 만들어진 경우에만 홈으로, 아니면 설정부터.
  // (만들다 중단된 경우 설정 화면이 이어서 진행한다)
  final saved = await StorageService.loadProfile();
  final ready = saved != null && await AvatarLibrary.isComplete(saved.voiceId);
  runApp(GongbuApp(profile: ready ? saved : null, resume: ready ? null : saved));
}

class GongbuApp extends StatelessWidget {
  final ParentProfile? profile;
  final ParentProfile? resume;
  const GongbuApp({super.key, this.profile, this.resume});

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
          ? SetupScreen(resume: resume)
          : HomeScreen(profile: profile!),
    );
  }
}
