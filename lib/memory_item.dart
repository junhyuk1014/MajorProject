class MemoryItem {
  final String id;
  final String content;
  final double ef;
  final int interval;
  final int repetitions;
  final DateTime nextReviewDate;

  const MemoryItem({
    required this.id,
    required this.content,
    required this.ef,
    required this.interval,
    required this.repetitions,
    required this.nextReviewDate,
  });

  factory MemoryItem.initial({
    required String id,
    required String content,
    required double initialEf,
  }) {
    return MemoryItem(
      id: id,
      content: content,
      ef: initialEf,
      interval: 0,
      repetitions: 0,
      nextReviewDate: DateTime.now().add(const Duration(seconds: 10)),
    );
  }

  MemoryItem copyWith({
    String? id,
    String? content,
    double? ef,
    int? interval,
    int? repetitions,
    DateTime? nextReviewDate,
  }) {
    return MemoryItem(
      id: id ?? this.id,
      content: content ?? this.content,
      ef: ef ?? this.ef,
      interval: interval ?? this.interval,
      repetitions: repetitions ?? this.repetitions,
      nextReviewDate: nextReviewDate ?? this.nextReviewDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'ef': ef,
      'interval': interval,
      'repetitions': repetitions,
      'nextReviewDate': nextReviewDate.toIso8601String(),
    };
  }

  factory MemoryItem.fromJson(Map<String, dynamic> json) {
    return MemoryItem(
      id: json['id'],
      content: json['content'],
      ef: (json['ef'] as num).toDouble(),
      interval: json['interval'],
      repetitions: json['repetitions'],
      nextReviewDate: DateTime.parse(json['nextReviewDate']),
    );
  }
}
