import 'dart:math';
import 'memory_item.dart';

class FeedbackModule {
    MemoryItem schedule(MemoryItem item, int q) {
        assert(q >= 0 && q <= 5, 'Feedback quality (q) must be between 0 and 5.');

        double oldEF = item.ef;
        double qDouble = q.toDouble();
        double newEF =
            oldEF + (0.1 - (5.0 - qDouble) * (0.08 + (5.0 - qDouble) * 0.02));

        newEF = max(1.3, newEF);

        int newRepetitions;
        int newInterval;

        if (q < 3) {
            newRepetitions = item.repetitions;

            int newIntervalCalc = (item.interval * 0.5).round();
            newInterval = max(1, newIntervalCalc);

        } else {
            newRepetitions = item.repetitions + 1;

            if (item.interval == 0) {
                newInterval = 1;
            } else {
                newInterval = (item.interval * newEF).round();
            }

            if (newInterval < 1) {
                newInterval = 1;
            }
        }

        DateTime newNextReviewDate = DateTime.now().add(Duration(seconds: newInterval*10));

        return item.copyWith(
            ef: newEF,
            interval: newInterval,
            repetitions: newRepetitions,
            nextReviewDate: newNextReviewDate,
        );
    }
}
