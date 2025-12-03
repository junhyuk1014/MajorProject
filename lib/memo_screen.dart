import 'dart:convert';
import 'dart:io'; // 파일 처리를 위해 추가

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart'; // 이미지 선택
import 'package:path_provider/path_provider.dart'; // 경로 획득
import 'package:path/path.dart' as p; // 경로 조작

import 'memo_model.dart';
import 'alarm_module.dart';
import 'memory_item.dart';
import 'user_profile.dart';

class MemoScreen extends StatefulWidget {
  const MemoScreen({super.key});

  @override
  State<MemoScreen> createState() => _MemoScreenState();
}

class _MemoScreenState extends State<MemoScreen> {
  List<Memo> _memos = [];
  final AlarmService _alarmService = AlarmService();
  final UserProfile _userProfile = UserProfile();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadMemos();
  }

  Future<void> _loadUserProfile() async {
    await _userProfile.load();
  }

  Future<void> _loadMemos() async {
    final prefs = await SharedPreferences.getInstance();
    final memosJson = prefs.getStringList('memos') ?? [];

    setState(() {
      _memos = memosJson
          .map((json) => Memo.fromJson(jsonDecode(json)))
          .toList()
        ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    });
  }

  Future<void> _saveMemos() async {
    final prefs = await SharedPreferences.getInstance();
    final memosJson = _memos.map((memo) => jsonEncode(memo.toJson())).toList();
    await prefs.setStringList('memos', memosJson);
  }

  Future<String?> _pickAndSaveImage() async {
    try {
      final picker = ImagePicker();
      final XFile? picked =
      await picker.pickImage(source: ImageSource.gallery);

      if (picked == null) return null;

      final appDir = await getApplicationDocumentsDirectory();
      final fileName =
          'memo_img_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}';
      final savedPath = p.join(appDir.path, fileName);
      await File(picked.path).copy(savedPath);
      return savedPath;
    } catch (e) {
      return null;
    }
  }

  Future<void> _showAddMemoDialog() async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    String? tempImagePath;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('메모 추가'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '제목',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    decoration: const InputDecoration(
                      labelText: '내용',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                  ),
                  const SizedBox(height: 16),

                  if (tempImagePath != null)
                    Stack(
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

                  const SizedBox(height: 8),
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (titleController.text.trim().isNotEmpty) {
                    Navigator.of(dialogContext).pop(true);
                  }
                },
                child: const Text('추가하기'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final newMemo = Memo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: titleController.text.trim(),
        content: contentController.text.trim(),
        createdAt: DateTime.now(),
        imagePath: tempImagePath,
      );

      setState(() {
        _memos.insert(0, newMemo);
        _memos.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      });

      await _saveMemos();
      await _alarmService.saveMemo(newMemo, _userProfile);
    }
  }

  Future<void> _handleFeedback(Memo memo, int score) async {
    await _alarmService.processFeedback('MEMO_${memo.id}', score);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showMemoDetail(Memo memo) {
    final memoIndex = _memos.indexWhere((m) => m.id == memo.id);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(memo.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (memo.imagePath != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(memo.imagePath!),
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
                ),
              Text(
                memo.content.isEmpty ? '(내용 없음)' : memo.content,
                style: const TextStyle(fontSize: 16),
              ),
              const Divider(height: 32),
              StreamBuilder<void>(
                stream: AlarmService.dataUpdateStream.stream,
                builder: (context, _) {
                  return FutureBuilder<MemoryItem?>(
                    future: _alarmService.getMemoryItem('MEMO_${memo.id}'),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const SizedBox.shrink();
                      }

                      final item = snapshot.data!;
                      final isDue =
                      DateTime.now().isAfter(item.nextReviewDate);

                      if (!isDue) {
                        return Center(
                          child: Text(
                            '복습 완료\n다음: ${item.nextReviewDate.toString().split('.')[0]}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.blueGrey,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          const Text(
                            '복습 시간입니다!',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildFeedbackBtn('다시(1)', 1, Colors.red, memo),
                              _buildFeedbackBtn('보통(3)', 3, Colors.blue, memo),
                              _buildFeedbackBtn('완벽(5)', 5, Colors.green, memo),
                            ],
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
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
              Navigator.of(dialogContext).pop();
              _showEditMemoDialog(memo, memoIndex);
            },
            child: const Text('수정'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackBtn(
      String text, int score, Color color, Memo memo) {
    return ElevatedButton(
      onPressed: () => _handleFeedback(memo, score),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 36),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Future<void> _showEditMemoDialog(Memo memo, int index) async {
    final titleController = TextEditingController(text: memo.title);
    final contentController = TextEditingController(text: memo.content);
    String? tempImagePath = memo.imagePath;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('메모 수정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '제목',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    decoration: const InputDecoration(
                      labelText: '내용',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 5,
                  ),
                  const SizedBox(height: 16),
                  if (tempImagePath != null)
                    Stack(
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
                  const SizedBox(height: 8),
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (titleController.text.trim().isNotEmpty) {
                    Navigator.of(dialogContext).pop(true);
                  }
                },
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final updatedMemo = Memo(
        id: memo.id,
        title: titleController.text.trim(),
        content: contentController.text.trim(),
        createdAt: memo.createdAt,
        updatedAt: DateTime.now(),
        imagePath: tempImagePath,
      );

      setState(() {
        _memos[index] = updatedMemo;
        _memos.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      });

      await _saveMemos();
      await _alarmService.saveMemo(updatedMemo, _userProfile);
    }
  }

  void _showDeleteConfirmDialog(Memo memo, int index) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('메모 삭제'),
        content: const Text('삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              setState(() {
                _memos.removeAt(index);
              });
              await _saveMemos();
              await _alarmService.deleteMemo(memo.id);

              if (context.mounted) {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
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
          )
        ],
      ),
      body: _memos.isEmpty
          ? const Center(
        child: Text(
          '메모가 없습니다.',
          style: TextStyle(color: Colors.grey),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _memos.length,
        itemBuilder: (context, index) {
          final memo = _memos[index];
          return Card(
            color: const Color(0xFFF5F5F5),
            child: ListTile(
              leading: memo.imagePath != null
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(
                  File(memo.imagePath!),
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
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
                  },
                ),
              )
                  : null,
              title: Text(
                memo.title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                memo.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _showMemoDetail(memo),
            ),
          );
        },
      ),
    );
  }
}
