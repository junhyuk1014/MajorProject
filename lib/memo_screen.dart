import 'package:flutter/material.dart';

class MemoScreen extends StatelessWidget {
  const MemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('메모'),
      ),
      body: const Center(
        child: Text('메모 화면'),
      ),
    );
  }
}

