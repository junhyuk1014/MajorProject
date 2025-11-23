import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'memo_model.dart';

class MemoScreen extends StatefulWidget {
  const MemoScreen({super.key});

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  List<Memo> _memos = [];

  @override
  void initState() {
    super.initState();
    _loadMemos();
  }

  Future<void> _loadMemos() async {
    final prefs = await SharedPreferences.getInstance();
    final memosJson = prefs.getStringList('memos') ?? [];
    
    setState(() {
      _memos = memosJson
          .map((json) => Memo.fromJson(jsonDecode(json)))
          .toList()
        ..sort((a, b) => b.lastModified.compareTo(a.lastModified)); // 최신순 정렬
    });
  }

  Future<void> _saveMemos() async {
    final prefs = await SharedPreferences.getInstance();
    final memosJson = _memos
        .map((memo) => jsonEncode(memo.toJson()))
        .toList();
    
    await prefs.setStringList('memos', memosJson);
  }

  Future<void> _showAddMemoDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('메모 추가'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: '제목',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              decoration: InputDecoration(
                labelText: '내용',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
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
    );

    if (result == true && titleController.text.trim().isNotEmpty) {
      final newMemo = Memo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: titleController.text.trim(),
        content: contentController.text.trim(),
        createdAt: DateTime.now(),
      );

      setState(() {
        _memos.insert(0, newMemo);
        _memos.sort((a, b) => b.lastModified.compareTo(a.lastModified)); // 최신순 정렬
      });

      await _saveMemos();
    }
  }

  void _showMemoDetail(Memo memo) {
    final memoIndex = _memos.indexWhere((m) => m.id == memo.id);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(memo.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (memo.content.isNotEmpty) ...[
                Text(
                  memo.content,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
              ] else
                const Text(
                  '(내용 없음)',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
              const Divider(),
              Text(
                '작성일: ${memo.createdAt.year}-${memo.createdAt.month.toString().padLeft(2, '0')}-${memo.createdAt.day.toString().padLeft(2, '0')} ${memo.createdAt.hour.toString().padLeft(2, '0')}:${memo.createdAt.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              if (memo.updatedAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  '수정일: ${memo.updatedAt!.year}-${memo.updatedAt!.month.toString().padLeft(2, '0')}-${memo.updatedAt!.day.toString().padLeft(2, '0')} ${memo.updatedAt!.hour.toString().padLeft(2, '0')}:${memo.updatedAt!.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _showDeleteConfirmDialog(memo, memoIndex),
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showEditMemoDialog(memo, memoIndex);
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
  }

  Future<void> _showEditMemoDialog(Memo memo, int index) async {
    final titleController = TextEditingController(text: memo.title);
    final contentController = TextEditingController(text: memo.content);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('메모 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: '제목',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              decoration: InputDecoration(
                labelText: '내용',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 5,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
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
    );

    if (result == true && titleController.text.trim().isNotEmpty) {
      final updatedMemo = Memo(
        id: memo.id,
        title: titleController.text.trim(),
        content: contentController.text.trim(),
        createdAt: memo.createdAt, // 작성일은 유지
        updatedAt: DateTime.now(), // 수정 시간 업데이트
      );

      setState(() {
        _memos[index] = updatedMemo;
        _memos.sort((a, b) => b.lastModified.compareTo(a.lastModified)); // 최신순 정렬
      });

      await _saveMemos();
    }
  }

  void _showDeleteConfirmDialog(Memo memo, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('메모 삭제'),
        content: const Text('정말 이 메모를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _memos.removeAt(index);
                _memos.sort((a, b) => b.lastModified.compareTo(a.lastModified)); // 최신순 정렬
              });
              
              await _saveMemos();
              
              if (context.mounted) {
                Navigator.of(context).pop(); // 확인 다이얼로그 닫기
                Navigator.of(context).pop(); // 상세 다이얼로그 닫기
              }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddMemoDialog,
            tooltip: '메모 추가',
          ),
        ],
      ),
      body: _memos.isEmpty
          ? const Center(
              child: Text(
                '메모가 없습니다.\n우측 상단 + 버튼을 눌러 추가하세요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _memos.length,
              itemBuilder: (context, index) {
                final memo = _memos[index];
                return Card(
                  color: const Color(0xFFF5F5F5),
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text(
                      memo.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          memo.content.isEmpty
                              ? '(내용 없음)'
                              : memo.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          memo.updatedAt != null
                              ? '수정: ${memo.updatedAt!.year}-${memo.updatedAt!.month.toString().padLeft(2, '0')}-${memo.updatedAt!.day.toString().padLeft(2, '0')} ${memo.updatedAt!.hour.toString().padLeft(2, '0')}:${memo.updatedAt!.minute.toString().padLeft(2, '0')}'
                              : '작성: ${memo.createdAt.year}-${memo.createdAt.month.toString().padLeft(2, '0')}-${memo.createdAt.day.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: memo.updatedAt != null ? Colors.blue : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    isThreeLine: true,
                    onTap: () => _showMemoDetail(memo),
                  ),
                );
              },
            ),
    );
  }
}
