import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/parent_profile.dart';
import '../models/study_record.dart';

/// 기기 안 저장소. 서버에 아무것도 올리지 않는다.
class StorageService {
  static const _kProfile = 'parent_profile';
  static const _kRecords = 'study_records';

  static Future<ParentProfile?> loadProfile() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kProfile);
    if (raw == null) return null;
    try {
      return ParentProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveProfile(ParentProfile profile) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kProfile, jsonEncode(profile.toJson()));
  }

  static Future<List<StudyRecord>> loadRecords() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kRecords);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => StudyRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addRecord(StudyRecord r) async {
    final list = await loadRecords();
    list.insert(0, r); // 최신이 위로
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kRecords, jsonEncode(list.take(500).map((e) => e.toJson()).toList()));
  }
}
