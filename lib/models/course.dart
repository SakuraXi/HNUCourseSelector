class Course {
  final String courseName;
  final String courseNum;
  final String courseTeacher;
  final String courseId;
  bool selected;
  bool grabbed;

  Course({
    required this.courseName,
    required this.courseNum,
    required this.courseTeacher,
    required this.courseId,
    this.selected = true,
    this.grabbed = false,
  });

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        courseName: (json['courseName'] ?? '') as String,
        courseNum: (json['courseNum'] ?? '') as String,
        courseTeacher: (json['courseTeacher'] ?? '') as String,
        courseId: (json['courseID'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'courseName': courseName,
        'courseNum': courseNum,
        'courseTeacher': courseTeacher,
        'courseID': courseId,
      };
}
