import 'dart:math';

class UserProfile {
  double globalEf;
  final double _learningRate = 0.1;

  UserProfile({
    this.globalEf = 2.0,
  });

  void updateUserEf(double newItemEf) {
    globalEf = (globalEf * (1.0 - _learningRate)) + (newItemEf * _learningRate);
    globalEf = max(1.3, globalEf);
  }
}

