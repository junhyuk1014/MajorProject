class Memo {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// 메모에 첨부된 이미지 경로 (없으면 null)
  final String? imagePath;

  Memo({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    this.updatedAt,
    this.imagePath,
  });

  DateTime get lastModified => updatedAt ?? createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      if (imagePath != null) 'imagePath': imagePath,  // 🔹 이미지 경로 저장
    };
  }

  factory Memo.fromJson(Map<String, dynamic> json) {
    return Memo(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
      imagePath: json['imagePath'], // 🔹 없으면 자동으로 null
    );
  }
}
