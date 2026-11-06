import 'package:flutter/material.dart';

import '../models/parent_profile.dart';
import '../services/avatar_library.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../widgets/avatar_view.dart';
import '../widgets/ui.dart';
import 'history_screen.dart';
import 'setup_screen.dart';
import 'study_screen.dart';

class HomeScreen extends StatefulWidget {
  final ParentProfile profile;
  const HomeScreen({super.key, required this.profile});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _presets = [10, 25, 50, 90];
  int _minutes = 25;
  int _todaySeconds = 0;
  AvatarController? _avatar;

  @override
  void initState() {
    super.initState();
    _loadToday();
    _startIdle();
  }

  @override
  void dispose() {
    _avatar?.dispose();
    super.dispose();
  }

  Future<void> _startIdle() async {
    final c = AvatarController();
    setState(() => _avatar = c);
    await c.init(await AvatarLibrary(widget.profile.voiceId).idleVideo());
  }

  Future<void> _loadToday() async {
    final records = await StorageService.loadRecords();
    final now = DateTime.now();
    final sec = records
        .where((r) =>
            r.startedAt.year == now.year &&
            r.startedAt.month == now.month &&
            r.startedAt.day == now.day)
        .fold<int>(0, (s, r) => s + r.studiedSeconds);
    if (mounted) setState(() => _todaySeconds = sec);
  }

  Future<void> _start() async {
    await _avatar?.pauseAll();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StudyScreen(profile: widget.profile, minutes: _minutes),
    ));
    await _avatar?.resumeIdle();
    _loadToday();
  }

  String get _todayLabel {
    final m = _todaySeconds ~/ 60;
    return m >= 60 ? '오늘 ${m ~/ 60}시간 ${m % 60}분' : '오늘 $m분';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            children: [
              Row(
                children: [
                  Text('공부해라',
                      style: AppText.base(26,
                          w: FontWeight.w800, c: AppColors.siennaLight)),
                  const Spacer(),
                  StatusChip(label: _todayLabel, color: AppColors.siennaLight),
                  const SizedBox(width: 8),
                  RoundIconButton(
                    icon: Icons.settings_outlined,
                    tooltip: '가상 부모 다시 만들기',
                    size: 40,
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => SetupScreen(previous: p))),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AvatarView(
                        controller: _avatar,
                        photoPath: p.photoPath,
                        width: 250,
                        height: 290),
                    const SizedBox(height: 22),
                    Text('${p.childCall}, 공부할 시간이야!',
                        textAlign: TextAlign.center,
                        style: AppText.base(22, w: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('폰을 세워 얼굴이 보이게 두세요 · 영상은 폰 밖으로 나가지 않아요',
                        textAlign: TextAlign.center,
                        style: AppText.base(13,
                            c: AppColors.inkSub, height: 1.5)),
                  ],
                ),
              ),
              PillTabs<int>(
                values: _presets,
                selected: _minutes,
                labelOf: (m) => '$m분',
                onChanged: (m) => setState(() => _minutes = m),
              ),
              const SizedBox(height: 16),
              PillButton(label: '공부 시작', onPressed: _start),
              const SizedBox(height: 16),
              RoundIconButton(
                icon: Icons.bar_chart_rounded,
                tooltip: '공부 기록',
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
