import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'calendar_event_model.dart';
import 'alarm_module.dart';
import 'user_profile.dart';
import 'memory_item.dart';

class _AuthenticatedHttpClient extends http.BaseClient {
    final http.Client _inner;
    final GoogleSignInAccount _account;

    _AuthenticatedHttpClient(this._inner, this._account);

    @override
    Future<http.StreamedResponse> send(http.BaseRequest request) async {
        final authHeaders = await _account.authHeaders;
        request.headers.addAll(authHeaders);
        return _inner.send(request);
    }

    @override
    void close() {
        _inner.close();
    }
}

class CalendarScreen extends StatefulWidget {
    const CalendarScreen({super.key});

    @override
    State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
    CalendarFormat _calendarFormat = CalendarFormat.month;
    DateTime _focusedDay = DateTime.now();
    DateTime? _selectedDay;
    Map<DateTime, List<CalendarEvent>> _events = {};
    List<CalendarEvent> _selectedEvents = [];
    final AlarmService _alarmService = AlarmService();
    final UserProfile _userProfile = UserProfile();
    GoogleSignIn? _googleSignIn;
    GoogleSignInAccount? _currentUser;
    cal.CalendarApi? _calendarApi;
    bool _isSignedIn = false;
    bool _isLoading = false;

    @override
    void initState() {
        super.initState();
        final now = DateTime.now();
        _focusedDay = _dateOnly(now);   // 오늘을 기준으로 캘린더를 보여줌
        _selectedDay = null;            // 처음에는 아무 날짜도 선택하지 않음
        _loadUserProfile();
        _initializeGoogleSignIn();
        _selectedEvents = [];           // 선택한 날짜가 없으니 빈 리스트
    }

    Future<void> _loadUserProfile() async {
        await _userProfile.load();
    }

    void _initializeGoogleSignIn() {
        _googleSignIn = GoogleSignIn(
            scopes: [
                'https://www.googleapis.com/auth/calendar',
                'https://www.googleapis.com/auth/calendar.events',
            ],
        );

        _googleSignIn!.onCurrentUserChanged.listen((GoogleSignInAccount? account) {
            if (account != null) {
                _handleSignIn(account);
            } else {
                setState(() {
                    _isSignedIn = false;
                    _calendarApi = null;
                    _events = {};
                    _selectedEvents = [];
                });
            }
        });

        _checkSignInStatus();
    }

    Future<void> _checkSignInStatus() async {
        final account = await _googleSignIn!.signInSilently();
        if (account != null) {
            await _handleSignIn(account);
        }
    }

    Future<void> _handleSignIn(GoogleSignInAccount account) async {
        setState(() {
            _isLoading = true;
        });

        try {
            _currentUser = account;
            final authenticatedClient = _AuthenticatedHttpClient(http.Client(), account);

            setState(() {
                _calendarApi = cal.CalendarApi(authenticatedClient);
                _isSignedIn = true;
                _isLoading = false;
            });

            await _loadEventsFromGoogle();
        } catch (e) {
            setState(() {
                _isLoading = false;
            });
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('로그인 오류: $e')),
                );
            }
        }
    }

    Future<void> _signIn() async {
        try {
            final account = await _googleSignIn!.signIn();
            if (account != null) {
                await _handleSignIn(account);
            }
        } catch (e) {
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('로그인 실패: $e')),
                );
            }
        }
    }

    Future<void> _signOut() async {
        await _googleSignIn!.signOut();
        setState(() {
            _isSignedIn = false;
            _calendarApi = null;
            _events = {};
            _selectedEvents = [];
        });
    }

    DateTime _dateOnly(DateTime date) {
        return DateTime(date.year, date.month, date.day);
    }


    Future<String?> _pickAndSaveImage() async {
        try {
            final picker = ImagePicker();
            final XFile? picked =
                await picker.pickImage(source: ImageSource.gallery);

            if (picked == null) return null;

            final appDir = await getApplicationDocumentsDirectory();
            final fileName =
                'event_img_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}';
            final savedPath = p.join(appDir.path, fileName);
            await File(picked.path).copy(savedPath);
            return savedPath;
        } catch (e) {
            return null;
        }
    }

    Future<void> _loadEventsFromGoogle() async {
        if (_calendarApi == null) return;

        setState(() {
            _isLoading = true;
        });

        try {
            final now = DateTime.now();
            final timeMin = DateTime(now.year - 1, 1, 1);
            final timeMax = DateTime(now.year + 1, 12, 31);

            final events = await _calendarApi!.events.list(
                'primary',
                timeMin: timeMin.toUtc(),
                timeMax: timeMax.toUtc(),
                maxResults: 2500,
            );

            // 로컬에 저장된 이벤트 불러오기
            final localEvents = await _loadLocalEvents();
            final Map<String, CalendarEvent> localEventsMap = {
                for (var e in localEvents) e.id: e
            };

            final Map<DateTime, List<CalendarEvent>> eventsMap = {};
            final Set<String> processedEventIds = {}; // 처리된 이벤트 ID 추적

            // Google Calendar에서 불러온 이벤트 처리
            for (var event in events.items ?? []) {
                if (event.start?.dateTime != null || event.start?.date != null) {
                    final startDate = event.start?.dateTime ??
                        DateTime.parse(event.start!.date!.toIso8601String());
                    final endDate = event.end?.dateTime ??
                        DateTime.parse(event.end!.date!.toIso8601String());

                    final dateKey = DateTime(startDate.year, startDate.month, startDate.day);
                    final eventId = event.id ?? DateTime.now().millisecondsSinceEpoch.toString();
                    processedEventIds.add(eventId);

                    // 로컬에 저장된 이벤트가 있으면 그것을 사용, 없으면 새로 생성
                    final calendarEvent = localEventsMap[eventId] ?? CalendarEvent(
                        id: eventId,
                        title: event.summary ?? '(제목 없음)',
                        description: event.description,
                        startDate: startDate,
                        endDate: endDate,
                        isAllDay: event.start?.date != null,
                    );

                    // Google Calendar에서 업데이트된 정보로 갱신 (이미지는 유지)
                    final updatedEvent = calendarEvent.copyWith(
                        title: event.summary ?? calendarEvent.title,
                        description: event.description ?? calendarEvent.description,
                        startDate: startDate,
                        endDate: endDate,
                        isAllDay: event.start?.date != null,
                        imagePath: calendarEvent.imagePath, // 이미지 경로 명시적으로 유지
                    );

                    if (eventsMap[dateKey] == null) {
                        eventsMap[dateKey] = [];
                    }
                    eventsMap[dateKey]!.add(updatedEvent);
                }
            }

            // 로컬에만 있는 이벤트 추가 (이미지가 있는 이벤트 등)
            for (var localEvent in localEvents) {
                if (!processedEventIds.contains(localEvent.id)) {
                    print('로컬 전용 이벤트 발견 - ID: ${localEvent.id}, imagePath: ${localEvent.imagePath}');
                    final dateKey = DateTime(localEvent.startDate.year, localEvent.startDate.month, localEvent.startDate.day);
                    if (eventsMap[dateKey] == null) {
                        eventsMap[dateKey] = [];
                    }
                    // 중복 체크
                    if (!eventsMap[dateKey]!.any((e) => e.id == localEvent.id)) {
                        eventsMap[dateKey]!.add(localEvent);
                        print('로컬 전용 이벤트 추가됨 - ID: ${localEvent.id}, imagePath: ${localEvent.imagePath}');
                    }
                }
            }

            // 로컬 이벤트 저장
            final allEvents = eventsMap.values.expand((list) => list).toList();
            await _saveLocalEvents(allEvents);

            setState(() {
                _events = eventsMap;
                _selectedEvents = _selectedDay == null
                    ? []
                    : _getEventsForDay(_selectedDay!);
                _isLoading = false;
            });
        } catch (e) {
            setState(() {
                _isLoading = false;
            });
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('일정 불러오기 실패: $e')),
                );
            }
        }
    }

    Future<List<CalendarEvent>> _loadLocalEvents() async {
        try {
            final prefs = await SharedPreferences.getInstance();
            final eventsJson = prefs.getStringList('calendar_events') ?? [];
            return eventsJson
                .map((json) => CalendarEvent.fromJson(jsonDecode(json)))
                .toList();
        } catch (e) {
            return [];
        }
    }

    Future<void> _saveLocalEvents(List<CalendarEvent> events) async {
        try {
            final prefs = await SharedPreferences.getInstance();
            final eventsJson = events.map((event) => jsonEncode(event.toJson())).toList();
            await prefs.setStringList('calendar_events', eventsJson);
        } catch (e) {
            print('일정 저장 오류: $e');
        }
    }

    List<CalendarEvent> _getEventsForDay(DateTime day) {
        final dateKey = DateTime(day.year, day.month, day.day);
        return _events[dateKey] ?? [];
    }

    void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
        final dateOnlySelected = _dateOnly(selectedDay);
        final DateTime? dateOnlyCurrent =
            _selectedDay == null ? null : _dateOnly(_selectedDay!);

        // 처음 선택하거나, 이전 선택과 날짜가 다를 때만 업데이트
        if (dateOnlyCurrent == null ||
            dateOnlyCurrent.year != dateOnlySelected.year ||
            dateOnlyCurrent.month != dateOnlySelected.month ||
            dateOnlyCurrent.day != dateOnlySelected.day) {
            setState(() {
                _selectedDay = dateOnlySelected;
                _focusedDay = _dateOnly(focusedDay);
                _selectedEvents = _getEventsForDay(_selectedDay!);
            });
        }
    }

    Future<void> _showAddEventDialog(DateTime date) async {
        if (!_isSignedIn) {
            await _signIn();
            return;
        }

        final titleController = TextEditingController();
        final descriptionController = TextEditingController();
        DateTime startDate = DateTime(date.year, date.month, date.day, 9, 0);
        DateTime endDate = DateTime(date.year, date.month, date.day, 10, 0);
        bool isAllDay = false;
        String? tempImagePath;

        final result = await showDialog<bool>(
            context: context,
            builder: (context) => StatefulBuilder(
                builder: (context, setDialogState) => AlertDialog(
                    backgroundColor: Colors.white,
                    title: const Text('일정 추가'),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                TextField(
                                    controller: titleController,
                                    decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                    controller: descriptionController,
                                    decoration: const InputDecoration(labelText: '설명', border: OutlineInputBorder()),
                                    maxLines: 3,
                                ),
                                const SizedBox(height: 16),
                                // 사진 추가 버튼을 먼저 표시
                                TextButton.icon(
                                    onPressed: () async {
                                        final path = await _pickAndSaveImage();
                                        if (!context.mounted) return;
                                        if (path != null) {
                                            setDialogState(() {
                                                tempImagePath = path;
                                            });
                                        }
                                    },
                                    icon: const Icon(Icons.image),
                                    label: const Text('사진 추가'),
                                ),
                                if (tempImagePath != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Stack(
                                            children: [
                                                ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Image.file(
                                                        File(tempImagePath!),
                                                        height: 150,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context, error, stackTrace) {
                                                            return Container(
                                                                height: 150,
                                                                color: Colors.grey[300],
                                                                alignment: Alignment.center,
                                                                child: const Text(
                                                                    '이미지를 불러올 수 없습니다.',
                                                                    style: TextStyle(fontSize: 12),
                                                                ),
                                                            );
                                                        },
                                                    ),
                                                ),
                                                Positioned(
                                                    right: 0,
                                                    top: 0,
                                                    child: GestureDetector(
                                                        onTap: () {
                                                            setDialogState(() {
                                                                tempImagePath = null;
                                                            });
                                                        },
                                                        child: Container(
                                                            color: Colors.black54,
                                                            child: const Icon(
                                                                Icons.close,
                                                                color: Colors.white,
                                                            ),
                                                        ),
                                                    ),
                                                ),
                                            ],
                                        ),
                                    ),
                                const SizedBox(height: 16),
                                CheckboxListTile(
                                    title: const Text('하루 종일'),
                                    value: isAllDay,
                                    onChanged: (value) {
                                        setDialogState(() {
                                            isAllDay = value ?? false;
                                        });
                                    },
                                ),
                                if (!isAllDay) ...[
                                    const SizedBox(height: 8),
                                    ListTile(
                                        title: const Text('시작 시간'),
                                        subtitle: Text(
                                            '${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}',
                                        ),
                                        trailing: const Icon(Icons.access_time),
                                        onTap: () async {
                                            final time = await showTimePicker(
                                                context: context,
                                                initialTime: TimeOfDay.fromDateTime(startDate),
                                            );
                                            if (time != null) {
                                                setDialogState(() {
                                                    startDate = DateTime(startDate.year, startDate.month, startDate.day, time.hour, time.minute);
                                                });
                                            }
                                        },
                                    ),
                                    ListTile(
                                        title: const Text('종료 시간'),
                                        subtitle: Text(
                                            '${endDate.hour.toString().padLeft(2, '0')}:${endDate.minute.toString().padLeft(2, '0')}',
                                        ),
                                        trailing: const Icon(Icons.access_time),
                                        onTap: () async {
                                            final time = await showTimePicker(
                                                context: context,
                                                initialTime: TimeOfDay.fromDateTime(endDate),
                                            );
                                            if (time != null) {
                                                setDialogState(() {
                                                    endDate = DateTime(endDate.year, endDate.month, endDate.day, time.hour, time.minute);
                                                });
                                            }
                                        },
                                    ),
                                ],
                            ],
                        ),
                    ),
                    actions: [
                        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('취소')),
                        ElevatedButton(
                            onPressed: () {
                                if (titleController.text.trim().isNotEmpty) {
                                    Navigator.of(context).pop(true);
                                }
                            },
                            child: const Text('추가하기'),
                        ),
                    ],
                ),
            ),
        );

        if (result == true && titleController.text.trim().isNotEmpty && _calendarApi != null) {
            await _addEventToGoogle(
                titleController.text.trim(),
                descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
                startDate,
                endDate,
                isAllDay,
                tempImagePath,
            );
        }
    }

    Future<void> _addEventToGoogle(
        String title,
        String? description,
        DateTime startDate,
        DateTime endDate,
        bool isAllDay,
        String? imagePath,
        ) async {
        if (_calendarApi == null) return;

        setState(() {
            _isLoading = true;
        });

        try {
            final event = cal.Event()
                ..summary = title
                ..description = description
                ..start = isAllDay
                    ? cal.EventDateTime(date: _dateOnly(startDate))
                    : cal.EventDateTime(dateTime: startDate.toUtc())
                ..end = isAllDay
                    ? cal.EventDateTime(date: _dateOnly(endDate))
                    : cal.EventDateTime(dateTime: endDate.toUtc());

            final createdEvent = await _calendarApi!.events.insert(event, 'primary');
            if (createdEvent.id != null) {
                final localEvent = CalendarEvent(
                    id: createdEvent.id!,
                    title: createdEvent.summary ?? title,
                    description: createdEvent.description,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    imagePath: imagePath,
                );
                
                // 디버깅 로그
                print('=== _addEventToGoogle 디버깅 ===');
                print('Created Event ID: ${createdEvent.id}');
                print('ImagePath: $imagePath');
                print('LocalEvent imagePath: ${localEvent.imagePath}');
                print('==============================');
                
                // 로컬에 저장
                final localEvents = await _loadLocalEvents();
                localEvents.add(localEvent);
                await _saveLocalEvents(localEvents);
                
                // 저장 후 확인
                final savedEvents = await _loadLocalEvents();
                final savedEvent = savedEvents.firstWhere((e) => e.id == createdEvent.id!, orElse: () => localEvent);
                print('저장 후 확인 - Event ID: ${savedEvent.id}, imagePath: ${savedEvent.imagePath}');
                
                await _alarmService.saveEvent(localEvent, _userProfile);
            }

            await _loadEventsFromGoogle();

            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('일정이 구글 캘린더에 추가되었습니다.')),
                );
            }
        } catch (e) {
            setState(() {
                _isLoading = false;
            });
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('일정 추가 실패: $e')),
                );
            }
        }
    }

    Future<void> _handleFeedback(CalendarEvent event, int score) async {
        await _alarmService.processFeedback('EVENT_${event.id}', score);
        if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$score점 반영 완료!')));
        }
    }

    void _showEventDetail(CalendarEvent event, DateTime date) {
      try {
        final dateKey = DateTime(date.year, date.month, date.day);
        final eventIndex = _events[dateKey]?.indexWhere((e) => e.id == event.id) ?? -1;

        if (!mounted) return;

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            title: Text(event.title.isEmpty ? '(제목 없음)' : event.title),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (event.description != null && event.description!.isNotEmpty) ...[
                    Text(event.description!),
                    const SizedBox(height: 16),
                  ],
                  const Divider(),
                  Text(
                    '시작: ${event.startDate.toString().split('.')[0]}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '종료: ${event.endDate.toString().split('.')[0]}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => _showDeleteConfirmDialog(event, date, eventIndex),
                child: const Text('삭제', style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showEditEventDialog(event, date, eventIndex);
                },
                child: const Text('수정'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('닫기'),
              ),
            ],
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('일정 상세 보기 오류: $e')),
          );
        }
      }
    }

    Widget _buildFeedbackBtn(String text, int score, Color color, CalendarEvent event) {
        return ElevatedButton(
            onPressed: () => _handleFeedback(event, score),
            style: ElevatedButton.styleFrom(
                backgroundColor: color.withOpacity(0.1),
                foregroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
            ),
            child: Text(text, style: const TextStyle(fontSize: 12)),
        );
    }

    Future<void> _showEditEventDialog(CalendarEvent event, DateTime date, int index) async {
        if (!_isSignedIn || _calendarApi == null) return;

        final titleController = TextEditingController(text: event.title);
        final descriptionController = TextEditingController(text: event.description ?? '');
        DateTime startDate = event.startDate;
        DateTime endDate = event.endDate;
        bool isAllDay = event.isAllDay;
        String? tempImagePath = event.imagePath;

        final result = await showDialog<bool>(
            context: context,
            builder: (context) => StatefulBuilder(
                builder: (context, setDialogState) => AlertDialog(
                    backgroundColor: Colors.white,
                    title: const Text('일정 수정'),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                TextField(
                                    controller: titleController,
                                    decoration: const InputDecoration(labelText: '제목', border: OutlineInputBorder()),
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                    controller: descriptionController,
                                    decoration: const InputDecoration(labelText: '설명', border: OutlineInputBorder()),
                                    maxLines: 3,
                                ),
                                const SizedBox(height: 16),
                                // 사진 추가 버튼을 먼저 표시
                                TextButton.icon(
                                    onPressed: () async {
                                        final path = await _pickAndSaveImage();
                                        if (!context.mounted) return;
                                        if (path != null) {
                                            setDialogState(() {
                                                tempImagePath = path;
                                            });
                                        }
                                    },
                                    icon: const Icon(Icons.image),
                                    label: Text(
                                        tempImagePath == null ? '사진 추가' : '사진 변경',
                                    ),
                                ),
                                if (tempImagePath != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Stack(
                                            children: [
                                                ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Image.file(
                                                        File(tempImagePath!),
                                                        height: 150,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context, error, stackTrace) {
                                                            return Container(
                                                                height: 150,
                                                                color: Colors.grey[300],
                                                                alignment: Alignment.center,
                                                                child: const Text(
                                                                    '이미지를 불러올 수 없습니다.',
                                                                    style: TextStyle(fontSize: 12),
                                                                ),
                                                            );
                                                        },
                                                    ),
                                                ),
                                                Positioned(
                                                    right: 0,
                                                    top: 0,
                                                    child: GestureDetector(
                                                        onTap: () {
                                                            setDialogState(() {
                                                                tempImagePath = null;
                                                            });
                                                        },
                                                        child: Container(
                                                            color: Colors.black54,
                                                            child: const Icon(
                                                                Icons.close,
                                                                color: Colors.white,
                                                            ),
                                                        ),
                                                    ),
                                                ),
                                            ],
                                        ),
                                    ),
                                const SizedBox(height: 16),
                                CheckboxListTile(
                                    title: const Text('하루 종일'),
                                    value: isAllDay,
                                    onChanged: (value) {
                                        setDialogState(() {
                                            isAllDay = value ?? false;
                                        });
                                    },
                                ),
                                if (!isAllDay) ...[
                                    const SizedBox(height: 8),
                                    ListTile(
                                        title: const Text('시작 시간'),
                                        subtitle: Text(
                                            '${startDate.hour.toString().padLeft(2, '0')}:${startDate.minute.toString().padLeft(2, '0')}',
                                        ),
                                        trailing: const Icon(Icons.access_time),
                                        onTap: () async {
                                            final time = await showTimePicker(
                                                context: context,
                                                initialTime: TimeOfDay.fromDateTime(startDate),
                                            );
                                            if (time != null) {
                                                setDialogState(() {
                                                    startDate = DateTime(startDate.year, startDate.month, startDate.day, time.hour, time.minute);
                                                });
                                            }
                                        },
                                    ),
                                    ListTile(
                                        title: const Text('종료 시간'),
                                        subtitle: Text(
                                            '${endDate.hour.toString().padLeft(2, '0')}:${endDate.minute.toString().padLeft(2, '0')}',
                                        ),
                                        trailing: const Icon(Icons.access_time),
                                        onTap: () async {
                                            final time = await showTimePicker(
                                                context: context,
                                                initialTime: TimeOfDay.fromDateTime(endDate),
                                            );
                                            if (time != null) {
                                                setDialogState(() {
                                                    endDate = DateTime(endDate.year, endDate.month, endDate.day, time.hour, time.minute);
                                                });
                                            }
                                        },
                                    ),
                                ],
                            ],
                        ),
                    ),
                    actions: [
                        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('취소')),
                        ElevatedButton(
                            onPressed: () {
                                if (titleController.text.trim().isNotEmpty) {
                                    Navigator.of(context).pop(true);
                                }
                            },
                            child: const Text('저장'),
                        ),
                    ],
                ),
            ),
        );

        if (result == true && titleController.text.trim().isNotEmpty) {
            await _updateEventInGoogle(
                event.id,
                titleController.text.trim(),
                descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
                startDate,
                endDate,
                isAllDay,
                tempImagePath,
            );
        }
    }

    Future<void> _updateEventInGoogle(
        String eventId,
        String title,
        String? description,
        DateTime startDate,
        DateTime endDate,
        bool isAllDay,
        String? imagePath,
        ) async {
        if (_calendarApi == null) return;

        setState(() {
            _isLoading = true;
        });

        try {
            final event = cal.Event()
                ..summary = title
                ..description = description
                ..start = isAllDay
                    ? cal.EventDateTime(date: _dateOnly(startDate))
                    : cal.EventDateTime(dateTime: startDate.toUtc())
                ..end = isAllDay
                    ? cal.EventDateTime(date: _dateOnly(endDate))
                    : cal.EventDateTime(dateTime: endDate.toUtc());

            final updatedEvent = await _calendarApi!.events.update(event, 'primary', eventId);
            
            final localEvent = CalendarEvent(
                id: eventId,
                title: title,
                description: description,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                imagePath: imagePath,
            );
            
            // 로컬에 저장
            final localEvents = await _loadLocalEvents();
            final index = localEvents.indexWhere((e) => e.id == eventId);
            if (index != -1) {
                localEvents[index] = localEvent;
            } else {
                localEvents.add(localEvent);
            }
            await _saveLocalEvents(localEvents);
            
            await _alarmService.saveEvent(localEvent, _userProfile);
            await _loadEventsFromGoogle();

            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('일정이 수정되었습니다.')),
                );
            }
        } catch (e) {
            setState(() {
                _isLoading = false;
            });
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('일정 수정 실패: $e')),
                );
            }
        }
    }

    void _showDeleteConfirmDialog(CalendarEvent event, DateTime date, int index) {
        showDialog(
            context: context,
            builder: (context) => AlertDialog(
                backgroundColor: Colors.white,
                title: const Text('일정 삭제'),
                content: const Text('정말 이 일정을 삭제하시겠습니까?'),
                actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('취소')),
                    ElevatedButton(
                        onPressed: () async {
                            Navigator.of(context).pop();
                            Navigator.of(context).pop();
                            await _deleteEventFromGoogle(event.id);
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                        ),
                        child: const Text('삭제'),
                    ),
                ],
            ),
        );
    }

    Future<void> _deleteEventFromGoogle(String eventId) async {
        if (_calendarApi == null) return;

        setState(() {
            _isLoading = true;
        });

        try {
            await _calendarApi!.events.delete('primary', eventId);
            await _alarmService.deleteEvent(eventId);
            
            // 로컬에서도 삭제
            final localEvents = await _loadLocalEvents();
            localEvents.removeWhere((e) => e.id == eventId);
            await _saveLocalEvents(localEvents);
            
            await _loadEventsFromGoogle();

            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('일정이 삭제되었습니다.')),
                );
            }
        } catch (e) {
            setState(() {
                _isLoading = false;
            });
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('일정 삭제 실패: $e')),
                );
            }
        }
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
                title: const Text('캘린더'),
                actions: [
                    if (!_isSignedIn)
                        IconButton(
                            icon: const Icon(Icons.login),
                            onPressed: _signIn,
                            tooltip: '구글 로그인',
                        )
                    else
                        IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _loadEventsFromGoogle,
                            tooltip: '새로고침',
                        ),
                    if (_isSignedIn)
                        IconButton(
                            icon: const Icon(Icons.logout),
                            onPressed: _signOut,
                            tooltip: '로그아웃',
                        ),
                    IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () => _showAddEventDialog(_selectedDay ?? _focusedDay),
                        tooltip: '일정 추가',
                    ),
                ],
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : !_isSignedIn
                ? Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            const Icon(Icons.calendar_today, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                                '구글 캘린더와 연동하려면\n로그인이 필요합니다.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                                onPressed: _signIn,
                                icon: const Icon(Icons.login),
                                label: const Text('구글 로그인'),
                            ),
                        ],
                    ),
                )
                : Column(
                    children: [
                        TableCalendar<CalendarEvent>(
                            firstDay: DateTime.utc(2020, 1, 1),
                            lastDay: DateTime.utc(2030, 12, 31),
                            focusedDay: _focusedDay,
                            calendarFormat: _calendarFormat,
                            eventLoader: _getEventsForDay,
                            startingDayOfWeek: StartingDayOfWeek.monday,
                            selectedDayPredicate: (day) {
                                if (_selectedDay == null) return false;
                                final selected = _dateOnly(_selectedDay!);
                                final checkDay = _dateOnly(day);
                                return selected.year == checkDay.year &&
                                       selected.month == checkDay.month &&
                                       selected.day == checkDay.day;
                            },
                            onDaySelected: _onDaySelected,
                            onFormatChanged: (format) {
                                if (_calendarFormat != format) {
                                    setState(() {
                                        _calendarFormat = format;
                                    });
                                }
                            },
                            onPageChanged: (focusedDay) {
                                setState(() {
                                    _focusedDay = _dateOnly(focusedDay);
                                });
                            },
                            calendarStyle: const CalendarStyle(
                                todayDecoration: BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                ),
                                selectedDecoration: BoxDecoration(
                                    color: Colors.blueGrey,
                                    shape: BoxShape.circle,
                                ),
                                markerDecoration: BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                ),
                            ),
                            headerStyle: const HeaderStyle(
                                formatButtonVisible: true,
                                titleCentered: true,
                            ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                            child: _selectedEvents.isEmpty
                                ? const Center(
                                    child: Text(
                                        '선택한 날짜에 일정이 없습니다.',
                                        style: TextStyle(color: Colors.grey),
                                    ),
                                )
                                : ListView.builder(
                                    itemCount: _selectedEvents.length,
                                    itemBuilder: (context, index) {
                                        final event = _selectedEvents[index];
                                        return Card(
                                            color: const Color(0xFFF5F5F5),
                                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            child: ListTile(
                                                leading: event.imagePath != null
                                                    ? ClipRRect(
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: FutureBuilder<Uint8List>(
                                                            future: File(event.imagePath!).readAsBytes(),
                                                            builder: (context, snapshot) {
                                                                print('detail snapshot: hasData=${snapshot.hasData}, '
                                                                    'data=${snapshot.data}, state=${snapshot.connectionState}');
                                                                if (snapshot.connectionState == ConnectionState.waiting) {
                                                                    return Container(
                                                                        width: 50,
                                                                        height: 50,
                                                                        color: Colors.grey[200],
                                                                        alignment: Alignment.center,
                                                                        child: const SizedBox(
                                                                            width: 20,
                                                                            height: 20,
                                                                            child: CircularProgressIndicator(strokeWidth: 2),
                                                                        ),
                                                                    );
                                                                }
                                                                if (snapshot.hasError || !snapshot.hasData) {
                                                                    return Container(
                                                                        width: 50,
                                                                        height: 50,
                                                                        color: Colors.grey[300],
                                                                        alignment: Alignment.center,
                                                                        child: const Icon(
                                                                            Icons.broken_image,
                                                                            size: 20,
                                                                        ),
                                                                    );
                                                                }
                                                                return Image.memory(
                                                                    snapshot.data!,
                                                                    width: 50,
                                                                    height: 50,
                                                                    fit: BoxFit.cover,
                                                                );
                                                            },
                                                        ),
                                                    )
                                                    : null,
                                                title: Text(
                                                    event.title,
                                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                                subtitle: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                        if (event.description != null && event.description!.isNotEmpty) ...[
                                                            const SizedBox(height: 4),
                                                            Text(
                                                                event.description!,
                                                                maxLines: 2,
                                                                overflow: TextOverflow.ellipsis,
                                                            ),
                                                        ],
                                                        const SizedBox(height: 4),
                                                        Text(
                                                            event.isAllDay
                                                                ? '하루 종일'
                                                                : '${event.startDate.hour.toString().padLeft(2, '0')}:${event.startDate.minute.toString().padLeft(2, '0')} - ${event.endDate.hour.toString().padLeft(2, '0')}:${event.endDate.minute.toString().padLeft(2, '0')}',
                                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                        ),
                                                    ],
                                                ),
                                                onTap: () => _showEventDetail(event, _selectedDay ?? _focusedDay),
                                            ),
                                        );
                                    },
                                ),
                        ),
                    ],
                ),
        );
    }
}