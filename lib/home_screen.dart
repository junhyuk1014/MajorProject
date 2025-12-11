import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
// import 'test_logic.dart'; // 데이터 주입 로직이 필요 없다면 주석/삭제
import 'calendar_screen.dart';
import 'memo_screen.dart';
import 'memory_item.dart';
import 'alarm_module.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  bool _isStatsLoading = true;
  List<MemoryItem> _memoryItems = [];

  double _avgEf = 2.0;
  double _memoryPercent = 0.0;

  List<_CategoryStat> _memoStats = [];
  List<_CategoryStat> _eventStats = [];

  // 접기/펼치기 상태 관리 변수
  bool _isMemoExpanded = false;
  bool _isEventExpanded = false;

  StreamSubscription<void>? _dataSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 참고: 테스트 데이터 주입이 필요하다면 주석 해제
    // injectEnglishWords200().then((_) {
    //   _loadStats();
    // });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkPermissions();
      await _loadStats();
    });

    _dataSubscription =
        AlarmService.dataUpdateStream.stream.listen((_) => _loadStats());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("앱이 활성화(Resumed) 되었습니다. 데이터를 갱신합니다.");
      _loadStats();
    }
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
              '정확한 시간에 복습 알림을 받으려면\n'
                  '[알람 및 리마인더] 권한이 필요합니다.\n\n'
                  '설정 화면에서 권한을 허용해 주세요.',
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

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final jsonList = prefs.getStringList('memory_items') ?? [];

    final items =
    jsonList.map((e) => MemoryItem.fromJson(jsonDecode(e))).toList();

    // 평균 EF 계산
    double avgEf;
    if (items.isEmpty) {
      avgEf = 2.0;
    } else {
      avgEf = items.map((i) => i.ef).fold(0.0, (a, b) => a + b) / items.length;
    }

    const minEf = 1.3;
    const maxEf = 3.0;
    double percent = ((avgEf - minEf) / (maxEf - minEf));
    if (percent.isNaN || percent.isInfinite) percent = 0.0;
    percent = (percent.clamp(0.0, 1.0)) * 100.0;

    final memoItems = items.where((i) => i.id.startsWith('MEMO_')).toList();
    final eventItems = items.where((i) => i.id.startsWith('EVENT_')).toList();

    List<_CategoryStat> memoStats = memoItems
        .map((item) => _CategoryStat(
      _extractTitle(item),
      _forgetScore(item),
    ))
        .toList();
    // 점수 높은 순 정렬
    memoStats.sort((a, b) => b.value.compareTo(a.value));

    List<_CategoryStat> eventStats = eventItems
        .map((item) => _CategoryStat(
      _extractTitle(item),
      _forgetScore(item),
    ))
        .toList();
    eventStats.sort((a, b) => b.value.compareTo(a.value));

    if (!mounted) return;
    setState(() {
      _memoryItems = items;
      _avgEf = avgEf;
      _memoryPercent = percent;
      _memoStats = memoStats;
      _eventStats = eventStats;
      _isStatsLoading = false;
    });
  }

  String _extractTitle(MemoryItem item) {
    final firstLine = item.content.split('\n').first;
    if (firstLine.startsWith('[메모] ')) {
      return firstLine.substring(5);
    }
    if (firstLine.startsWith('[일정] ')) {
      return firstLine.substring(5);
    }
    return firstLine;
  }

  double _forgetScore(MemoryItem item) {
    final now = DateTime.now();
    final overdue = now.isAfter(item.nextReviewDate);

    final base = (3.0 - item.ef).clamp(0.0, 3.0);
    final overdueBonus = overdue ? 1.5 : 1.0;
    final repBonus = 0.1 * item.repetitions;

    return (base * overdueBonus) + repBonus;
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
      child: _isStatsLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Text(
                  '대시보드',
                  style:
                  Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '나의 망각과 암기력 한눈에 보기',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildPanel(
                    '나의 망각 곡선',
                    subtitle: '최근 나의 곡선 vs 기준 에빙하우스 곡선',
                    children: [
                      SizedBox(
                        height: 200,
                        child: _buildForgettingCurveChart(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLegendDot(Colors.blue, '나의 곡선'),
                          const SizedBox(width: 16),
                          _buildLegendDot(Colors.orange, '기준 곡선'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildPanel(
                    '가장 많이 망각한 항목',
                    subtitle: '메모 기준 상위 항목',
                    children: [
                      if (_memoStats.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              '아직 분석할 메모 데이터가 없습니다.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        SizedBox(
                          height: 200,
                          child: _buildPieChart(_memoStats),
                        ),
                        const SizedBox(height: 8),
                        // 접기/펼치기 기능이 적용된 레전드
                        _buildExpandableLegend(
                          _memoStats,
                          _isMemoExpanded,
                              () {
                            setState(() {
                              _isMemoExpanded = !_isMemoExpanded;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildPanel(
                    '가장 많이 망각한 일정',
                    subtitle: '일정 기준 상위 항목',
                    children: [
                      if (_eventStats.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              '아직 분석할 일정 데이터가 없습니다.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        )
                      else ...[
                        SizedBox(
                          height: 200,
                          child: _buildPieChart(_eventStats),
                        ),
                        const SizedBox(height: 8),
                        // 접기/펼치기 기능이 적용된 레전드
                        _buildExpandableLegend(
                          _eventStats,
                          _isEventExpanded,
                              () {
                            setState(() {
                              _isEventExpanded = !_isEventExpanded;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildPanel(
                    '나의 암기력',
                    subtitle: '최근 1년(또는 누적) 학습 데이터 기반 추정',
                    children: [
                      Center(
                        child: Column(
                          children: [
                            Text(
                              '${_memoryPercent.round()}%',
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '평균 EF: ${_avgEf.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _memoryItems.isEmpty
                                  ? '아직 충분한 데이터가 없어 기본값으로 표시 중입니다.'
                                  : '에빙하우스 곡선을 기반으로 환산한 나의 암기력입니다.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: _memoryPercent / 100.0,
                              minHeight: 8,
                              backgroundColor: Colors.grey[200],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(
      String title, {
        required List<Widget> children,
        String subtitle = '',
      }) {
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
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildForgettingCurveChart() {
    final userSpots = _buildUserCurveSpots();
    final baseSpots = _buildBaseCurveSpots();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: 100,
        gridData: FlGridData(show: true),
        borderData: FlBorderData(show: true),
        titlesData: FlTitlesData(
          rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final day = value.toInt();
                return Text(
                  '${day}일',
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                if (value % 25 != 0) return const SizedBox.shrink();
                return Text(
                  '${value.toInt()}%',
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: baseSpots,
            isCurved: true,
            barWidth: 3,
            color: Colors.orange,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: userSpots,
            isCurved: true,
            barWidth: 3,
            color: Colors.blue,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  List<FlSpot> _buildUserCurveSpots() {
    final List<FlSpot> spots = [];
    const int days = 7;
    final k = 0.45 * (2.0 / _avgEf.clamp(1.3, 3.0));

    for (int d = 0; d < days; d++) {
      final t = d.toDouble();
      final retention = 100 * (1 / (1 + k * t));
      spots.add(FlSpot(t, retention.clamp(0, 100)));
    }
    return spots;
  }

  List<FlSpot> _buildBaseCurveSpots() {
    final List<FlSpot> spots = [];
    const int days = 7;
    const double baseK = 0.5;
    for (int d = 0; d < days; d++) {
      final t = d.toDouble();
      final retention = 100 * (1 / (1 + baseK * t));
      spots.add(FlSpot(t, retention.clamp(0, 100)));
    }
    return spots;
  }

  Widget _buildPieChart(List<_CategoryStat> stats) {
    // Top 5만 파이차트에 표시하고 싶으면 여기서 stats를 sublist로 자르면 됩니다.
    // 여기서는 전체 비율을 보여주되, 너무 많으면 보기 힘들 수 있으므로
    // 상위 5개만 차트에 표시하도록 수정합니다.
    final topStats = stats.length > 5 ? stats.take(5).toList() : stats;

    final total = topStats.fold<double>(0.0, (a, b) => a + b.value);
    if (total <= 0) {
      return const Center(
        child: Text(
          '표시할 데이터가 없습니다.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    final List<Color> colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
    ];

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: [
          for (int i = 0; i < topStats.length; i++)
            PieChartSectionData(
              color: colors[i % colors.length].withOpacity(0.9),
              value: topStats[i].value,
              title: '${(topStats[i].value / total * 100).round()}%',
              radius: 60,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  // 확장 가능한 레전드 빌더
  Widget _buildExpandableLegend(
      List<_CategoryStat> stats,
      bool isExpanded,
      VoidCallback onToggle,
      ) {
    const int limit = 5;

    // 데이터가 5개 이하면 더보기 버튼 없이 그냥 표시
    if (stats.length <= limit) {
      return _buildCategoryLegend(stats);
    }

    // 상태에 따라 보여줄 데이터 자르기
    final visibleStats = isExpanded ? stats : stats.sublist(0, limit);

    return Column(
      children: [
        _buildCategoryLegend(visibleStats),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: onToggle,
          icon: Icon(
            isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 20,
            color: Colors.grey[600],
          ),
          label: Text(
            isExpanded ? '접기' : '더보기 (+${stats.length - limit})',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryLegend(List<_CategoryStat> stats) {
    final List<Color> colors = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < stats.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    // 인덱스가 5를 넘어가면 색상이 반복되도록 처리
                    color: colors[i % colors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          stats[i].label,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (index) {
        setState(() => _selectedIndex = index);
        if (index == 0) {
          _loadStats();
        }
      },
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

class _CategoryStat {
  final String label;
  final double value;

  _CategoryStat(this.label, this.value);
}
