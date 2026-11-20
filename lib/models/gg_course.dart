// 公选课
enum GgTeachType { any, offline, online }

extension GgTeachTypeX on GgTeachType {
  String get label => switch (this) {
        GgTeachType.any => '任意',
        GgTeachType.offline => '线下授课',
        GgTeachType.online => '网上教学',
      };

  static GgTeachType fromId(String v) => switch (v) {
        'offline' => GgTeachType.offline,
        'online' => GgTeachType.online,
        _ => GgTeachType.any,
      };

  bool matches(GgCourse c) {
    final isOnline = c.place.contains('网络教学');
    switch (this) {
      case GgTeachType.any:
        return true;
      case GgTeachType.offline:
        return !isOnline;
      case GgTeachType.online:
        return isOnline;
    }
  }
}

/// 公选课（通识选修）课程模型 — 对应 xsxkGgxxkxk 接口返回的 aaData 条目
class GgCourse {
  final String courseName; // kcmc 课程名
  final String courseNum; // kch 课程号
  final String teacher; // skls 上课教师
  final String time; // sksj 上课时间（含 <br>）
  final String category; // kcxzmc 课程性质（如 科学精神与职业素养类通识课）
  final String subCategory; // szkcflmc 课程分类
  final double credit; // xf 学分
  final int capacity; // pkrs 容量
  final int enrolled; // xkrs 已选人数
  final String unit; // dwmc 开课单位
  final String jx0404id; // 教学班/课堂 id（选课参数）
  final String jx02id; // 课程 id（选课 URL 中的 kcid）
  final String xkzt; // 选课状态
  final String examType; // khfs 考核方式
  final String teachMode; // skfsmc 授课方式（面授讲课/网络教学等）
  final String place; // skdd 上课地点（含"网络教学"即为网上课程）

  bool selected;
  bool grabbed;

  GgCourse({
    required this.courseName,
    required this.courseNum,
    required this.teacher,
    required this.time,
    required this.category,
    required this.subCategory,
    required this.credit,
    required this.capacity,
    required this.enrolled,
    required this.unit,
    required this.jx0404id,
    required this.jx02id,
    required this.xkzt,
    required this.examType,
    required this.teachMode,
    required this.place,
    this.selected = false,
    this.grabbed = false,
  });

  factory GgCourse.fromJson(Map<String, dynamic> j) {
    return GgCourse(
      courseName: (j['kcmc'] ?? '') as String,
      courseNum: (j['kch'] ?? '') as String,
      teacher: (j['skls'] ?? '') as String,
      time: (j['sksj'] ?? '') as String,
      category: (j['kcxzmc'] ?? '') as String,
      subCategory: (j['szkcflmc'] ?? '') as String,
      credit: double.tryParse('${j['xf'] ?? 0}') ?? 0,
      capacity: int.tryParse('${j['pkrs'] ?? 0}') ?? 0,
      enrolled: int.tryParse('${j['xkrs'] ?? 0}') ?? 0,
      unit: (j['dwmc'] ?? '') as String,
      jx0404id: (j['jx0404id'] ?? '') as String,
      jx02id: (j['jx02id'] ?? '') as String,
      xkzt: '${j['xkzt'] ?? ''}',
      examType: (j['khfs'] ?? '') as String,
      teachMode: (j['skfsmc'] ?? '') as String,
      place: (j['skdd'] ?? '') as String,
    );
  }

  // 清理掉 HTML 标签的时间文本（sksj 里的 <br> 换成换行点）
  String get timeClean =>
      time.replaceAll('<br>', ' ｜ ').replaceAll(RegExp(r'<[^>]+>'), '');

  // 是否已选满
  bool get isFull => capacity > 0 && enrolled >= capacity;

  // 是否可用于选课请求
  bool get selectable => jx0404id.isNotEmpty && jx02id.isNotEmpty;
}
