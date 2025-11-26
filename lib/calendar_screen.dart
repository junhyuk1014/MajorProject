import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as cal;
import 'package:http/http.dart' as http;
import 'dart:async';
import 'calendar_event_model.dart';
import 'alarm_item.dart';
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
  DateTime _selectedDay = DateTime.now();
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
    _initializeGoogleSignIn();
    _selectedEvents = _getEventsForDay(_selectedDay);
  }

  void _initializeGoogleSignIn() {
    _googleSignIn = GoogleSignIn(
      scopes: [
        'https://www.googleapis.com/auth/calendar',
        'https://www.googleapis.com/auth/calendar.events',
      ],
    );

    print('Google Sign In 초기화 완료');

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

      final Map<DateTime, List<CalendarEvent>> eventsMap = {};

      for (var event in events.items ?? []) {
        if (event.start?.dateTime != null || event.start?.date != null) {
          final startDate = event.start?.dateTime ??
              DateTime.parse(event.start!.date!.toIso8601String());
          final endDate = event.end?.dateTime ??
              DateTime.parse(event.end!.date!.toIso8601String());

          final dateKey = DateTime(startDate.year, startDate.month, startDate.day);

          final calendarEvent = CalendarEvent(
            id: event.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
            title: event.summary ?? '(제목 없음)',
            description: event.description,
            startDate: startDate,
            endDate: endDate,
            isAllDay: event.start?.date != null,
          );

          if (eventsMap[dateKey] == null) {
            eventsMap[dateKey] = [];
          }
          eventsMap[dateKey]!.add(calendarEvent);
        }
      }

      setState(() {
        _events = eventsMap;
        _selectedEvents = _getEventsForDay(_selectedDay);
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

  List<CalendarEvent> _getEventsForDay(DateTime day) {
    final dateKey = DateTime(day.year, day.month, day.day);
    return _events[dateKey] ?? [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    if (!isSameDay(_selectedDay, selectedDay)) {
      setState(() {
        _selectedDay = selectedDay;
        _focusedDay = focusedDay;
        _selectedEvents = _getEventsForDay(selectedDay);
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
      );
    }
  }

  Future<void> _addEventToGoogle(
      String title,
      String? description,
      DateTime startDate,
      DateTime endDate,
      bool isAllDay,
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
        );
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
    final eventIndex = _events[DateTime(date.year, date.month, date.day)]
        ?.indexWhere((e) => e.id == event.id) ?? -1;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(event.title),
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

              const SizedBox(height: 24),

              // ▼▼▼ [실시간 UI 갱신] ▼▼▼
              StreamBuilder<void>(
                  stream: AlarmService.dataUpdateStream.stream,
                  builder: (context, _) {
                    return FutureBuilder<MemoryItem?>(
                      future: _alarmService.getMemoryItem('EVENT_${event.id}'),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data == null) {
                          return const SizedBox.shrink();
                        }

                        final item = snapshot.data!;
                        final isDue = DateTime.now().isAfter(item.nextReviewDate);

                        if (!isDue) {
                          return Center(
                            child: Text(
                              '✅ 복습 완료\n다음: ${item.nextReviewDate.toString().split('.')[0]}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
                            ),
                          );
                        }

                        return Column(
                          children: [
                            const Text('🔔 복습 시간입니다!', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildFeedbackBtn('다시(1)', 1, Colors.red, event),
                                _buildFeedbackBtn('보통(3)', 3, Colors.blue, event),
                                _buildFeedbackBtn('완벽(5)', 5, Colors.green, event),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  }
              ),
              // ▲▲▲ ----------------------- ▲▲▲
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
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기')),
        ],
      ),
    );
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
      );
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
            onPressed: () => _showAddEventDialog(_selectedDay),
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
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: _onDaySelected,
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.blueAccent,
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
                    onTap: () => _showEventDetail(event, _selectedDay),
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
