import 'dart:async';

import 'package:flutter/material.dart';

import '../models/gg_course.dart';
import '../services/config_store.dart';
import '../services/grab_service.dart';
import '../services/edge_login_service.dart';
import '../services/hnu_client.dart';
import '../services/ocr_service.dart';
import 'glass.dart';

/// 公选课（通识选修）抢课独立页面
/// 查询 xsxkGgxxkxk（会话分页自动抓全） → 勾选手动抢 / 按授课方式极速抢
class GgScreen extends StatefulWidget {
  final VoidCallback onBack;

  const GgScreen({super.key, required this.onBack});

  @override
  State<GgScreen> createState() => _GgScreenState();
}

class _GgScreenState extends State<GgScreen> {
  final ConfigStore _config = ConfigStore();
  final GrabService _grab = GrabService.instance;
  final ScrollController _logScroll = ScrollController();
  final List<String> _cachedLogs = [];

  late final TextEditingController _nameCtrl;
  late final TextEditingController _teacherCtrl;

  String _week = ''; // skxq
  String _jcStart = ''; // skjc
  String _jcEnd = ''; // endJc
  GgTeachType _type = GgTeachType.any;

  // 过滤复选框（对应 URL 参数 sfym/sfct/sfxx）
  bool _filterFull = false; // 过滤已满课程 → sfym
  bool _filterConflict = true; // 过滤冲突课程 → sfct
  bool _filterRestricted = true; // 过滤限选课程 → sfxx

  bool _loading = false;
  String _loadInfo = '';
  List<GgCourse> _courses = [];
  StreamSubscription<String>? _logSub;
  StreamSubscription<bool>? _runSub;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _teacherCtrl = TextEditingController();
    // 恢复上次保存的筛选条件
    _config.load().then((_) {
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = (_config.data['ggKcxx'] ?? '') as String;
        _teacherCtrl.text = (_config.data['ggSkls'] ?? '') as String;
        _week = (_config.data['ggSkxq'] ?? '') as String;
        _jcStart = (_config.data['ggSkjc'] ?? '') as String;
        _jcEnd = (_config.data['ggEndJc'] ?? '') as String;
        _type = GgTeachTypeX.fromId((_config.data['ggType'] ?? 'any') as String);
        _filterFull = (_config.data['ggFilterFull'] ?? false) as bool;
        _filterConflict = (_config.data['ggFilterConflict'] ?? true) as bool;
        _filterRestricted = (_config.data['ggFilterRestricted'] ?? true) as bool;
      });
    });
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
    _runSub = Stream<bool>.periodic(
            const Duration(milliseconds: 500), (_) => _grab.isRunning)
        .distinct()
        .listen((_) {
      if (mounted) setState(() {});
    });
  }

  /// 确保已登录（复用 GrabService 的共享客户端）
  Future<HnuClient> _ensureLogin() async {
    final existing = _grab.client;
    if (existing != null && existing.loggedIn) return existing;

    await _config.load();
    final account = (_config.data['account'] ?? '') as String;
    final password = (_config.data['password'] ?? '') as String;
    if (account.trim().isEmpty || password.isEmpty) {
      throw Exception('请先回到主页面填写学号和密码');
    }
    _grab.log('🌐 正在通过 Edge 浏览器自动登录...');
    final client = await EdgeLoginService.instance.loginViaEdge(
      account: account.trim(),
      password: password,
      log: _grab.log,
      ocr: OcrService.instance,
    );
    _grab.client = client;
    return client;
  }

  /// 保存筛选条件到配置（跨启动持久化）
  Future<void> _saveFilters() async {
    _config
      ..update('ggKcxx', _nameCtrl.text.trim())
      ..update('ggSkls', _teacherCtrl.text.trim())
      ..update('ggSkxq', _week)
      ..update('ggSkjc', _jcStart)
      ..update('ggEndJc', _jcEnd)
      ..update('ggType', _type.name)
      ..update('ggFilterFull', _filterFull)
      ..update('ggFilterConflict', _filterConflict)
      ..update('ggFilterRestricted', _filterRestricted);
    await _config.save();
  }

  String get _sfym => _filterFull ? 'true' : 'false';
  String get _sfct => _filterConflict ? 'true' : 'false';
  String get _sfxx => _filterRestricted ? 'true' : 'false';

  /// 查询公选课（自动翻页抓全）
  Future<void> _query() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadInfo = '正在查询...';
    });
    await _saveFilters();
    try {
      final client = await _ensureLogin();
      _grab.log('📚 查询公选课：${_nameCtrl.text.isEmpty ? '全部' : _nameCtrl.text}'
          '${_teacherCtrl.text.isEmpty ? '' : ' / ${_teacherCtrl.text}'}'
          '${_week.isEmpty ? '' : ' / 周$_week'}'
          '${_jcStart.isEmpty ? '' : ' / 第$_jcStart 节起'}');
      final courses = await client.fetchAllGgxxk(
        kcxx: _nameCtrl.text.trim(),
        skls: _teacherCtrl.text.trim(),
        skxq: _week,
        skjc: _jcStart,
        endJc: _jcEnd,
        sfym: _sfym,
        sfct: _sfct,
        sfxx: _sfxx,
        onProgress: (loaded, total, page) {
          if (mounted) {
            setState(() => _loadInfo = '已加载 $loaded/$total 门（第 $page 页）');
          }
        },
      );
      // 授课方式过滤：非"任意"时只保留匹配的课程（按 skdd 是否含"网络教学"）
      if (_type != GgTeachType.any) {
        courses.removeWhere((c) => !_type.matches(c));
      }
      // 保留原有勾选/抢中状态
      final oldById = {for (final c in _courses) c.jx0404id: c};
      for (final c in courses) {
        final old = oldById[c.jx0404id];
        if (old != null) {
          c.selected = old.selected;
          c.grabbed = old.grabbed;
        }
      }
      if (mounted) {
        setState(() {
          _courses = courses;
          _loadInfo = '共 ${courses.length} 门可选';
        });
      }
      _grab.log('📚 公选课查询完成，共 ${courses.length} 门');
    } catch (e) {
      _grab.log('‼ 公选课查询失败: $e');
      if (mounted) setState(() => _loadInfo = '查询失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startGrab() async {
    final selected = _courses.where((c) => c.selected && c.selectable).toList();
    if (selected.isEmpty) {
      _grab.log('⚠ 请先查询并勾选要抢的公选课');
      return;
    }
    await _config.load();
    final d = _config.data;
    _grab.log('⚙ 使用参数：最大轮数 ${d['maxRounds']} / 课程间隔 ${d['delayBase']}s / '
        '轮间隔 ${d['roundsDelay']}s（在主页面设置栏修改）');
    unawaited(_grab.runGg(
      account: (_config.data['account'] ?? '') as String,
      password: (_config.data['password'] ?? '') as String,
      maxRounds: double.tryParse('${d['maxRounds'] ?? 10}') ?? 10,
      delayBase: double.tryParse('${d['delayBase'] ?? 1.0}') ?? 1.0,
      roundsDelay: double.tryParse('${d['roundsDelay'] ?? 5.0}') ?? 5.0,
      courses: _courses,
    ));
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _runSub?.cancel();
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
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
                  _buildFilterPanel(),
                  const SizedBox(height: 14),
                  Expanded(child: _buildCoursePanel()),
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
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          radius: 18,
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: widget.onBack,
                  child: Row(
                    children: [
                      Icon(Icons.arrow_back,
                          size: 17, color: s.textSecondary),
                      const SizedBox(width: 6),
                      Text('返回',
                          style: TextStyle(
                              color: s.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(width: 1, height: 18, color: s.fieldBorder),
              const SizedBox(width: 12),
              Icon(Icons.explore, size: 17, color: s.accent),
              const SizedBox(width: 8),
              Text(
                '公选课抢课',
                style: TextStyle(
                  color: s.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterPanel() {
    final s = GlassScheme.of(context);
    return GlassContainer(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_outlined,
                  size: 15, color: s.textSecondary),
              const SizedBox(width: 7),
              Text(
                '查询条件',
                style: TextStyle(
                  color: s.textPrimary.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (_loadInfo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    _loadInfo,
                    style: TextStyle(color: s.textHint, fontSize: 11.5),
                  ),
                ),
              _filterCheck('过滤已满', _filterFull,
                  (v) => setState(() => _filterFull = v ?? false)),
              const SizedBox(width: 10),
              _filterCheck('过滤冲突', _filterConflict,
                  (v) => setState(() => _filterConflict = v ?? false)),
              const SizedBox(width: 10),
              _filterCheck('过滤限选', _filterRestricted,
                  (v) => setState(() => _filterRestricted = v ?? false)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 200,
                child: GlassTextField(
                  controller: _nameCtrl,
                  labelInside: false,
                  label: '课程名称/编码',
                  icon: Icons.menu_book_outlined,
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: GlassTextField(
                  controller: _teacherCtrl,
                  label: '上课教师',
                  labelInside: false,
                  icon: Icons.person_outline,
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: _dropdown(
                  '授课方式',
                  _type.name,
                  const ['any', 'offline', 'online'],
                  (v) => GgTeachTypeX.fromId(v).label,
                  (v) => setState(
                      () => _type = GgTeachTypeX.fromId(v ?? 'any')),
                ),
              ),
              SizedBox(
                width: 110,
                child: _dropdown(
                  '星期',
                  _week,
                  const ['', '1', '2', '3', '4', '5', '6', '7'],
                  _weekLabel,
                      (v) => setState(() => _week = v ?? ''),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: _dropdown(
                  '节次起',
                  _jcStart,
                  _jcItems,
                  _jcLabel,
                      (v) {
                    setState(() {
                      _jcStart = v ?? '';
                      if (_jcStart.isNotEmpty &&
                          _jcEnd.isNotEmpty &&
                          int.parse(_jcEnd) < int.parse(_jcStart)) {
                        _jcEnd = _jcStart;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                child: _dropdown(
                  '节次止',
                  _jcEnd,
                  _jcItems,
                  _jcLabel,
                      (v) => setState(() => _jcEnd = v ?? ''),
                ),
              ),
              const SizedBox(width: 20),
              GlassButton(
                label: _loading ? '查询中...' : '查询',
                icon: Icons.search,
                onPressed: _loading ? null : _query,
              ),
              const SizedBox(width: 10),
              GlassButton(
                label: '直接抢课',
                icon: Icons.accessible_forward,
                primary: true,
                onPressed: _grab.isRunning ? null : _startAutoGrab,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 极速抢课：按当前筛选条件 + 授课方式，自动查询→筛选→立即抢，多轮循环
  Future<void> _startAutoGrab() async {
    await _config.load();
    await _saveFilters();
    final d = _config.data;
    final account = (_config.data['account'] ?? '') as String;
    final password = (_config.data['password'] ?? '') as String;
    if (account.trim().isEmpty || password.isEmpty) {
      _grab.log('⚠ 请先回到主页面填写学号和密码');
      return;
    }
    _grab.log('⚙ 使用参数：最大轮数 ${d['maxRounds']} / 课程间隔 ${d['delayBase']}s / '
        '轮间隔 ${d['roundsDelay']}s（在主页面设置栏修改）');
    unawaited(_grab.runGgAuto(
      account: account.trim(),
      password: password,
      kcxx: _nameCtrl.text.trim(),
      skls: _teacherCtrl.text.trim(),
      skxq: _week,
      skjc: _jcStart,
      endJc: _jcEnd,
      sfym: _sfym,
      sfct: _sfct,
      sfxx: _sfxx,
      teachType: _type,
      maxRounds: double.tryParse('${d['maxRounds'] ?? 10}') ?? 10,
      delayBase: double.tryParse('${d['delayBase'] ?? 1.0}') ?? 1.0,
      roundsDelay: double.tryParse('${d['roundsDelay'] ?? 5.0}') ?? 5.0,
    ));
  }

  static const List<String> _jcItems = [
    '', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15'
  ];

  String _weekLabel(String v) =>
      v.isEmpty ? '全部' : '周${['一', '二', '三', '四', '五', '六', '日'][int.parse(v) - 1]}';

  String _jcLabel(String v) => v.isEmpty ? '全部' : '第 $v 节';

  /// 过滤条件
  Widget _filterCheck(String label, bool value, ValueChanged<bool?> onChanged) {
    final s = GlassScheme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                activeColor: s.accent,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(
                    color: s.textSecondary.withValues(alpha: 0.6), width: 1),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(color: s.textSecondary, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> items,
      String Function(String) display, ValueChanged<String?> onChanged) {
    final s = GlassScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: s.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: s.fieldFill,
            border: Border.all(color: s.fieldBorder, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              isDense: true,
              icon: Icon(Icons.arrow_drop_down,
                  size: 16, color: s.textSecondary),
              dropdownColor: s.isDark ? const Color(0xFF1C2029) : Colors.white,
              style: TextStyle(color: s.textPrimary, fontSize: 12),
              items: items
                  .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(display(v), overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoursePanel() {
    final s = GlassScheme.of(context);
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _panelTitle(Icons.list_alt, '可选课程'),
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
                        Icon(Icons.explore_outlined,
                            size: 42, color: s.textHint),
                        const SizedBox(height: 10),
                        Text(
                          '设置筛选条件后点击"查询"加载公选课列表',
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

  Widget _courseCard(GgCourse c) {
    final s = GlassScheme.of(context);
    final grabbed = c.grabbed;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: grabbed
            ? s.success.withValues(alpha: s.isDark ? 0.14 : 0.12)
            : s.courseFill(c.selected),
        border: Border.all(
          color: grabbed
              ? s.success.withValues(alpha: 0.5)
              : s.isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.08),
          width: 1,
        ),
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.courseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: s.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${c.courseNum})',
                      style: TextStyle(
                          color: s.textHint, fontSize: 11.5),
                    ),
                    if (c.isFull) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: s.danger.withValues(alpha: 0.15),
                        ),
                        child: Text(
                          '已满',
                          style: TextStyle(
                              color: s.dangerText, fontSize: 10.5),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '教师: ${c.teacher.isEmpty ? '未知' : c.teacher}  ·  ${c.credit}学分  ·  ${c.enrolled}/${c.capacity}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: s.textSecondary, fontSize: 11.5),
                ),
                if (c.timeClean.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    c.timeClean,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: s.textHint, fontSize: 11),
                  ),
                ],
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
            Row(
              children: [
                _panelTitle(Icons.terminal, '运行日志'),
                const Spacer(),
                GlassButton(
                  label: '开始抢课',
                  icon: Icons.bolt,
                  primary: true,
                  onPressed: _grab.isRunning ? null : _startGrab,
                ),
                const SizedBox(width: 10),
                GlassButton(
                  label: '停止',
                  icon: Icons.stop_rounded,
                  accent: s.danger,
                  onPressed: _grab.isRunning ? () => _grab.stop() : null,
                ),
              ],
            ),
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
