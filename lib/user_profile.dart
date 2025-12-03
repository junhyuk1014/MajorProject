import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
    static const String _prefKey = 'global_ef';
    double globalEf;
    final double _learningRate = 0.05;

    UserProfile({
        this.globalEf = 2.0,
    });

    Future<void> load() async {
        final prefs = await SharedPreferences.getInstance();
        globalEf = prefs.getDouble(_prefKey) ?? 2.0;
        print('UserProfile Loaded: Global EF = $globalEf');
    }

    Future<void> save() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(_prefKey, globalEf);
        print('UserProfile Saved: Global EF = $globalEf');
    }

    Future<void> updateUserEf(double newItemEf) async {
        globalEf = (globalEf * (1.0 - _learningRate)) + (newItemEf * _learningRate);
        globalEf = max(1.3, globalEf);
        await save();
    }
}