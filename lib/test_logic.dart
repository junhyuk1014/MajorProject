import 'feedback_module.dart';
import 'memory_item.dart';
import 'user_profile.dart';

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

