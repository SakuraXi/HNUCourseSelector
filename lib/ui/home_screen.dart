import 'dart:async';

import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/config_store.dart';
import '../services/grab_service.dart';
import 'glass.dart';
import 'import_gate.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onOpenGg;

  const HomeScreen({super.key, this.onOpenGg});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ConfigStore _config = ConfigStore();
  final GrabService _grab = GrabService.instance;
  final ScrollController _logScroll = ScrollController();
  final List<String> _cachedLogs = [];

  late final TextEditingController _accountCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _maxRoundsCtrl;
  late final TextEditingController _delayCtrl;
  late final TextEditingController _roundsDelayCtrl;

  bool _autoStart = false;
  bool _importing = false;
  List<Course> _courses = [];
  String _startTimeStr = '';
  StreamSubscription<String>? _logSub;

  @override
  void initState() {
    super.initState();
    _accountCtrl = TextEditingController();
    _passwordCtrl = TextEditingController();
    _maxRoundsCtrl = TextEditingController(text: '10');
    _delayCtrl = TextEditingController(text: '1.0');
    _roundsDelayCtrl = TextEditingController(text: '5.0');

    _initConfig();
    _logSub = _grab.logs.listen((line) {
      if (!mounted) return;
      setState(() {
        _cachedLogs.add(line);
        if (_cachedLogs.length > 500) {
          _cachedLogs.removeRange(0, _cachedLogs.length - 500);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) {
          _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
        }
      });
    });
  }

  Future<void> _initConfig() async {
    await _config.load();
    final savedCourses = await _config.loadCourses();
    if (!mounted) return;
    setState(() {
      _courses = savedCourses.map((j) => Course.fromJson(j)).toList();
    });
    final d = _config.data;
    if (!mounted) return;
    setState(() {
      _accountCtrl.text = (d['account'] ?? '') as String;
      _passwordCtrl.text = (d['password'] ?? '') as String;
      _startTimeStr = (d['startTime'] ?? '') as String;
      _autoStart = (d['enableAutoStart'] ?? false) as bool;
      _maxRoundsCtrl.text = (d['maxRounds'] ?? 10).toString();
      _delayCtrl.text = (d['delayBase'] ?? 1.0).toString();
      _roundsDelayCtrl.text = (d['roundsDelay'] ?? 5.0).toString();
    });
  }

  void _saveConfig() {
    _config
      ..update('account', _accountCtrl.text)
      ..update('password', _passwordCtrl.text)
      ..update('startTime', _startTimeStr)
      ..update('enableAutoStart', _autoStart)
      ..update('maxRounds', int.tryParse(_maxRoundsCtrl.text) ?? 10)
      ..update('delayBase', double.tryParse(_delayCtrl.text) ?? 1.0)
      ..update('roundsDelay', double.tryParse(_roundsDelayCtrl.text) ?? 5.0)
      ..save();
  }

  /// 导入预选课表（HTML 或 parsedCourses.json），主界面可随时重新导入
  Future<void> _importCourses() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await importCoursesFromFile();
      if (result == null) return; // 用户取消
      final (ok, count, error) = result;
      if (!ok) {
        _grab.log('‼ 导入失败: $error');
        return;
      }
      final savedCourses = await _config.loadCourses();
      if (mounted) {
        setState(() =>
            _courses = savedCourses.map((j) => Course.fromJson(j)).toList());
      }
      _grab.log('📚 已导入 $count 门课程');
    } catch (e) {
      _grab.log('‼ 导入失败: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _startGrab() async {
    final selected =
        _courses.where((c) => c.selected && c.courseId.isNotEmpty).toList();
    if (selected.isEmpty) {
      _grab.log('⚠ 请先导入预选课表并勾选要抢的课程');
      return;
    }
    if (_accountCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      _grab.log('⚠ 请先填写账号和密码');
      return;
    }
    if (_autoStart && _startTimeStr.isEmpty) {
      _grab.log('⚠ 已开启定时开始，请选择开始时间');
      return;
    }
    _saveConfig();
    // 抢课循环在后台异步执行，日志通过流推送到 UI
    unawaited(_grab.run(
      account: _accountCtrl.text.trim(),
      password: _passwordCtrl.text,
      enableAutoStart: _autoStart,
      startTime: _startTimeStr,
      maxRounds: double.tryParse(_maxRoundsCtrl.text) ?? 10,
      delayBase: double.tryParse(_delayCtrl.text) ?? 1.0,
      roundsDelay: double.tryParse(_roundsDelayCtrl.text) ?? 5.0,
      courses: _courses,
    ));
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const LiquidBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 14),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 330, child: _buildSettingsPanel()),
                        const SizedBox(width: 14),
                        Expanded(child: _buildCoursePanel()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildLogPanel(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final s = GlassScheme.of(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF0A84FF), Color(0xFF8A4DFF)],
                  ),
                ),
                child: const Icon(Icons.school, color: Colors.white, size: 15),
              ),
              const SizedBox(width: 10),
              Text(
                '海大抢课助手',
                style: TextStyle(
                  color: s.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
        const Spacer(),
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          radius: 18,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _grab.isRunning
                      ? s.success
                      : s.textSecondary.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _grab.isRunning ? '抢课运行中' : '待机',
                style: TextStyle(color: s.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 6),
              // 公选课抢课页入口
              IconButton(
                tooltip: '公选课抢课',
                icon: Icon(
                  Icons.explore_outlined,
                  size: 18,
                  color: s.textSecondary,
                ),
                onPressed: widget.onOpenGg,
              ),
              const SizedBox(width: 4),
              // 需求1：深浅色切换图标（跟随系统 → 浅色 → 深色 循环）
              IconButton(
                tooltip: switch (ThemeController.instance.mode) {
                  ThemeMode.system => '主题：跟随系统（点击切换浅色）',
                  ThemeMode.light => '主题：浅色（点击切换深色）',
                  _ => '主题：深色（点击恢复跟随系统）',
                },
                icon: Icon(
                  switch (ThemeController.instance.mode) {
                    ThemeMode.system => Icons.brightness_auto,
                    ThemeMode.light => Icons.light_mode,
                    _ => Icons.dark_mode,
                  },
                  size: 17,
                  color: s.textSecondary,
                ),
                onPressed: () => setState(() => ThemeController.instance.cycle()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel() {
    // 需求3：设置栏不显示滚动条
    return GlassContainer(
      child: ScrollConfiguration(
        behavior:
            ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _panelTitle(Icons.tune, '设置'),
              const SizedBox(height: 14),
              GlassTextField(
                controller: _accountCtrl,
                label: '学号',
                icon: Icons.person_outline,
                onChanged: (_) => _saveConfig(),
              ),
              const SizedBox(height: 12),
              // 需求2：密码默认密文 + 眼睛图标切换明文
              GlassTextField(
                controller: _passwordCtrl,
                label: '密码',
                icon: Icons.lock_outline,
                obscure: true,
                onChanged: (_) => _saveConfig(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(Icons.timer_outlined,
                      size: 15, color: GlassScheme.of(context).textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '定时开始',
                    style: TextStyle(
                      color: GlassScheme.of(context).textPrimary
                          .withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: _autoStart,
                      activeThumbColor: const Color(0xFF0A84FF),
                      onChanged: (v) {
                        setState(() {
                          _autoStart = v;
                          // 开启时若尚未选择时间，默认 1 小时后
                          if (v && _startTimeStr.isEmpty) {
                            final t =
                                DateTime.now().add(const Duration(hours: 1));
                            _startTimeStr = _formatDateTime(t);
                          }
                        });
                        _saveConfig();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 开始时间改为日期时间选择器，定时未开启时禁用
              GlassDateTimeField(
                value: _startTimeStr,
                enabled: _autoStart,
                onPicked: (dt) {
                  setState(() => _startTimeStr = _formatDateTime(dt));
                  _saveConfig();
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GlassTextField(
                      controller: _maxRoundsCtrl,
                      label: '最大轮数',
                      icon: Icons.repeat,
                      labelInside: false,
                      onChanged: (_) => _saveConfig(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassTextField(
                      controller: _delayCtrl,
                      label: '课程间隔 (s)',
                      icon: Icons.speed,
                      labelInside: false,
                      onChanged: (_) => _saveConfig(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassTextField(
                      controller: _roundsDelayCtrl,
                      label: '轮间隔 (s)',
                      icon: Icons.more_time,
                      labelInside: false,
                      onChanged: (_) => _saveConfig(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GlassButton(
                    label: _importing ? '导入中...' : '导入预选课表',
                    icon: Icons.upload_file,
                    onPressed: _importing ? null : _importCourses,
                  ),
                  // 需求3：圆形问号帮助按钮
                  _HelpButton(),
                  const SizedBox(height: 52),
                  GlassButton(
                    label: '开始抢课',
                    icon: Icons.bolt,
                    primary: true,
                    onPressed: _grab.isRunning ? null : _startGrab,
                  ),
                  GlassButton(
                    label: '停止',
                    icon: Icons.stop_rounded,
                    accent: GlassScheme.of(context).danger,
                    onPressed: _grab.isRunning ? () => _grab.stop() : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Widget _buildCoursePanel() {
    final s = GlassScheme.of(context);
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _panelTitle(Icons.menu_book_outlined, '课程列表'),
              const Spacer(),
              Text(
                '${_courses.where((c) => c.selected).length}/${_courses.length} 已选',
                style: TextStyle(color: s.textHint, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _courses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 42, color: s.textHint),
                        const SizedBox(height: 10),
                        Text(
                          '点击左侧"导入预选课表"加载课程',
                          style:
                              TextStyle(color: s.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _courses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _courseCard(_courses[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _courseCard(Course c) {
    final s = GlassScheme.of(context);
    final grabbed = c.grabbed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: grabbed ? s.success.withValues(alpha: s.isDark ? 0.14 : 0.12) : s.courseFill(c.selected),
        border: Border.all(color: s.courseBorder(grabbed), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: grabbed
                  ? s.success
                  : c.selected
                      ? s.accent
                      : s.textSecondary.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.courseName} (${c.courseNum})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: s.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '教师: ${c.courseTeacher.isEmpty ? '未知' : c.courseTeacher}  ·  ID: ${c.courseId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: s.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (grabbed)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.check_circle, color: s.success, size: 18),
            )
          else
            Checkbox(
              value: c.selected,
              activeColor: s.accent,
              side: BorderSide(color: s.textSecondary.withValues(alpha: 0.5)),
              onChanged: _grab.isRunning
                  ? null
                  : (v) => setState(() => c.selected = v ?? false),
            ),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    final s = GlassScheme.of(context);
    return SizedBox(
      height: 190,
      child: GlassContainer(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _panelTitle(Icons.terminal, '运行日志'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: _logScroll,
                itemCount: _cachedLogs.length,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    _cachedLogs[i],
                    style: TextStyle(
                      color: _logColor(s, _cachedLogs[i]),
                      fontSize: 12,
                      fontFamily: 'Consolas',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _logColor(GlassScheme s, String line) {
    if (line.contains('✅') || line.contains('🎉')) return s.successText;
    if (line.contains('❌') || line.contains('‼')) return s.dangerText;
    if (line.contains('⚠') || line.contains('⏹')) return s.warnText;
    return s.logDefault();
  }

  Widget _panelTitle(IconData icon, String title) {
    final s = GlassScheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: s.textSecondary),
        const SizedBox(width: 7),
        Text(
          title,
          style: TextStyle(
            color: s.textPrimary.withValues(alpha: 0.8),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// 圆形问号帮助按钮（需求3）：按下打开使用说明对话框
class _HelpButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = GlassScheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showHelpDialog(context),
        child: Tooltip(
          message: '使用说明',
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: s.chipFill,
              border: Border.all(
                color: s.isDark
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.8),
                width: 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: s.isDark
                    ? [
                        Colors.white.withValues(alpha: 0.16),
                        Colors.white.withValues(alpha: 0.06),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.9),
                        Colors.white.withValues(alpha: 0.6),
                      ],
              ),
            ),
            child: Center(
              child: Text(
                '?',
                style: TextStyle(
                  color: s.textPrimary.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
