import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'hnu_client.dart';
import 'ocr_service.dart';

/* 通过 Edge 浏览器（DevTools 协议）自动登录教务系统, 登录成功后提取 Cookie 注入 dio */
class EdgeLoginService {
  EdgeLoginService._();
  static final EdgeLoginService instance = EdgeLoginService._();

  static const int _basePort = 9223;

  Process? _process;
  _Cdp? _cdp;
  int? _port;
  DateTime _lastReqAt = DateTime.fromMillisecondsSinceEpoch(0);

  // 会话失效自动恢复所需的凭据/回调
  String _lastAccount = '';
  String _lastPassword = '';
  void Function(String) _log = (_) {};
  OcrService? _ocr;

  // 查找 Edge 可执行文件
  String _findEdge() {
    final candidates = <String>[
      r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    ];
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    throw Exception('未找到 Edge 浏览器，请确认已安装 Microsoft Edge');
  }

  // 查一个未被占用的调试端口
  Future<int> _findFreePort() async {
    for (var port = _basePort; port < _basePort + 10; port++) {
      try {
        final s = await ServerSocket.bind('127.0.0.1', port);
        await s.close();
        return port;
      } catch (_) {
        continue;
      }
    }
    throw Exception('没有可用的本地调试端口');
  }

  Future<dynamic> _httpGetJson(String url) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }

  // 完整登录：返回一个已带登录会话的 HnuClient。
  Future<HnuClient> loginViaEdge({
    required String account,
    required String password,
    required void Function(String) log,
    required OcrService ocr,
  }) async {
    // 记录凭据/日志通道，供请求失效时自动重登使用
    _lastAccount = account;
    _lastPassword = password;
    _log = log;
    _ocr = ocr;

    // 复用仍存活的浏览器实例
    if (_cdp != null && _process != null) {
      try {
        final st = jsonDecode(
            '${await _evalSafe('JSON.stringify({has: !!document.querySelector("#userAccount")})')}');
        if (!(st['has'] as bool)) {
          log('✅ 复用已打开的浏览器会话');
          await _enterSelectionInBrowser(log);
          return await _buildClient(log, ocr);
        }
        log('🧭 复用已打开的浏览器，执行自动登录...');
        await _ensureLoggedIn(account, password, log, ocr);
        await _enterSelectionInBrowser(log);
        return await _buildClient(log, ocr);
      } catch (e) {
        log('⚠ 浏览器连接失效，重新启动 Edge...（$e）');
        _disposeBrowser();
      }
    }

    await _launchBrowser(log);
    await _ensureLoggedIn(account, password, log, ocr);
    await _enterSelectionInBrowser(log);
    return await _buildClient(log, ocr);
  }

  // 浏览器访问 xklc_list → 检测轮次列表/「进入选课」按钮 → 在浏览器中点击，
  // [force] = true 时跳过"已在公选课页面"的短路判断
  Future<void> _enterSelectionInBrowser(void Function(String) log,
      {bool force = false}) async {
    if (!force) {
      try {
        final st = jsonDecode('${await _evalSafe(_ggLoadedJs)}');
        if (st['ggLoaded'] as bool) {
          log('✅ 浏览器已在公选课选课页面');
          return;
        }
      } catch (_) {}
    }
    log('🧭 浏览器进入选课入口...');
    await _evalSafe('location.href = "/jsxsd/xsxk/xklc_list"');
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 1000));
      final info = jsonDecode('${await _evalSafe(_pageStateJs)}');
      final url = '${info['url']}';
      final hasRounds = info['hasRounds'] as bool;
      final hasEnter = info['hasEnter'] as bool;

      if (hasEnter) {
        final r = '${await _evalSafe(_clickEnterJs)}';
        if (r == 'ok') {
          log('✅ 已进入选课');
          await Future.delayed(const Duration(milliseconds: 2000));
          // 等待选课框架页出现（进入选课后的页面含 selectBottom 底部 iframe）
          var frameFound = false;
          for (var w = 0; w < 15; w++) {
            final st = jsonDecode(
                '${await _evalSafe(_frameStateJs)}');
            if (st['found'] as bool) {
              frameFound = true;
              break;
            }
            await Future.delayed(const Duration(seconds: 1));
          }
          if (frameFound) {
            // jpbxxk 定义在 selectBottom 框架里（不在 top）——
            // 通过同源框架引用执行：selectBottom.contentWindow.jpbxxk('ggksfkf')
            await _evalSafe(_runJpbxxkJs);
            await Future.delayed(const Duration(milliseconds: 1000));
            return;
          }
          // 找不到 iframe 结构时用静默 fetch 模拟
          log('⚠ 未找到选课页签/框架，改用静默 fetch 模拟...');
          final referer = await _findSelectBottomUrl();
          final body = await _browserFetch(
              'GET', 'https://jxgl.hainanu.edu.cn/jsxsd/xsxkkc/getGgxxkxk',
              const {}, referrer: referer);
          if (body.contains('系统暂停') || body.contains('暂未开放')) {
            await Future.delayed(const Duration(seconds: 1));
            await _browserFetch(
                'GET', 'https://jxgl.hainanu.edu.cn/jsxsd/xsxkkc/getGgxxkxk',
                const {}, referrer: referer);
          }
          log('✅ 公选课上下文已建立（静默模拟）');
          return;
        }
      }
      // 轮次列表页 → 跳转第一个轮次
      if (hasRounds && !hasEnter) {
        final href =
            '${await _evalSafe('(document.querySelector("#dataList td a")||{href:""}).href || ""')}';
        if (href.isNotEmpty) {
          await _evalSafe('location.href = ${jsonEncode(href)}');
        }
        continue;
      }
      // 主页 → 重新访问 xklc_list
      if (url.contains('xsMain')) {
        await _evalSafe('location.href = "/jsxsd/xsxk/xklc_list"');
      }
    }
    throw Exception('未能进入选课（未找到"进入选课"入口，请确认选课已开放）');
  }

  // 启动 Edge 并连接调试通道
  Future<void> _launchBrowser(void Function(String) log) async {
    final edgePath = _findEdge();
    final port = await _findFreePort();
    final tempDir = await Directory.systemTemp.createTemp('edge_cdp');

    log('🧭 正在启动 Edge 浏览器...');
    final process = await Process.start(edgePath, [
      '--remote-debugging-port=$port',
      '--user-data-dir=${tempDir.path}',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-sync',
      '--window-size=1280,860',
      'https://jxgl.hainanu.edu.cn/jsxsd/',
    ]);

    // 等待 DevTools 端口ready并access教务页面
    Map<String, dynamic>? target;
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        final list = await _httpGetJson('http://127.0.0.1:$port/json/list');
        if (list is! List) continue;
        final pages =
            list.whereType<Map>().where((t) => t['type'] == 'page').toList();
        if (pages.isEmpty) continue;
        target = pages.firstWhere(
          (t) => '${t['url']}'.contains('jxgl.hainanu.edu.cn'),
          orElse: () => pages.first,
        ) as Map<String, dynamic>;
        break;
      } catch (_) {}
    }
    if (target == null) {
      process.kill();
      throw Exception('连接 Edge 调试端口超时');
    }
    _process = process;
    _port = port;
    _cdp = await _Cdp.connect('${target['webSocketDebuggerUrl']}');
    log('🧭 已连接浏览器调试通道');
  }

  // 确保浏览器内已登录，未登录就自动填表单 + OCR 验证码
  Future<void> _ensureLoggedIn(
    String account,
    String password,
    void Function(String) log,
    OcrService ocr,
  ) async {
    // 等待登录表单出现or发现已是登录态
    var alreadyLoggedIn = false;
    for (var i = 0; i < 20; i++) {
      final st = jsonDecode(
          '${await _evalSafe('JSON.stringify({has: !!document.querySelector("#userAccount"), url: location.href})')}');
      if (!(st['has'] as bool)) {
        alreadyLoggedIn = '${st['url']}'.contains('xsMain') ||
            '${st['url']}'.contains('main_index') ||
            '${st['url']}'.contains('xsxk');
        if (alreadyLoggedIn) break;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    if (alreadyLoggedIn) {
      log('✅ 浏览器已有登录会话，跳过登录');
      return;
    }

    // 验证码：截图 → OCR → 填入 → 点登录，失败自动换一张重试（最多 5 次）
    var loggedIn = false;
    for (var captchaAttempt = 1; captchaAttempt <= 5; captchaAttempt++) {
      // 确保回到登录页
      for (var w = 0; w < 8; w++) {
        final has = jsonDecode(
            '${await _evalSafe('JSON.stringify({has: !!document.querySelector("#userAccount")})')}');
        if (has['has'] as bool) break;
        await _evalSafe('location.href = "/jsxsd/"');
        await Future.delayed(const Duration(milliseconds: 800));
      }
      await _evalSafe(
          'document.querySelector("#userAccount").value=${jsonEncode(account)}');
      await _evalSafe(
          'document.querySelector("#userPassword").value=${jsonEncode(password)}');
      log('🧩 识别验证码（第 $captchaAttempt/5 次）...');
      final rectJson = '${await _evalSafe(_rectJs)}';
      final rect = jsonDecode(rectJson);
      final shot = await _cdp!.send('Page.captureScreenshot', {
        'format': 'png',
        'clip': {
          'x': rect['x'],
          'y': rect['y'],
          'width': rect['w'],
          'height': rect['h'],
          'scale': rect['dpr'],
        },
      });
      final png = base64.decode('${shot['data']}');
      final code = await ocr.classification(Uint8List.fromList(png));
      log('验证码识别结果: "$code"');
      await _evalSafe(
          'document.querySelector("#RANDOMCODE").value=${jsonEncode(code)}');
      await _evalSafe('document.getElementById("btn-login").click()');

      // 页面跳转后 #userAccount 消失即成功登录
      var ok = false;
      for (var w = 0; w < 12; w++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final st = jsonDecode(
            '${await _evalSafe('JSON.stringify({has: !!document.querySelector("#userAccount")})')}');
        if (!(st['has'] as bool)) {
          ok = true;
          break;
        }
      }
      if (ok) {
        log('✅ 浏览器自动登录成功');
        loggedIn = true;
        break;
      }
      log('⚠ 登录未成功，换一张验证码重试...');
    }
    if (!loggedIn) {
      throw Exception('自动登录失败：验证码多次识别未通过');
    }
  }

  // 从浏览器提取 Cookie 并构建带会话的 dio
  Future<HnuClient> _buildClient(
      void Function(String) log, OcrService ocr) async {
    final ck = await _cdp!.send('Storage.getCookies', {});
    final cookies = (ck['cookies'] as List)
        .whereType<Map>()
        .where((c) => '${c['domain']}'.contains('hainanu.edu.cn'))
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
    final ua = '${await _evalSafe('navigator.userAgent')}';
    log('🍪 已提取 ${cookies.length} 条会话 Cookie');

    final client = HnuClient(ocr)..debugLog = log;
    client.injectCookies(cookies);
    if (ua.isNotEmpty) client.setUserAgent(ua);
    // 选课相关请求走浏览器会话内 fetch（自动携带全部 Cookie/会话状态）
    client.browserFetch = _browserFetch;
    return client;
  }

  // 在 Edge 页面上下文内执行 fetch
  // 强制相邻两次请求间隔 ≥1.2s
  Future<String> _browserFetch(
      String method, String url, Map<String, String> form,
      {String? referrer}) async {
    var body = await _browserFetchOnce(method, url, form, referrer);
    if (_isKickedBody(body)) {
      _log('⚠ 检测到会话失效（请先登录/高频保护），自动重新登录并重试...');
      await _recoverSession();
      body = await _browserFetchOnce(method, url, form, referrer);
      if (_isKickedBody(body)) {
        throw Exception('重新登录后仍被拒绝（${_kickReason(body)}），请手动检查账号状态');
      }
    }
    return body;
  }

  bool _isKickedBody(String body) =>
      body.contains('请先登录系统') ||
      body.contains('高频访问') ||
      body.contains('注销登录') ||
      body.contains('authserver') ||
      body.contains('系统功能暂未开放');

  String _kickReason(String body) {
    for (final m in const ['请先登录系统', '高频访问', '系统功能暂未开放']) {
      if (body.contains(m)) return m;
    }
    return '会话失效';
  }

  // 会话失效恢复：回登录页 → 自动登录 → 重新进入公选课轮次
  Future<void> _recoverSession() async {
    await _evalSafe('location.href = "/jsxsd/"');
    await Future.delayed(const Duration(milliseconds: 2000));
    await _ensureLoggedIn(_lastAccount, _lastPassword, _log,
        _ocr ?? OcrService.instance);
    await _enterSelectionInBrowser(_log, force: true);
  }

  Future<String> _browserFetchOnce(
      String method, String url, Map<String, String> form,
      String? referrer) async {
    const minGap = Duration(milliseconds: 1200);
    final gap = DateTime.now().difference(_lastReqAt);
    if (gap < minGap) {
      await Future.delayed(minGap - gap);
    }
    _lastReqAt = DateTime.now();
    final formJson = jsonEncode(form);
    final js = '''
new Promise((resolve, reject) => {
  const getWin = () => {
    try {
      const sb = document.querySelector('iframe[src*="selectBottom"]');
      if (sb && sb.contentWindow) {
        const w2 = sb.contentWindow;
        const st = w2.frames["selectTable"] ||
          (w2.document && w2.document.querySelector('iframe[src*="getGgxxkxk"]'));
        if (st && st.contentWindow) return st.contentWindow;
      }
    } catch (e) {}
    return window;
  };
  const w = getWin();
  w.fetch(${jsonEncode(url)}, {
    method: ${jsonEncode(method)},
    headers: {
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      "X-Requested-With": "XMLHttpRequest"
    },
    referrer: ${referrer == null ? 'undefined' : jsonEncode(referrer)},
    body: ${jsonEncode(method)} === "GET" ? undefined : new URLSearchParams($formJson).toString(),
    credentials: "same-origin"
  }).then(r => r.text().then(t => resolve(JSON.stringify({
      status: r.status,
      finalUrl: r.url,
      body: t
    })))).catch(e => reject("fetch error: " + e));
})''';
    final wrapped = '${await _evalSafe(js)}';
    String body = wrapped;
    String statusInfo = '';
    try {
      final info = jsonDecode(wrapped);
      body = '${info['body']}';
      statusInfo = 'HTTP ${info['status']} → ${info['finalUrl']}';
    } catch (_) {}
    // ignore: avoid_print
    print('=== [browser fetch] $method $url\n'
        // ignore: avoid_print
        'form: $formJson\n'
        // ignore: avoid_print
        '$statusInfo\n'
        // ignore: avoid_print
        'response(${body.length} chars): $body');
    return body;
  }

  // 检测浏览器是否已停在公选课选课页面（selectTable 框架已加载 getGgxxkxk）
  static const String _ggLoadedJs = '''
JSON.stringify((() => {
  try {
    const sb = document.querySelector('iframe[src*="selectBottom"]');
    if (!sb || !sb.contentDocument) return {ggLoaded: false};
    return {ggLoaded: !!sb.contentDocument.querySelector('iframe[src*="getGgxxkxk"]')};
  } catch (e) { return {ggLoaded: false}; }
})())''';

  /// 检测选课框架页是否已出现（含 selectBottom 底部 iframe）
  static const String _frameStateJs = '''
JSON.stringify({found: !!document.querySelector('iframe[src*="selectBottom"]')})''';

  /// 在 selectBottom 框架内执行 jpbxxk('ggksfkf')（该函数定义于 selectBottom）
  static const String _runJpbxxkJs = '''
(() => {
  const f = document.querySelector('iframe[src*="selectBottom"]');
  if (f && f.contentWindow && typeof f.contentWindow.jpbxxk === 'function') {
    f.contentWindow.jpbxxk('ggksfkf');
    return 'ok';
  }
  if (typeof jpbxxk === 'function') { jpbxxk('ggksfkf'); return 'ok-top'; }
  return 'none';
})()''';

  // 查找选课底部 iframe 的 URL（selectBottom?jx0502zbid=...）作为 Referer
  Future<String?> _findSelectBottomUrl() async {
    try {
      final path = '${await _evalSafe(_findSelectBottomJs)}';
      if (path.isNotEmpty) {
        return 'https://jxgl.hainanu.edu.cn$path';
      }
    } catch (_) {}
    return null;
  }

  static const String _findSelectBottomJs = '''
(() => {
  const tryUrl = (u) => {
    const m = /[?&]jx0502zbid=([^&]+)/.exec(u || "");
    return m ? ("/jsxsd/xsxk/selectBottom?jx0502zbid=" + m[1]) : null;
  };
  let u = tryUrl(location.href);
  if (u) return u;
  const f = Array.from(document.querySelectorAll("iframe")).find(f => (f.src || "").includes("selectBottom"));
  if (f) { u = tryUrl(f.src); if (u) return u; }
  return "";
})()''';

  // 执行 JS；连接失效时重连对应页面后重试一次
  Future<dynamic> _evalSafe(String js) async {
    try {
      return await _cdp!.eval(js);
    } catch (_) {
      // 页面跳转可能断开连接，重连后重试
      await Future.delayed(const Duration(milliseconds: 600));
      final list = await _httpGetJson('http://127.0.0.1:$_port/json/list');
      final pages =
          (list as List).whereType<Map>().where((t) => t['type'] == 'page');
      if (pages.isEmpty) rethrow;
      final t = pages.firstWhere(
        (t) => '${t['url']}'.contains('jxgl.hainanu.edu.cn'),
        orElse: () => pages.first,
      );
      _cdp = await _Cdp.connect('${t['webSocketDebuggerUrl']}');
      return _cdp!.eval(js);
    }
  }

  void _disposeBrowser() {
    _process?.kill();
    _cdp?.close();
    _process = null;
    _cdp = null;
    _port = null;
  }

  static const String _rectJs = '''
new Promise(res => {
  const e = document.querySelector("#SafeCodeImg");
  e.scrollIntoView({block: "center"});
  setTimeout(() => {
    const r = e.getBoundingClientRect();
    res(JSON.stringify({x: r.x, y: r.y, w: r.width, h: r.height, dpr: window.devicePixelRatio || 1}));
  }, 300);
})''';

  /// 页面状态检测：当前 URL / 是否有轮次列表 / 是否有「进入选课」按钮
  static const String _pageStateJs = '''
JSON.stringify({
  url: location.href,
  hasRounds: !!document.querySelector("#dataList td a"),
  hasEnter: Array.from(document.querySelectorAll("span")).some(s => s.textContent.includes("进入选课"))
})''';

  /// 点击页面中的「进入选课」按钮
  static const String _clickEnterJs = '''
(() => {
  const span = Array.from(document.querySelectorAll("span")).find(s => s.textContent.includes("进入选课"));
  if (span) { span.click(); return "ok"; }
  const btn = Array.from(document.querySelectorAll("a, button")).find(e => e.textContent.includes("进入选课"));
  if (btn) { btn.click(); return "ok"; }
  return "none";
})()''';
}

/// 极简 CDP（Chrome DevTools Protocol）客户端
class _Cdp {
  WebSocket? _ws;
  final Map<int, Completer<dynamic>> _pending = {};
  var _nextId = 1;
  final String wsUrl;

  _Cdp._(this.wsUrl);

  static Future<_Cdp> connect(String wsUrl) async {
    final c = _Cdp._(wsUrl);
    await c._connect();
    return c;
  }

  Future<void> _connect() async {
    _pending.clear();
    final ws = await WebSocket.connect(wsUrl);
    _ws = ws;
    ws.listen((data) {
      if (data is! String) return;
      final msg = jsonDecode(data);
      final id = msg['id'];
      if (id != null && _pending.containsKey(id)) {
        _pending.remove(id)!.complete(msg);
      }
    }, onError: (Object e) {
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError(e);
      }
      _pending.clear();
    }, onDone: () {
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError('连接已断开');
      }
      _pending.clear();
    });
  }

  Future<Map<String, dynamic>> send(String method,
      [Map<String, dynamic>? params]) async {
    if (_ws == null || _ws!.readyState != WebSocket.open) {
      await _connect();
    }
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    _ws!.add(jsonEncode({
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    }));
    final resp = await completer.future.timeout(const Duration(seconds: 20));
    if (resp is Map && resp['error'] != null) {
      throw Exception('CDP 调用失败: ${resp['error']}');
    }
    return (resp['result'] as Map?)?.cast<String, dynamic>() ?? {};
  }

  // 执行 JS 并返回值（支持 awaitPromise）
  Future<dynamic> eval(String js) async {
    final r = await send('Runtime.evaluate', {
      'expression': js,
      'returnByValue': true,
      'awaitPromise': true,
    });
    return r['result']?['value'];
  }

  void close() {
    _ws?.close();
  }
}
