import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

/// 本地验证码 OCR，使用 ddddocr 的 common_old.onnx 模型，
/// 预处理与 CTC 解码逻辑与 ddddocr 1.6.1 保持一致：
///   1. 灰度化，等比缩放到高度 64
///   2. 像素值 / 255.0，输入形状 [1, 1, 64, W]
///   3. 输出 [seq, 1, C]，argmax -> 去连续重复 -> 跳过 blank(index 0) -> 查字符表
class OcrService {
  static final OcrService instance = OcrService._();
  OcrService._();

  OrtSession? _session;
  List<String> _charset = [];
  bool _ready = false;
  String? _initError;

  static const int _targetHeight = 64;

  /// 初始化，失败时有[initError]
  bool get isReady => _ready;
  String? get initError => _initError;

  Future<void> ensureReady() async {
    if (_ready) return;

    try {
      OrtEnv.instance.init();
      final sessionOptions = OrtSessionOptions();

      final modelData = await rootBundle.load('assets/models/common_old.onnx');
      final bytes = modelData.buffer.asUint8List();
      _session = OrtSession.fromBuffer(bytes, sessionOptions);

      final charsetRaw =
          await rootBundle.loadString('assets/models/charset_old.json');
      final list = jsonDecode(charsetRaw) as List<dynamic>;
      _charset = list.map((e) => e.toString()).toList();

      _initError = null;
      _ready = true;
    } catch (e) {
      // 资产缺失等原因导致的初始化失败：不抛出未处理异常，
      // 记录原因并允许下次调用重试（如重新构建后资产恢复）
      _ready = false;
      _session = null;
      _initError = 'OCR 模型初始化失败: $e';
      assert(() {
        debugPrint(_initError);
        return true;
      }());
    }
  }

  /// 识别验证码 PNG/JPEG 字节流
  Future<String> classification(Uint8List imageBytes) async {
    await ensureReady();
    final session = _session;
    if (session == null) return '';

    // ---- 预处理 ----
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return '';

    final srcW = decoded.width;
    final srcH = decoded.height;
    if (srcH <= 0 || srcW <= 0) return '';

    final targetW = max(1, (srcW * (_targetHeight / srcH)).round());
    final resized = img.copyResize(
      decoded,
      width: targetW,
      height: _targetHeight,
    );

    // 灰度化 + 归一化 (/255)，形状 [1, 1, 64, W]
    final w = resized.width;
    final h = resized.height;
    final input = Float32List(w * h);
    var idx = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = resized.getPixel(x, y);
        final gray = img.getLuminance(p);
        input[idx++] = gray / 255.0;
      }
    }

    final inputOrt = OrtValueTensor.createTensorWithDataList(
      input,
      [1, 1, h, w],
    );
    final runOptions = OrtRunOptions();

    List<List<double>> probs;
    try {
      final inputName = 'input1'; // ddddocr 默认模型的输入名
      final outputs = await session.runAsync(runOptions, {inputName: inputOrt});
      final list = outputs ?? <OrtValue?>[];
      final first = list.isNotEmpty ? list.first : null;
      if (first == null) return '';
      probs = _extractProbabilities(first.value);
      first.release();
    } finally {
      inputOrt.release();
      runOptions.release();
    }

    // CTC 解码
    return _ctcDecode(probs);
  }

  /// 从输出张量提取每个时间步的概率分布，兼容
  /// [seq, 1, C] 与 [1, seq, C] 两种布局
  List<List<double>> _extractProbabilities(dynamic value) {
    // value: List<dynamic> 嵌套结构
    final outer = value as List;
    if (outer.isEmpty) return [];

    List rowAt(List seqList, int i) => seqList[i] as List;

    if (outer.length == 1 && outer.first is List && (outer.first as List).isNotEmpty && (outer.first as List).first is List) {
      // [1, seq, C]
      final seqList = outer.first as List;
      return List.generate(seqList.length, (i) {
        final row = rowAt(seqList, i);
        return row.map((e) => (e as num).toDouble()).toList();
      });
    }

    // [seq, 1, C]
    if (outer.first is List) {
      final result = <List<double>>[];
      for (var i = 0; i < outer.length; i++) {
        final mid = rowAt(outer, i);
        if (mid.isEmpty) continue;
        final row = (mid.length == 1 ? mid.first : mid) as List;
        result.add(row.map((e) => (e as num).toDouble()).toList());
      }
      return result;
    }

    // 一维，视为单时间步
    return [outer.map((e) => (e as num).toDouble()).toList()];
  }

  String _ctcDecode(List<List<double>> probs) {
    final buf = StringBuffer();
    int prev = -1;
    for (final step in probs) {
      if (step.isEmpty) continue;
      var best = 0;
      var bestVal = step[0];
      for (var i = 1; i < step.length; i++) {
        if (step[i] > bestVal) {
          bestVal = step[i];
          best = i;
        }
      }
      if (best != prev && best != 0) {
        if (best < _charset.length) buf.write(_charset[best]);
      }
      prev = best;
    }
    return buf.toString().trim();
  }

  void dispose() {
    _session = null;
    _ready = false;
  }
}
