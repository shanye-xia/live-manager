import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/live_photo.dart';

/// 详情页 ViewModel：加载大图/视频/EXIF，并控制长按播放状态。
class DetailViewModel extends ChangeNotifier {
  DetailViewModel({required this.item, required this.repository});

  final LivePhoto item;
  final LivePhotoRepository repository;

  bool _loading = true;
  String? _imagePath;
  String? _videoPath;
  Map<String, dynamic>? _exif;
  String? _error;
  VideoPlayerController? _controller;
  bool _playing = false;

  bool get loading => _loading;
  String? get imagePath => _imagePath;
  Map<String, dynamic>? get exif => _exif;
  String? get error => _error;
  VideoPlayerController? get controller => _controller;
  bool get isPlaying => _playing;
  bool get videoReady => _controller?.value.isInitialized ?? false;

  Future<void> init() async {
    try {
      final results = await Future.wait<Object?>([
        repository.fullImagePathFor(item),
        repository.videoFilePathFor(item),
        repository.exifFor(item),
      ]);
      _imagePath = results[0] as String;
      _videoPath = results[1] as String;
      _exif = results[2] as Map<String, dynamic>?;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();

    // 预加载视频控制器：长按时可立即播放（静默失败，不影响看图）。
    final videoPath = _videoPath;
    if (videoPath == null || videoPath.isEmpty) return;
    try {
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      _controller = controller;
      notifyListeners();
    } catch (_) {
      // 忽略：视频不可用时仍可查看静态图
    }
  }

  Future<void> startPlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.seekTo(Duration.zero);
    await controller.play();
    _playing = true;
    notifyListeners();
  }

  Future<void> stopPlayback() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.pause();
    _playing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
