import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/course.dart';
import '../services/hnu_client.dart';
import 'glass.dart';

/// 打开文件选择器导入预选课表，支持两种格式：
/// 1. 浏览器另存的预选课表 HTML（.html/.htm）→ 解析后保存
/// 2. 之前解析过的 parsedCourses.json（.json）→ 校验合法后保存
///
/// 返回：用户取消返回 null；成功返回 (true, 有效课程数, null)；失败返回 (false, 0, 错误信息)
Future<(bool, int, String?)?> importCoursesFromFile() async {
  const typeGroup = XTypeGroup(
    label: '预选课表 (HTML / JSON)',
    extensions: ['html', 'htm', 'json'],
  );
  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null) return null; // 用户取消

  final path = file.path.toLowerCase();
  final List<Course> valid;

  if (path.endsWith('.json')) {
    // JSON格式严格validation，不可用直接打回
    final raw = await file.readAsString();
    final err = validateCoursesJson(raw);
    if (err != null) return (false, 0, err);
    final list = (jsonDecode(raw) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    valid = list.map((j) => Course.fromJson(j)).toList();
  } else {
    // HTML解析预选课表页面
    final html = await file.readAsString();
    final courses = HnuClient.parseCourses(html);
    valid = courses.where((c) => c.courseId.isNotEmpty).toList();
    if (valid.isEmpty) {
      return (
        false,
        0,
        '解析结果为空：请确认选择的是"预选课表"页面（表格需含课程号、课程名、教师和选课操作链接），'
            '或直接选择之前导出的 parsedCourses.json'
      );
    }
  }

  // 保存 parsedCourses.json（与 ConfigStore 同一应用支持目录）
  final dir = await getApplicationSupportDirectory();
  final out = File('${dir.path}\\parsedCourses.json');
  await out.writeAsString(
    const JsonEncoder.withIndent('  ')
        .convert(valid.map((c) => c.toJson()).toList()),
  );
  return (true, valid.length, null);
}

/// 校验课程 JSON 是否合法可用。
/// 合法 = 非空数组 + 每项为含 courseName/courseNum/courseTeacher/courseID
/// 四个字符串字段的 Map + 至少一门课的 courseID 非空。
/// 合法返回 null，否则返回错误原因。
String? validateCoursesJson(String raw) {
  final dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return '文件不是合法的 JSON';
  }
  if (decoded is! List || decoded.isEmpty) {
    return 'JSON 内容应为非空的课程数组';
  }
  final requiredKeys = ['courseName', 'courseNum', 'courseTeacher', 'courseID'];
  for (var i = 0; i < decoded.length; i++) {
    final item = decoded[i];
    if (item is! Map) {
      return '第 ${i + 1} 项不是课程对象（应为 {"courseName": ...} 结构）';
    }
    for (final key in requiredKeys) {
      final v = item[key];
      if (v == null || v is! String) {
        return '第 ${i + 1} 门课程缺少字段 "$key"（需为字符串），该 JSON 可能不是本应用导出的预选课表';
      }
    }
  }
  final hasValidId =
      decoded.any((e) => (e['courseID'] as String).trim().isNotEmpty);
  if (!hasValidId) {
    return '所有课程的选课 ID 均为空，该课表不可用';
  }
  return null;
}

/// 帮助对话框
void showHelpDialog(BuildContext context) {
  final s = GlassScheme.of(context);
  showDialog(
    context: context,
    barrierColor: s.isDark ? Colors.black54 : Colors.black26,
    builder: (context) {
      final s = GlassScheme.of(context);
      return Dialog(
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: 460,
          child: GlassContainer(
            radius: 16,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.help_outline, size: 17, color: s.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    '使用说明',
                    style: TextStyle(
                      color: s.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const Divider(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '💡 如何导入预选课程？',
                          style: TextStyle(
                            color: s.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _helpStep(s, '1. 登录教务系统的【学生选课】页面，并进入本次选课的【预选场次】。'),
                        _helpStep(s, '2. 点击【选择课程】按钮，会弹出本次选课的课程列表窗口。'),
                        _helpStep(s, '3. 在浏览器页面空白处（右键 → 【另存为】（或按 Ctrl + S 组合键）。'),
                        _helpStep(s, '4. 保存类型选择【网页，仅 HTML】(*.html)。'),
                        _helpStep(s, '5. 回到本助手，点击【导入预选课表】按钮，选择刚保存的文件。'),
                        const SizedBox(height: 10),
                        Text(
                          '⚠ 注意：请勿直接保存"快捷方式"或"网页档案(mhtml)"，必须是完整的 HTML 文件。',
                          style: TextStyle(
                            color: s.warnText,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: GlassButton(
                  label: '确定',
                  icon: Icons.check,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
          ),
        ),
      );
    },
  );
}

Widget _helpStep(GlassScheme s, String text) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      text,
      style: TextStyle(
        color: s.textPrimary.withValues(alpha: 0.85),
        fontSize: 12.5,
        height: 1.55,
      ),
    ),
  );
}

/// 未检测到有效 parsedCourses.json 时，应用停留在本页，
/// 必须导入预选课表并解析成功后才能进入主界面
class ImportGate extends StatefulWidget {
  const ImportGate({super.key, required this.onImported});

  /// 导入解析成功后回调（参数为解析出的有效课程数）
  final ValueChanged<int> onImported;

  @override
  State<ImportGate> createState() => _ImportGateState();
}

class _ImportGateState extends State<ImportGate> {
  bool _importing = false;
  String? _error;

  Future<void> _pickAndImport() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await importCoursesFromFile();
      if (result == null) return; // 用户取消
      final (ok, count, error) = result;
      if (!ok) {
        setState(() => _error = error);
        return;
      }
      if (mounted) widget.onImported(count);
    } catch (e) {
      setState(() => _error = '导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = GlassScheme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const LiquidBackground(),
          Center(
            child: SizedBox(
              width: 480,
              child: GlassContainer(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                Color(0xFF0A84FF),
                                Color(0xFF8A4DFF),
                              ],
                            ),
                          ),
                          child: const Icon(Icons.school,
                              color: Colors.white, size: 19),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '海大抢课助手',
                          style: TextStyle(
                            color: s.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '首次使用需要导入预选课表',
                      style: TextStyle(
                        color: s.textPrimary.withValues(alpha: 0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '支持两种格式：① 浏览器另存的预选课表 HTML 文件（"网页，仅 HTML"）；'
                      '② 之前导出的 parsedCourses.json（导入时会校验合法性）。',
                      style: TextStyle(
                        color: s.textSecondary,
                        fontSize: 12.5,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: GlassButton(
                        label: _importing ? '解析中...' : '导入预选课表',
                        icon: Icons.upload_file,
                        primary: true,
                        onPressed: _importing ? null : _pickAndImport,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: s.danger.withValues(alpha: 0.12),
                          border: Border.all(
                              color: s.danger.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: s.dangerText,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
