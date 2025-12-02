import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'calendar_screen.dart';
import 'memo_screen.dart';

class HomeScreen extends StatefulWidget {
    const HomeScreen({super.key});

    @override
    State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
    int _selectedIndex = 0;

    @override
    void initState() {
        super.initState();
        WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkPermissions();
        });
    }

    Future<void> _checkPermissions() async {
        if (await Permission.notification.isDenied) {
            await Permission.notification.request();
        }
        var alarmStatus = await Permission.scheduleExactAlarm.status;

        if (alarmStatus.isDenied) {
            if (!mounted) return;
            showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                    return AlertDialog(
                        title: const Text('알림 권한 필요'),
                        content: const Text(
                            '정확한 시간에 복습 알림을 받으려면\n[알람 및 리마인더] 권한이 필요합니다.\n\n설정 화면에서 권한을 허용해 주세요.',
                        ),
                        actions: [
                            TextButton(
                                child: const Text('나중에'),
                                onPressed: () => Navigator.of(context).pop(),
                            ),
                            ElevatedButton(
                                child: const Text('설정하러 가기'),
                                onPressed: () async {
                                    Navigator.of(context).pop();
                                    await Permission.scheduleExactAlarm.request();
                                    if (await Permission.scheduleExactAlarm.isDenied) {
                                        await openAppSettings();
                                    }
                                },
                            ),
                        ],
                    );
                },
            );
        }
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            backgroundColor: Colors.white,
            body: _getScreenForIndex(_selectedIndex),
            bottomNavigationBar: _buildBottomNavigationBar(),
        );
    }

    Widget _getScreenForIndex(int index) {
        switch (index) {
            case 0:
                return _buildStatisticsScreen();
            case 1:
                return const CalendarScreen();
            case 2:
                return const MemoScreen();
            default:
                return _buildStatisticsScreen();
        }
    }

    Widget _buildStatisticsScreen() {
        return SafeArea(
            child: Column(
                children: [
                    Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text(
                                    'Statistics',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Colors.grey[600],
                                        fontSize: 18,
                                    ),
                                ),
                            ],
                        ),
                    ),
                    Expanded(
                        child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                                _buildPanel('나의 망각 곡선', [
                                    _buildProgressBar('Views', 0.62, Colors.blue),
                                    _buildProgressBar('Visits', 0.74, Colors.orange),
                                    _buildProgressBar('Purchases', 0.51, Colors.black87),
                                ]),
                                const SizedBox(height: 16),
                                _buildPanel('가장 많이 망각한 항목(원그래프)',[
                                    _buildNumberBox('2,541', '복습 횟수', Colors.orange),
                                ]),
                                const SizedBox(height: 16),
                                _buildPanel('가장 많이 망각한 일정', [
                                    _buildNumberBox('56,321', '총 학습 항목', Colors.blue),
                                ]),
                                const SizedBox(height: 16),
                                _buildPanel('나의 암기력(환산수치)', [
                                    _buildNumberBox('77,483', '누적 복습', Colors.black87),
                                    _buildInfoList(),
                                ]),
                                const SizedBox(height: 16),
                            ],
                        ),
                    ),
                ],
            ),
        );
    }

    Widget _buildPanel(String title, List<Widget> children, [String subtitle = '']) {
        return Card(
            color: const Color(0xFFF5F5F5),
            child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        ],
                        const SizedBox(height: 16),
                        ...children,
                    ],
                ),
            ),
        );
    }

    Widget _buildProgressBar(String label, double value, Color color) {
        return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                            Text(label, style: const TextStyle(fontSize: 12)),
                            Text('${(value * 100).toInt()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                        value: value,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 6,
                    ),
                ],
            ),
        );
    }

    Widget _buildNumberBox(String number, String label, Color color) {
        return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
                children: [
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                            number,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                            ),
                        ),
                    ),
                    const SizedBox(height: 8),
                    Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
            ),
        );
    }

    Widget _buildInfoList() {
        return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
                children: [
                    _buildInfoItem(Icons.calculate, 'Profit', '56,321', false),
                    _buildInfoItem(Icons.access_time, 'Saving', '77,483', true),
                    _buildInfoItem(Icons.account_balance_wallet, 'Expenses', '568,333', false),
                    _buildInfoItem(Icons.business, 'Capital', '1,567,298', false),
                ],
            ),
        );
    }

    Widget _buildInfoItem(IconData icon, String label, String value, bool isHighlighted) {
        return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: isHighlighted ? Colors.blue[700] : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                    Row(
                        children: [
                            Icon(icon, color: isHighlighted ? Colors.white : Colors.grey[700], size: 20),
                            const SizedBox(width: 8),
                            Text(
                                label,
                                style: TextStyle(
                                    color: isHighlighted ? Colors.white : Colors.black87,
                                    fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                                ),
                            ),
                        ],
                    ),
                    Row(
                        children: [
                            Text(
                                value,
                                style: TextStyle(
                                    color: isHighlighted ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                                Icons.arrow_forward_ios,
                                size: 12,
                                color: isHighlighted ? Colors.white : Colors.grey[400],
                            ),
                        ],
                    ),
                ],
            ),
        );
    }

    Color _getColorForLabel(String label) {
        switch (label) {
            case 'Likes':
            case 'Advertising':
                return Colors.blue;
            case 'Dislike':
            case 'Subscription':
                return Colors.lightBlue;
            case 'Comment':
            case 'Donates':
                return Colors.orange;
            case 'Purchases':
                return Colors.black87;
            default:
                return Colors.grey;
        }
    }

    Widget _buildBottomNavigationBar() {
        return BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) => setState(() => _selectedIndex = index),
            backgroundColor: const Color(0xFFF5F5F5),
            selectedItemColor: Colors.brown[700],
            unselectedItemColor: Colors.brown[400],
            type: BottomNavigationBarType.fixed,
            items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home),
                    label: '홈',
                ),
                BottomNavigationBarItem(
                    icon: Icon(Icons.calendar_today_outlined),
                    activeIcon: Icon(Icons.calendar_today),
                    label: '캘린더',
                ),
                BottomNavigationBarItem(
                    icon: Icon(Icons.note_outlined),
                    activeIcon: Icon(Icons.note),
                    label: '메모',
                ),
            ],
        );
    }
}
