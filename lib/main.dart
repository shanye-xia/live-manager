import 'package:flutter/material.dart';

import 'data/repositories/live_photo_repository.dart';
import 'ui/features/home/views/home_shell.dart';

void main() {
  runApp(const LiveManagerApp());
}

class LiveManagerApp extends StatelessWidget {
  const LiveManagerApp({super.key, this.repository});

  /// 可注入的数据仓库（测试时传入 Fake）。
  final LivePhotoRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveKit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0072FF)),
        useMaterial3: true,
      ),
      home: HomeShell(
        repository: repository ?? const MediaStoreLivePhotoRepository(),
      ),
    );
  }
}
