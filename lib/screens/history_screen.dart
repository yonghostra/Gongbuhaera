import 'package:flutter/material.dart';

import '../models/study_record.dart';
import '../services/storage_service.dart';
import '../theme.dart';

/// 공부 기록 (최근 순).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<StudyRecord>? _records;

  @override
  void initState() {
    super.initState();
    StorageService.loadRecords().then((r) {
      if (mounted) setState(() => _records = r);
    });
  }

  static String _date(DateTime d) {
    const wd = ['월', '화', '수', '목', '금', '토', '일'];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.month}월 ${d.day}일 (${wd[d.weekday - 1]}) $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    final weekSec = records == null
        ? 0
        : records
            .where((r) =>
                DateTime.now().difference(r.startedAt).inDays < 7)
            .fold<int>(0, (s, r) => s + r.studiedSeconds);
    return Scaffold(
      appBar: AppBar(
        title: Text('공부 기록', style: AppText.base(20, w: FontWeight.w800)),
      ),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? Center(
                  child: Text('아직 기록이 없어요.\n첫 공부를 시작해 볼까요?',
                      textAlign: TextAlign.center,
                      style: AppText.base(17, c: AppColors.inkSub, height: 1.6)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: AppColors.sienna.withValues(alpha: 0.18),
                          border: Border.all(
                              color: AppColors.siennaLight
                                  .withValues(alpha: 0.5),
                              width: 1.5),
                          borderRadius: BorderRadius.circular(24)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('최근 7일',
                              style: AppText.base(15, c: AppColors.inkSub)),
                          const SizedBox(height: 4),
                          Text(
                              '${weekSec ~/ 3600}시간 ${(weekSec % 3600) ~/ 60}분',
                              style: AppText.number(36,
                                  c: AppColors.siennaLight)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final r in records)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(18)),
                        child: Row(
                          children: [
                            Icon(
                                r.completed
                                    ? Icons.check_circle
                                    : Icons.timelapse,
                                color: r.completed
                                    ? AppColors.siennaLight
                                    : AppColors.inkFaint),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_date(r.startedAt),
                                      style: AppText.base(14,
                                          c: AppColors.inkSub)),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${r.studiedSeconds ~/ 60}분 / 목표 ${r.plannedMinutes}분',
                                      style: AppText.base(17,
                                          w: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                      '졸음 ${r.drowsyCount} · 자리 비움 ${r.awayCount} · 딴짓 ${r.distractedCount}',
                                      style: AppText.base(13,
                                          c: AppColors.inkSub)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}
