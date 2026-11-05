/// 공부 한 번의 기록.
class StudyRecord {
  final DateTime startedAt;
  final int plannedMinutes;

  /// 실제로 시간이 흐른(자리에 있던) 초.
  final int studiedSeconds;
  final int drowsyCount;
  final int awayCount;
  final int distractedCount;

  /// 목표 시간을 끝까지 채웠는지.
  final bool completed;

  const StudyRecord({
    required this.startedAt,
    required this.plannedMinutes,
    required this.studiedSeconds,
    required this.drowsyCount,
    required this.awayCount,
    required this.distractedCount,
    required this.completed,
  });

  int get warningCount => drowsyCount + awayCount + distractedCount;

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'plannedMinutes': plannedMinutes,
        'studiedSeconds': studiedSeconds,
        'drowsyCount': drowsyCount,
        'awayCount': awayCount,
        'distractedCount': distractedCount,
        'completed': completed,
      };

  factory StudyRecord.fromJson(Map<String, dynamic> j) => StudyRecord(
        startedAt: DateTime.parse(j['startedAt'] as String),
        plannedMinutes: j['plannedMinutes'] as int,
        studiedSeconds: j['studiedSeconds'] as int,
        drowsyCount: j['drowsyCount'] as int,
        awayCount: j['awayCount'] as int,
        distractedCount: j['distractedCount'] as int,
        completed: j['completed'] as bool,
      );
}
