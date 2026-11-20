import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:html/parser.dart' as html_parser;

import '../models/course.dart';
import '../models/gg_course.dart';
import 'ocr_service.dart';

class HnuClient {
  static const String baseUrl = 'https://jxgl.hainanu.edu.cn';

  static const String loginPageUrl = '$baseUrl/jsxsd/';

  late final Dio dio;
  final OcrService ocr;
  bool loggedIn = false;

  /// 会话 Cookie 容器（由浏览器登录注入）
  final CookieJar cookieJar = CookieJar();

  /// 调试日志回调（ UI 层注入）
  void Function(String msg)? debugLog;

  /// 浏览器请求通道（Edge CDP）：设置后选课相关请求经浏览器会话内
  /// fetch 发出（自动携带完整会话状态），返回响应文本；为空时走 dio。
  /// [referrer] 用于模拟真实页面的 Referer
  Future<String> Function(String method, String url, Map<String, String> form,
      {String? referrer})? browserFetch;

  /// 服务端会话失效得重新登录
  static bool isKickedResponse(String body) => body.contains('请先登录系统');

  /// 标记会话失效并抛出明确异常
  Never _kicked() {
    loggedIn = false;
    throw Exception('⚠ 会话已失效（未登录/高频保护）——自动重新登录...');
  }

  HnuClient(this.ocr) {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      followRedirects: true,
      maxRedirects: 5,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36 Edg/132.0.0.0',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      },
      validateStatus: (status) => status != null && status < 500,
    ));
    dio.interceptors.add(CookieManager(cookieJar));
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        request: true,
        requestHeader: false,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
      ));
    }
  }

  /// 注入从Edge CDP提取的会话 Cookie
  void injectCookies(List<Map<String, dynamic>> cookies) {
    final uri = Uri.parse(baseUrl);
    final list = cookies
        .where((c) => '${c['name']}'.isNotEmpty)
        .map((c) {
          final ck = Cookie('${c['name']}', '${c['value'] ?? ''}');
          final domain = '${c['domain'] ?? ''}';
          if (domain.isNotEmpty) ck.domain = domain;
          final path = '${c['path'] ?? ''}';
          if (path.isNotEmpty) ck.path = path;
          ck.secure = uri.scheme == 'https';
          return ck;
        })
        .toList();
    cookieJar.saveFromResponse(uri, list);
  }

  /// 与浏览器保持一致 UA（部分服务端会校验）
  void setUserAgent(String ua) {
    dio.options.headers['User-Agent'] = ua;
  }

  /// 访问登录页，返回页面 HTML（同时让服务器种下会话 Cookie）
  Future<String> getLoginPage() async {
    final r = await dio.get('/jsxsd/');
    return r.data.toString();
  }

  /// 下载验证码图片并本地 OCR 识别
  Future<String> resolveCaptcha() async {
    final r = await dio.get<List<int>>(
      '/jsxsd/verifyCode.servlet',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(r.data ?? []);
    final code = await ocr.classification(bytes);
    return code;
  }

  /// 登录。验证码识别错误时自动换一张重试（最多 3 次），
  /// 明确的凭据错误（密码错误/账号不存在）不重试直接抛出
  Future<void> login(String account, String password) async {
    loggedIn = false;
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (attempt > 1) {
        debugLog?.call('↻ 换一张验证码重试（第 $attempt/3 次）');
      }
      try {
        await _loginOnce(account, password);
        loggedIn = true;
        return;
      } catch (e) {
        lastError = e;
        final msg = e.toString();
        if (msg.contains('密码错误') || msg.contains('账号不存在')) rethrow;
      }
    }
    throw lastError!;
  }

  /// 单次登录尝试。失败抛出带原因的异常
  ///
  /// 1. GET /jsxsd/ 建立会话并解析表单参数
  /// 2. GET 验证码图片 → OCR
  /// 3. POST /jsxsd/Logon.do?method=logon&flag=sess → 返回 "scode#sxh" 种子
  /// 4. 按 JS 算法把 账号%%%密码 与种子交叉拼接成 encoded
  /// 5. POST 表单 action（/jsxsd/xk/LoginToXkLdap）提交
  ///    loginMethod/userAccount/userPassword/RANDOMCODE/encoded
  Future<void> _loginOnce(String account, String password) async {
    loggedIn = false;

    // 访问登录页建立会话，并解析验证码地址
    final pageHtml = await getLoginPage();
    final doc = html_parser.parse(pageHtml);
    String captchaPath = '/jsxsd/verifycode.servlet';
    final img = doc.querySelector('#SafeCodeImg');
    final imgSrc = img?.attributes['src'];
    if (imgSrc != null && imgSrc.isNotEmpty) {
      captchaPath = _pathOf(imgSrc);
    }

    // 下载并识别验证码
    final r = await dio.get<List<int>>(
      captchaPath,
      options: Options(responseType: ResponseType.bytes),
    );
    final captchaBytes = Uint8List.fromList(r.data ?? []);
    final code = await ocr.classification(captchaBytes);
    debugLog?.call('验证码识别结果: "$code"');

    final encoded =
        "${base64.encode(utf8.encode(account))}%%%${base64.encode(utf8.encode(password))}";
    debugLog?.call('encoded 已生成（长度 ${encoded.length}）   $encoded');

    final loginR = await dio.post(
      '$baseUrl/jsxsd/xk/LoginToXkl.dap',
      data: {
        'loginMethod': 'LoginToXkl.dap',
        'userAccount': account,
        'userPassword': "",
        'RANDOMCODE': code,
        'encoded': encoded,
      },
      options: Options(headers: {
        'Referer': loginPageUrl,
      }),
    );

    if ((loginR.statusCode ?? 0) >= 400) {
      throw Exception('登录请求失败 (HTTP ${loginR.statusCode})');
    }

    final check = await dio.get('/jsxsd/xsxk/xklc_list');
    final checkBody = check.data.toString();
    final backToLogin = checkBody.contains('userAccount') &&
        checkBody.contains('RANDOMCODE') &&
        checkBody.contains('loginForm');
    if (backToLogin) {
      debugLog?.call(
          'xklc_list 疑似登录页，片段: ${checkBody.length > 150 ? checkBody.substring(0, 150) : checkBody}');
      final tip = RegExp(
              '(alert\\()?["\']([^"\']*(?:错误|失败|不正确|不存在)[^"\']*)')
          .firstMatch(checkBody)
          ?.group(2);
      throw Exception(
          '登录失败：${tip ?? '账号、密码或验证码错误（会话未建立）'}');
    }
    loggedIn = true;
  }

  /// 进入选课流程：选课轮次列表 -> 选课入口 -> 课程列表页 HTML
  Future<String> fetchCoursePageHtml() async {
    // 1选课轮次列表
    final r1 = await dio.get('/jsxsd/xsxk/xklc_list');
    final r1Body = r1.data.toString();

    // 找到进入选课
    String? roundUrl = _findEnterLink(r1Body);
    if (roundUrl == null) {
      throw Exception('当前没有开放中的选课轮次（未找到"进入选课"入口）');
    }

    // 进入选课入口页（xsrkxz）
    final r2 = await dio.get(_pathOf(roundUrl));
    final r2Body = r2.data.toString();
    String? listUrl = _firstDataListLink(r2Body);
    if (listUrl == null) {
      if (r2Body.contains('<tbody')) {
        return r2Body;
      }
      throw Exception('未能定位课程列表链接');
    }

    // 课程列表页
    final r3 = await dio.get(_pathOf(listUrl));
    return r3.data.toString();
  }

  /// 从课程列表页 HTML 解析课程
  static List<Course> parseCourses(String html) {
    final doc = html_parser.parse(html);
    final rows = doc.querySelectorAll('tbody tr');
    final courses = <Course>[];
    final idRegex = RegExp(r"x[st]tkOper\('(\d+)'\)");

    for (final row in rows) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 10) continue;

      final courseNum = cells[0].text.trim();
      final courseName = cells[1].text.trim();
      final courseTeacher = cells[5].text.trim();

      String courseId = '';
      for (final a in cells.last.querySelectorAll('a')) {
        final href = a.attributes['href'] ?? '';
        final m = idRegex.firstMatch(href);
        if (m != null) {
          courseId = m.group(1)!;
          break;
        }
      }

      courses.add(Course(
        courseName: courseName,
        courseNum: courseNum,
        courseTeacher: courseTeacher,
        courseId: courseId,
      ));
    }
    return courses;
  }

  /// 发送选课请求，返回服务器消息；message 含"成功"视为成功
  Future<(bool, String)> sendPost(Course c) async {
    try {
      String body;
      if (browserFetch != null) {
        body = await browserFetch!(
          'GET',
          '$baseUrl/jsxsd/xsxkkc/bxxkOper'
          '?kcid='
          '&cfbs=null'
          '&jx0404id=${Uri.encodeComponent(c.courseId)}'
          '&xkzy=&trjf=',
          {},
          referrer: '$baseUrl/jsxsd/xsxkkc/getGgxxkxk',
        );
      } else {
        final r = await dio.post(
          '/jsxsd/xsxkkc/bxxkOper',
          queryParameters: {
            'kcid': '',
            'cfbs': 'null',
            'jx0404id': c.courseId,
            'xkzy': '',
            'trjf': '',
          },
          options: Options(headers: {
            'Referer': '$baseUrl/jsxsd/xsxk/xsxk_courseSelect',
            'X-Requested-With': 'XMLHttpRequest',
            'Content-Type': 'application/x-www-form-urlencoded',
          }),
        );
        body = r.data.toString();
      }
      if (isKickedResponse(body)) _kicked();
      String msg = body;
      try {
        final json = jsonDecode(body);
        if (json is Map && json['message'] != null) msg = json['message'];
        if (json is Map && json['jg'] != null) msg = json['jg'];
      } catch (_) {}
      final ok = msg.contains('成功');
      return (ok, msg);
    } catch (e) {
      return (false, e.toString());
    }
  }

  // ==================== 公选课 ====================

  /// 查询公选课列表（单页，DataTables 协议 POST）。
  /// 返回 (课程列表, sEcho 页码, 总记录数)。
  /// [page] 从 1 开始；请求负载：sEcho=页码、iDisplayStart=(页码-1)*10
  /// [sfym] 过滤已满课程 [sfct] 过滤冲突课程 [sfxx] 过滤限选课程
  Future<(List<GgCourse>, int, int)> fetchGgxxkPage({
    String kcxx = '',
    String skls = '',
    String skxq = '',
    String skjc = '',
    String endJc = '',
    int page = 1,
    String sfym = 'false',
    String sfct = 'true',
    String sfxx = 'true',
  }) async {
    final query = {
      'kcxx': kcxx, // 课程(编号/名称)
      'skls': skls, // 上课教师
      'skxq': skxq, // 星期
      'skjc': skjc, // 开始节次
      'endJc': endJc, // 结束节次
      // szjylb 必须为空串：传 "false" 会被服务端当作筛选值导致 aaData 为空
      'sfym': sfym,
      'sfct': sfct,
      'szjylb': '',
      'sfxx': sfxx,
      'skfs': '',
      'kcxz': '',
    };
    final form = {
      'sEcho': '$page',
      'iColumns': '13',
      'sColumns': '',
      'iDisplayStart': '${(page - 1) * 10}',
      'iDisplayLength': '10',
      'mDataProp_0': 'kch',
      'mDataProp_1': 'kcmc',
      'mDataProp_2': 'xf',
      'mDataProp_3': 'skls',
      'mDataProp_4': 'sksj',
      'mDataProp_5': 'kkdd',
      'mDataProp_6': 'xqmc',
      'mDataProp_7': 'xkrs',
      'mDataProp_8': 'syrs',
      'mDataProp_9': 'skfsmc',
      'mDataProp_10': 'ctsm',
      'mDataProp_11': 'szkcflmc',
      'mDataProp_12': 'czOper',
    };
    // 手动拼接查询串：保留空参数的 "="（Uri.replace 会把空值参数输出成不带 = 的形式）
    final qs = query.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final uri = '$baseUrl/jsxsd/xsxkkc/xsxkGgxxkxk?$qs';

    String body;
    if (browserFetch != null) {
      // 走浏览器会话
      body = await browserFetch!('POST', uri.toString(), form,
          referrer: '$baseUrl/jsxsd/xsxkkc/getGgxxkxk');
    } else {
      final r = await dio.post(
        '/jsxsd/xsxkkc/xsxkGgxxkxk',
        queryParameters: query,
        data: form,
        options: Options(headers: {
          'Referer': '$baseUrl/jsxsd/xsxkkc/getGgxxk',
          'X-Requested-With': 'XMLHttpRequest',
        }),
      );
      body = r.data.toString();
    }
    if (isKickedResponse(body)) _kicked();
    final dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      final snippet = body.length > 300 ? body.substring(0, 300) : body;
      throw Exception(
          '公选课查询返回非 JSON（可能未登录或选课轮次未开放）响应片段: $snippet');
    }
    if (json is! Map) throw Exception('公选课查询返回格式异常');
    final list = (json['aaData'] as List?) ?? const [];
    final courses = list
        .whereType<Map>()
        .where((m) => m['kcmc'] != null)
        .map((m) => GgCourse.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final sEcho = int.tryParse('${json['sEcho'] ?? 1}') ?? 1;
    final total = int.tryParse('${json['iTotalDisplayRecords'] ?? 0}') ?? 0;
    return (courses, sEcho, total);
  }

  /// 抓取所有分页（确定性分页：iDisplayStart 按 10 条/页推进）
  Future<List<GgCourse>> fetchAllGgxxk({
    String kcxx = '',
    String skls = '',
    String skxq = '',
    String skjc = '',
    String endJc = '',
    String sfym = 'false',
    String sfct = 'true',
    String sfxx = 'true',
    void Function(int loaded, int total, int page)? onProgress,
  }) async {
    final all = <String, GgCourse>{};
    var total = 0;
    for (var page = 1; page <= 50; page++) {
      final (courses, sEcho, t) = await fetchGgxxkPage(
        kcxx: kcxx,
        skls: skls,
        skxq: skxq,
        skjc: skjc,
        endJc: endJc,
        page: page,
        sfym: sfym,
        sfct: sfct,
        sfxx: sfxx,
      );
      total = t;
      if (courses.isEmpty) break;
      for (final c in courses) {
        all[c.jx0404id] = c;
      }
      onProgress?.call(all.length, total, page);
      if (all.length >= total && total > 0) break;
    }
    return all.values.toList();
  }

  /// 公选课选课请求，返回 (是否成功, 消息)
  Future<(bool, String)> ggxxkOper(GgCourse c) async {
    try {
      String body;
      if (browserFetch != null) {
        body = await browserFetch!(
          'GET',
          '$baseUrl/jsxsd/xsxkkc/ggxxkxkOper'
          '?kcid=${Uri.encodeComponent(c.jx02id)}'
          '&cfbs=null'
          '&jx0404id=${Uri.encodeComponent(c.jx0404id)}'
          '&xkzy=&trjf=',
          {},
          referrer: '$baseUrl/jsxsd/xsxkkc/getGgxxkxk',
        );
      } else {
        final r = await dio.get(
          '/jsxsd/xsxkkc/ggxxkxkOper',
          queryParameters: {
            'kcid': c.jx02id,
            'cfbs': 'null',
            'jx0404id': c.jx0404id,
            'xkzy': '',
            'trjf': '',
          },
          options: Options(headers: {
            'Referer': '$baseUrl/jsxsd/xsxk/xsxk_courseSelect',
            'X-Requested-With': 'XMLHttpRequest',
          }),
        );
        body = r.data.toString();
      }
      if (isKickedResponse(body)) _kicked();
      String msg = body;
      try {
        final json = jsonDecode(body);
        if (json is Map && json['message'] != null) msg = json['message'];
        if (json is Map && json['jg'] != null) msg = json['jg'];
      } catch (_) {}
      if (msg.length > 120) msg = msg.substring(0, 120);
      final ok = msg.contains('成功');
      return (ok, msg);
    } catch (e) {
      return (false, e.toString());
    }
  }

  String _pathOf(String url) {
    if (url.startsWith('http')) {
      return url.replaceFirst(baseUrl, '');
    }
    return url;
  }

  /// 在 xklc_list 页面中找到"进入选课"对应的链接
  String? _findEnterLink(String html) {
    final doc = html_parser.parse(html);
    for (final a in doc.querySelectorAll('a')) {
      final text = a.text.trim();
      if (text.contains('进入选课')) {
        final href = a.attributes['href'];
        if (href != null && href.isNotEmpty && href != '#') return href;
        // 链接可能包在 span 外层/内层，向上或向下找
        final parent = a.parent;
        if (parent != null) {
          final ph = parent.attributes['href'];
          if (ph != null && ph.isNotEmpty && ph != '#') return ph;
        }
      }
    }
    for (final a in doc.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (href.contains('xsxk') && !href.contains('xklc_list')) return href;
    }
    return null;
  }

  /// 在选课入口页找 #dataList 中的第一个课程列表链接
  String? _firstDataListLink(String html) {
    final doc = html_parser.parse(html);
    final dataList = doc.querySelector('#dataList');
    if (dataList == null) return null;
    for (final a in dataList.querySelectorAll('td a')) {
      final href = a.attributes['href'];
      if (href != null && href.isNotEmpty && href != '#') return href;
    }
    return null;
  }
}
