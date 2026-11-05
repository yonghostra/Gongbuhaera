import 'package:flutter/material.dart';

import '../models/parent_profile.dart';
import '../models/study_record.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../widgets/parent_avatar.dart';
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

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  Future<void> _loadToday() async {
    final records = await StorageService.loadRecords();
    final now = DateTime.now();
    final today = records.where((r) =>
        r.startedAt.year == now.year &&
        r.startedAt.month == now.month &&
        r.startedAt.day == now.day);
    if (!mounted) return;
    setState(() => _todaySeconds =
        today.fold(0, (sum, r) => sum + r.studiedSeconds));
  }

  Future<void> _start() async {
    await Navigator.of(context).push<StudyRecord>(MaterialPageRoute(
      builder: (_) =>
          StudyScreen(profile: widget.profile, minutes: _minutes),
    ));
    _loadToday();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final todayMin = _todaySeconds ~/ 60;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('공부해라', style: AppText.base(22, w: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: '공부 기록',
            icon: const Icon(Icons.bar_chart_rounded),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(
            tooltip: '부모 다시 설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SetupScreen(previous: p))),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              ParentAvatar(photoPath: p.photoPath, size: 180),
              const SizedBox(height: 20),
              Text('${p.childCall}, 공부할 시간이야!',
                  textAlign: TextAlign.center,
                  style: AppText.base(24, w: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('오늘 공부한 시간  ${todayMin ~/ 60 > 0 ? '${todayMin ~/ 60}시간 ' : ''}${todayMin % 60}분',
                  style: AppText.base(16, c: AppColors.inkSub)),
              const Spacer(),
              Text('얼마나 할까?', style: AppText.base(17, w: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final m in _presets)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: SizedBox(
                            width: double.infinity,
                            child: Text('$m분',
                                textAlign: TextAlign.center,
                                style: AppText.base(17,
                                    w: FontWeight.w700,
                                    c: _minutes == m
                                        ? Colors.black
                                        : AppColors.ink)),
                          ),
                          selected: _minutes == m,
                          showCheckmark: false,
                          selectedColor: AppColors.accent,
                          backgroundColor: AppColors.surface,
                          onSelected: (_) => setState(() => _minutes = m),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 20, color: AppColors.inkSub),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          '폰을 세워서 얼굴이 보이게 두세요. 카메라 영상은 폰 밖으로 나가지 않아요.',
                          style: AppText.base(13,
                              c: AppColors.inkSub, height: 1.4)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              BigButton(label: '공부 시작', onPressed: _start),
            ],
          ),
        ),
      ),
    );
  }
}
