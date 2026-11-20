import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/config_store.dart';
import 'services/ocr_service.dart';
import 'ui/gg_screen.dart';
import 'ui/home_screen.dart';
import 'ui/import_gate.dart';

void main() {
  runApp(const HnuCourseSelectorApp());
}

/// 全局主题，system（跟随 Windows）→ light → dark 循环切换
class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController();

  ThemeMode mode = ThemeMode.system;

  Future<void> load() async {
    final config = ConfigStore();
    await config.load();
    final v = (config.data['themeMode'] ?? 'system') as String;
    mode = switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void set(ThemeMode m) {
    mode = m;
    notifyListeners();
    ConfigStore()
      ..update('themeMode', switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        _ => 'system',
      })
      ..save();
  }

  /// 跟随系统 → 浅色 → 深色
  void cycle() {
    set(switch (mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      _ => ThemeMode.system,
    });
  }
}

class HnuCourseSelectorApp extends StatelessWidget {
  const HnuCourseSelectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 预热 OCR 引擎（加载 ONNX 模型 + 字符表）
    OcrService.instance.ensureReady();

    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: '海大抢课助手',
          debugShowCheckedModeBanner: false,
          // 日期/时间选择器等 Material 组件显示为中文
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          // 需求1：默认跟随 Windows 深浅色模式，可手动切换
          themeMode: ThemeController.instance.mode,
          home: const AppRoot(),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0A84FF),
        brightness: brightness,
      ),
      fontFamily: 'Microsoft YaHei UI',
      useMaterial3: true,
    );
  }
}

/// 未检测到有效 parsedCourses.json 时，停留在导入页，
/// 导入成功后才放行进入主界面
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  Future<bool>? _gateFuture;
  bool _entered = false;
  bool _showGg = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ThemeController.instance.load();
    _gateFuture = ConfigStore.hasValidParsedCourses();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_gateFuture == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0D14),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFF0A84FF),
            strokeWidth: 2.5,
          ),
        ),
      );
    }
    if (_entered) {
      return _showGg
          ? GgScreen(onBack: () => setState(() => _showGg = false))
          : HomeScreen(onOpenGg: () => setState(() => _showGg = true));
    }
    return FutureBuilder<bool>(
      future: _gateFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF0A0D14),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF0A84FF),
                strokeWidth: 2.5,
              ),
            ),
          );
        }
        final ok = snapshot.data ?? false;
        if (ok) {
          // 两个页面：主页面（必修/预选课表）与公选课抢课页
          return _showGg
              ? GgScreen(onBack: () => setState(() => _showGg = false))
              : HomeScreen(
                  onOpenGg: () => setState(() => _showGg = true),
                );
        }
        return ImportGate(
          onImported: (_) => setState(() => _entered = true),
        );
      },
    );
  }
}
