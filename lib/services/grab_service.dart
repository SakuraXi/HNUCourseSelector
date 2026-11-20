import 'dart:async';
import 'dart:math';

import '../models/course.dart';
import '../models/gg_course.dart';
import 'edge_login_service.dart';
import 'hnu_client.dart';
import 'ocr_service.dart';

class GrabService {
  GrabService._();
  static final GrabService instance = GrabService._();

  HnuClient? client;
  bool _stopFlag = false;
  bool _running = false;
  bool get isRunning => _running;

  final StreamController<String> _logCtrl =
      StreamController<String>.broadcast();
  Stream<String> get logs => _logCtrl.stream;

  void log(String msg) {
    final now = DateTime.now().toIso8601String().substring(11, 19);
    _logCtrl.add('[$now] $msg');
  }

  void stop() {
    _stopFlag = true;
    log('⏹ 已请求停止，正在收尾...');
  }

  void _checkContinue() {
    if (_stopFlag) throw _UserInterrupted();
  }

  /// 可中断sleep，每 100ms 检查一次停止信号
  Future<void> interruptibleSleep(Duration d) async {
    final deadline = DateTime.now().add(d);
    while (DateTime.now().isBefore(deadline)) {
      _checkContinue();
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 等待到指定开始时间
  Future<void> waitForStart(String? targetTimeStr) async {
    if (targetTimeStr == null || targetTimeStr.isEmpty) return;
    final target = DateTime.tryParse(targetTimeStr);
    if (target == null) {
      log('⚠ 开始时间格式无效（应为 2026-06-23 12:00:00），已跳过等待');
      return;
    }
    log('⏰ 等待启动时间: $targetTimeStr');
    while (DateTime.now().isBefore(target)) {
      _checkContinue();
      final diff = target.difference(DateTime.now()).inSeconds;
      log('距离开始还有 $diff 秒...');
      await interruptibleSleep(const Duration(milliseconds: 500));
    }
  }

  /// 登录 -> (可选等待) -> 多轮抢课
  Future<void> run({
    required String account,
    required String password,
    required bool enableAutoStart,
    required String startTime,
    required double maxRounds,
    required double delayBase,
    required double roundsDelay,
    required List<Course> courses,
  }) async {
    if (_running) {
      log('⚠ 已有任务在运行中');
      return;
    }
    _running = true;
    _stopFlag = false;
    try {
      client = await EdgeLoginService.instance.loginViaEdge(
        account: account,
        password: password,
        log: log,
        ocr: OcrService.instance,
      );
      log('✅ 登录成功');

      if (enableAutoStart && startTime.isNotEmpty) {
        await waitForStart(startTime);
      }

      final queue = courses.where((c) => c.selected && c.courseId.isNotEmpty).toList();
      if (queue.isEmpty) {
        log('⚠ 没有勾选任何课程');
        return;
      }

      var attemptRound = 1;
      var currentQueue = List<Course>.of(queue);
      final rng = Random();

      while (currentQueue.isNotEmpty && attemptRound <= maxRounds) {
        _checkContinue();
        log('--- 第 $attemptRound 轮选课开始，剩余 ${currentQueue.length} 门 ---');

        final failedList = <Course>[];
        for (final course in currentQueue) {
          _checkContinue();
          final (ok, msg) = await client!.sendPost(course);
          if (ok) {
            log('✅ 【${course.courseName}】选课成功！');
            course.grabbed = true;
          } else {
            log('❌ 【${course.courseName}】失败: $msg');
            failedList.add(course);
          }
          if (course != currentQueue.last || failedList.isNotEmpty) {
            final delayMs =
                (rng.nextDouble() * 0.4 + 0.8) * delayBase * 1000;
            await interruptibleSleep(Duration(milliseconds: delayMs.round()));
          }
        }

        currentQueue = failedList;
        if (currentQueue.isEmpty) {
          log('🎉 恭喜！所有预定课程已处理完毕。');
          break;
        }
        log('第 $attemptRound 轮结束，有 ${currentQueue.length} 门课失败。');
        if (attemptRound < maxRounds) {
          final delayMs = (rng.nextDouble() * 0.4 + 0.8) * roundsDelay * 1000;
          await interruptibleSleep(Duration(milliseconds: delayMs.round()));
        }
        attemptRound++;
      }
    } on _UserInterrupted {
      log('⏹ 用户终止了任务');
    } catch (e) {
      log('‼ 发生错误: $e');
    } finally {
      _running = false;
      log('任务结束。');
    }
  }

  /// 公选课抢课流程：复用已登录客户端（未登录则先登录），多轮 ggxxkxkOper
  Future<void> runGg({
    required String account,
    required String password,
    required double maxRounds,
    required double delayBase,
    required double roundsDelay,
    required List<GgCourse> courses,
  }) async {
    if (_running) {
      log('⚠ 已有任务在运行中');
      return;
    }
    _running = true;
    _stopFlag = false;
    try {
      if (client == null || !client!.loggedIn) {
        client = await EdgeLoginService.instance.loginViaEdge(
          account: account,
          password: password,
          log: log,
          ocr: OcrService.instance,
        );
      } else {
        log('✅ 复用已登录会话');
      }

      final queue =
          courses.where((c) => c.selected && c.selectable).toList();
      if (queue.isEmpty) {
        log('⚠ 没有勾选任何公选课');
        return;
      }

      var attemptRound = 1;
      var currentQueue = List<GgCourse>.of(queue);
      final rng = Random();

      while (currentQueue.isNotEmpty && attemptRound <= maxRounds) {
        _checkContinue();
        // 会话被高频保护注销时自动重新登录
        if (client == null || !client!.loggedIn) {
          log('🔄 会话失效，自动重新登录...');
          client = await EdgeLoginService.instance.loginViaEdge(
            account: account,
            password: password,
            log: log,
            ocr: OcrService.instance,
          );
        }
        log('--- 第 $attemptRound 轮公选抢课开始，剩余 ${currentQueue.length} 门 ---');

        final failedList = <GgCourse>[];
        for (final course in currentQueue) {
          _checkContinue();
          final (ok, msg) = await client!.ggxxkOper(course);
          if (ok) {
            log('✅ 【${course.courseName}】选课成功！');
            course.grabbed = true;
          } else {
            log('❌ 【${course.courseName}】失败: $msg');
            failedList.add(course);
          }
          if (course != currentQueue.last || failedList.isNotEmpty) {
            final delayMs =
                (rng.nextDouble() * 0.4 + 0.8) * delayBase * 1000;
            await interruptibleSleep(Duration(milliseconds: delayMs.round()));
          }
        }

        currentQueue = failedList;
        if (currentQueue.isEmpty) {
          log('🎉 恭喜！所有公选课已处理完毕。');
          break;
        }
        log('第 $attemptRound 轮结束，有 ${currentQueue.length} 门课失败。');
        if (attemptRound < maxRounds) {
          final delayMs = (rng.nextDouble() * 0.4 + 0.8) * roundsDelay * 1000;
          await interruptibleSleep(Duration(milliseconds: delayMs.round()));
        }
        attemptRound++;
      }
    } on _UserInterrupted {
      log('⏹ 用户终止了任务');
    } catch (e) {
      log('‼ 发生错误: $e');
    } finally {
      _running = false;
      log('任务结束。');
    }
  }

  /// 公选课极速抢课：自动查询 → 按授课方式筛选 → 立即逐门尝试选课 → 多轮循环
  Future<void> runGgAuto({
    required String account,
    required String password,
    required String kcxx,
    required String skls,
    required String skxq,
    required String skjc,
    required String endJc,
    required String sfym,
    required String sfct,
    required String sfxx,
    required GgTeachType teachType,
    required double maxRounds,
    required double delayBase,
    required double roundsDelay,
  }) async {
    if (_running) {
      log('⚠ 已有任务在运行中');
      return;
    }
    _running = true;
    _stopFlag = false;
    try {
      if (client == null || !client!.loggedIn) {
        client = await EdgeLoginService.instance.loginViaEdge(
          account: account,
          password: password,
          log: log,
          ocr: OcrService.instance,
        );
      } else {
        log('✅ 复用已登录会话');
      }

      log('⚡ 极速抢课启动：类型「${teachType.label}」'
          '${kcxx.isEmpty ? '' : ' / 课程"$kcxx"'}'
          '${skls.isEmpty ? '' : ' / 教师$skls'}'
          '${skxq.isEmpty ? '' : ' / 周$skxq'}'
          '${skjc.isEmpty ? '' : ' / 第$skjc 节起'}');

      final grabbedIds = <String>{};
      final rng = Random();

      for (var round = 1; round <= maxRounds; round++) {
        _checkContinue();
        // 会话被高频保护注销时自动重新登录
        if (client == null || !client!.loggedIn) {
          log('🔄 会话失效，自动重新登录...');
          client = await EdgeLoginService.instance.loginViaEdge(
            account: account,
            password: password,
            log: log,
            ocr: OcrService.instance,
          );
        }
        log('--- 第 $round 轮查询+抢课 ---');

        List<GgCourse> courses;
        try {
          courses = await client!.fetchAllGgxxk(
            kcxx: kcxx,
            skls: skls,
            skxq: skxq,
            skjc: skjc,
            endJc: endJc,
            sfym: sfym,
            sfct: sfct,
            sfxx: sfxx,
            onProgress: (loaded, total, page) {
              log('  📄 第 $page 页，已加载 $loaded/$total 门');
            },
          );
        } catch (e) {
          log('‼ 查询失败: $e');
          await interruptibleSleep(
              Duration(milliseconds: (roundsDelay * 1000).round()));
          continue;
        }

        final targets = courses
            .where((c) =>
                c.selectable &&
                !grabbedIds.contains(c.jx0404id) &&
                teachType.matches(c))
            .toList();

        if (targets.isEmpty) {
          log('⚠ 本轮无「${teachType.label}」可抢课程（共 ${courses.length} 门）');
          if (round < maxRounds) {
            await interruptibleSleep(
                Duration(milliseconds: (roundsDelay * 1000).round()));
          }
          continue;
        }

        log('🎯 本轮命中 ${targets.length} 门「${teachType.label}」课程');
        for (final course in targets) {
          _checkContinue();
          final remain =
              course.capacity > 0 ? course.capacity - course.enrolled : null;
          final remainStr = remain == null ? '' : ' (余$remain)';
          final (ok, msg) = await client!.ggxxkOper(course);
          if (ok) {
            grabbedIds.add(course.jx0404id);
            log('🎉 【${course.courseName}】${course.teacher} 抢课成功！$remainStr');
          } else {
            log('❌ 【${course.courseName}】$remainStr 失败: $msg');
          }
          if (course != targets.last) {
            final delayMs =
                (rng.nextDouble() * 0.4 + 0.8) * delayBase * 1000;
            await interruptibleSleep(Duration(milliseconds: delayMs.round()));
          }
        }

        if (grabbedIds.isNotEmpty) {
          log('🎉 已累计抢到 ${grabbedIds.length} 门');
        }
        if (round < maxRounds) {
          final delayMs = (rng.nextDouble() * 0.4 + 0.8) * roundsDelay * 1000;
          await interruptibleSleep(Duration(milliseconds: delayMs.round()));
        }
      }
      log('极速抢课结束，共抢到 ${grabbedIds.length} 门。');
    } on _UserInterrupted {
      log('⏹ 用户终止了任务');
    } catch (e) {
      log('‼ 发生错误: $e');
    } finally {
      _running = false;
      log('任务结束。');
    }
  }
}

class _UserInterrupted implements Exception {}
