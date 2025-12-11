import 'feedback_module.dart';
import 'memory_item.dart';
import 'user_profile.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'memo_model.dart';    


void testLogic() {
    final feedbackModule = FeedbackModule();

    UserProfile user = UserProfile(globalEf: 2.0);
    print('--- 앱 시작: User Global EF = ${user.globalEf.toStringAsFixed(2)} ---');

    MemoryItem itemA = MemoryItem.initial(
        id: 'item-A',
        content: 'Flutter 공부',
        initialEf: user.globalEf,
    );
    print('항목 A 생성: EF=${itemA.ef.toStringAsFixed(2)}, Interval=${itemA.interval}일, Reps=${itemA.repetitions}');

    MemoryItem updatedItemA = feedbackModule.schedule(itemA, 5);
    print('항목 A (q=5): EF=${updatedItemA.ef.toStringAsFixed(2)}, Interval=${updatedItemA.interval}일, Reps=${updatedItemA.repetitions}');

    user.updateUserEf(updatedItemA.ef);
    print('--- 갱신: User Global EF = ${user.globalEf.toStringAsFixed(2)} ---');


    updatedItemA = feedbackModule.schedule(updatedItemA, 5);
    print('항목 A (q=5): EF=${updatedItemA.ef.toStringAsFixed(2)}, Interval=${updatedItemA.interval}일, Reps=${updatedItemA.repetitions}');

    user.updateUserEf(updatedItemA.ef);
    print('--- 갱신: User Global EF = ${user.globalEf.toStringAsFixed(2)} ---');

    updatedItemA = feedbackModule.schedule(updatedItemA, 5);
    print('항목 A (q=5): EF=${updatedItemA.ef.toStringAsFixed(2)}, Interval=${updatedItemA.interval}일, Reps=${updatedItemA.repetitions}');

    user.updateUserEf(updatedItemA.ef);
    print('--- 갱신: User Global EF = ${user.globalEf.toStringAsFixed(2)} ---');

    updatedItemA = feedbackModule.schedule(updatedItemA, 2);
    print('항목 A (q=2): EF=${updatedItemA.ef.toStringAsFixed(2)}, Interval=${updatedItemA.interval}일, Reps=${updatedItemA.repetitions}');

    user.updateUserEf(updatedItemA.ef);
    print('--- 갱신: User Global EF = ${user.globalEf.toStringAsFixed(2)} ---');
}



// 기초 영단어 100개 샘플 (단어: 뜻)
const Map<String, String> _sampleWords = {
  'ability': '능력', 'able': '할 수 있는', 'about': '대하여', 'above': '위에', 'accept': '받아들이다',
  'accident': '사고', 'accord': '일치하다', 'account': '계좌, 설명', 'across': '건너서', 'act': '행동하다',
  'action': '행동', 'actual': '실제의', 'add': '더하다', 'address': '주소', 'admit': '인정하다',
  'adopt': '채택하다', 'adult': '성인', 'advance': '나아가다', 'advice': '충고', 'affair': '사건',
  'afraid': '두려워하는', 'after': '후에', 'again': '다시', 'against': '반대하여', 'age': '나이',
  'agency': '대리점', 'agent': '대리인', 'ago': '이전에', 'agree': '동의하다', 'agreement': '동의',
  'ahead': '앞에', 'air': '공기', 'all': '모두', 'allow': '허락하다', 'almost': '거의',
  'alone': '홀로', 'along': '따라서', 'already': '이미', 'also': '또한', 'although': '비록 ~일지라도',
  'always': '항상', 'amazing': '놀라운', 'ambition': '야망', 'amount': '양', 'analysis': '분석',
  'ancestor': '조상', 'ancient': '고대의', 'and': '그리고', 'anger': '분노', 'angle': '각도',
  'animal': '동물', 'announce': '발표하다', 'answer': '대답', 'anxiety': '불안', 'any': '어떤',
  'apart': '떨어져', 'appeal': '호소하다', 'appear': '나타나다', 'apple': '사과', 'apply': '적용하다',
  'appoint': '임명하다', 'approach': '접근하다', 'approve': '승인하다', 'area': '지역', 'argue': '논쟁하다',
  'arm': '팔', 'army': '군대', 'around': '주위에', 'arrive': '도착하다', 'art': '예술',
  'article': '기사', 'artist': '예술가', 'as': '~로서', 'ask': '묻다', 'aspect': '측면',
  'assist': '돕다', 'assume': '가정하다', 'at': '~에', 'attack': '공격하다', 'attempt': '시도하다',
  'attend': '참석하다', 'attention': '주의', 'attitude': '태도', 'attract': '끌다', 'audience': '청중',
  'aunt': '이모, 고모', 'author': '저자', 'authority': '권위', 'auto': '자동차', 'available': '이용 가능한',
  'average': '평균', 'avoid': '피하다', 'awake': '깨어있는', 'award': '상', 'aware': '알고 있는',
  'away': '멀리', 'baby': '아기', 'back': '뒤', 'bad': '나쁜', 'bag': '가방'
};

Future<void> injectEnglishWords200() async {
  final prefs = await SharedPreferences.getInstance();

  List<String> memoJsonList = [];       // 메모 화면용 리스트
  List<String> alarmJsonList = [];      // 알림/통계용 리스트

  final List<String> words = _sampleWords.keys.toList();
  final int baseTime = DateTime.now().millisecondsSinceEpoch;

  for (int i = 0; i < 200; i++) {
    String word = words[i % words.length];
    String meaning = _sampleWords[word]!;

    // 101번째부터는 (2) 붙임
    String displayWord = i < 100 ? word : '$word (${(i ~/ 100) + 1})';
    String memoId = '${baseTime}_$i'; // 고유 ID

    // 1. 메모 모델 생성 (화면 표시용)
    final memo = Memo(
      id: memoId,
      title: displayWord,
      content: '뜻: $meaning',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 2. 알림 아이템 생성 (알고리즘용)
    // ID 앞에 'MEMO_'를 붙여야 통계 화면에서 인식함
    final alarmItem = MemoryItem(
      id: 'MEMO_$memoId',
      content: '[메모] $displayWord\n뜻: $meaning',
      ef: 2.5,
      interval: 0,
      repetitions: 0,
      nextReviewDate: DateTime.now(), // 즉시 알림
    );

    memoJsonList.add(jsonEncode(memo.toJson()));
    alarmJsonList.add(jsonEncode(alarmItem.toJson()));
  }

  // 두 저장소 모두 업데이트
  await prefs.setStringList('memos', memoJsonList);        // 메모장 화면
  await prefs.setStringList('memory_items', alarmJsonList); // 알림 & 대시보드

  print("✅ 영단어 200개 (화면용 + 알림용) 완벽 주입 완료!");
}

