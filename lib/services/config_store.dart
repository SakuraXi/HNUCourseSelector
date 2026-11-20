import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ConfigStore {
  static const Map<String, dynamic> defaults = {
    'account': '',
    'password': '',
    'enableAutoStart': false,
    'startTime': '',
    'maxRounds': 10,
    'delayBase': 1.0,
    'roundsDelay': 5.0,
    'themeMode': 'system',
    // 公选课筛选条件
    'ggKcxx': '',
    'ggSkls': '',
    'ggSkxq': '',
    'ggSkjc': '',
    'ggEndJc': '',
    'ggType': 'any',
  };

  Map<String, dynamic> _cache = Map.of(defaults);
  File? _file;

  Map<String, dynamic> get data => _cache;

  Future<File> _ensureFile(String name) async {
    if (_file != null && _file!.path.endsWith(name)) return _file!;
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}\\$name');
    return f;
  }

  Future<void> load() async {
    try {
      final f = await _ensureFile('config.json');
      if (await f.exists()) {
        final content = await f.readAsString();
        final loaded = jsonDecode(content) as Map<String, dynamic>;
        _cache = {...defaults, ...loaded};
      }
    } catch (_) {
      _cache = Map.of(defaults);
    }
  }

  Future<void> save() async {
    try {
      final f = await _ensureFile('config.json');
      await f.writeAsString(
          const JsonEncoder.withIndent('  ').convert(_cache));
    } catch (_) {}
  }

  void update(String key, dynamic value) {
    _cache[key] = value;
  }

  /// 课程缓存（parsedCourses.json）
  Future<void> saveCourses(List<Map<String, dynamic>> courses) async {
    try {
      final f = await _ensureFile('parsedCourses.json');
      await f.writeAsString(
          const JsonEncoder.withIndent('  ').convert(courses));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> loadCourses() async {
    try {
      final f = await _ensureFile('parsedCourses.json');
      if (await f.exists()) {
        final content = await f.readAsString();
        final list = jsonDecode(content) as List<dynamic>;
        return list.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return [];
  }

  /// 检测 parsedCourses.json 是否为"有效"预选课表：
  static Future<bool> hasValidParsedCourses() async {
    final courses = await ConfigStore().loadCourses();
    if (courses.isEmpty) return false;
    return courses.any((c) =>
        c['courseID'] != null && c['courseID'].toString().isNotEmpty);
  }
}
