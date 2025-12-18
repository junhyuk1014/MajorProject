
class CalendarEvent {
    final String id;
    final String title;
    final String? description;
    final DateTime startDate;
    final DateTime endDate;
    final bool isAllDay;

    // ✅ 추가: 이미지 경로(로컬 파일 경로 등)
    final String? imagePath;

    CalendarEvent({
        required this.id,
        required this.title,
        this.description,
        required this.startDate,
        required this.endDate,
        this.isAllDay = false,
        this.imagePath, // ✅ 추가
    });

    // ✅ 추가: copyWith
    CalendarEvent copyWith({
        String? id,
        String? title,
        String? description,
        DateTime? startDate,
        DateTime? endDate,
        bool? isAllDay,
        String? imagePath,
    }) {
        return CalendarEvent(
            id: id ?? this.id,
            title: title ?? this.title,
            description: description ?? this.description,
            startDate: startDate ?? this.startDate,
            endDate: endDate ?? this.endDate,
            isAllDay: isAllDay ?? this.isAllDay,
            imagePath: imagePath ?? this.imagePath, // ✅ 유지/변경
        );
    }

    Map<String, dynamic> toJson() {
        return {
            'id': id,
            'title': title,
            'description': description,
            'startDate': startDate.toIso8601String(),
            'endDate': endDate.toIso8601String(),
            'isAllDay': isAllDay,
            if (imagePath != null) 'imagePath': imagePath, // ✅ 추가
        };
    }

    factory CalendarEvent.fromJson(Map<String, dynamic> json) {
        return CalendarEvent(
            id: json['id'],
            title: json['title'],
            description: json['description'],
            startDate: DateTime.parse(json['startDate']),
            endDate: DateTime.parse(json['endDate']),
            isAllDay: json['isAllDay'] ?? false,
            imagePath: json['imagePath'], // ✅ 추가
        );
    }
}