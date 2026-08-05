import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/live_photo.dart';

/// 详情页 ViewModel：加载大图/视频/EXIF，并控制长按播放状态。
class DetailViewModel extends ChangeNotifier {
  DetailViewModel({
    required this.item,
    required this.repository,
    this.thumbnailPath,
  });

  final LivePhoto item;
  final LivePhotoRepository repository;
  final String? thumbnailPath;

  bool _loading = true;
  String? _imagePath;
  String? _videoPath;
  Map<String, dynamic>? _exif;
  String? _error;
  VideoPlayerController? _controller;
  bool _playing = false;
  bool _fullImageReady = false;

  bool get loading => _loading;
  String? get imagePath => _imagePath;
  Map<String, dynamic>? get exif => _exif;
  String? get error => _error;
  VideoPlayerController? get controller => _controller;
  bool get isPlaying => _playing;
  bool get videoReady => _controller?.value.isInitialized ?? false;
  bool get fullImageReady => _fullImageReady;

  Future<void> init() async {
    // 先展示已有缩略图，秒开详情页；原图/视频/EXIF 在后台加载。
    final thumb = thumbnailPath;
    if (thumb != null && thumb.isNotEmpty) {
      _imagePath = thumb;
      _loading = false;
      notifyListeners();
    }

    await _loadFullContent();
  }

  Future<void> _loadFullContent() async {
    String? fullPath;
    String? videoPath;
    Map<String, dynamic>? exif;
    try {
      final results = await Future.wait<Object?>([
        repository.fullImagePathFor(item),
        repository.videoFilePathFor(item),
        repository.exifFor(item),
      ]);
      fullPath = results[0] as String;
      videoPath = results[1] as String;
      exif = results[2] as Map<String, dynamic>?;
    } catch (e) {
      _error = e.toString();
    }

    if (fullPath != null && fullPath.isNotEmpty) {
      _imagePath = fullPath;
      _fullImageReady = true;
    }
    _videoPath = videoPath;
    _exif = exif;
    _loading = false;
    notifyListeners();

    // 预加载视频控制器：长按时可立即播放（静默失败，不影响看图）。
    if (_videoPath == null || _videoPath!.isEmpty) return;
    try {
      final controller = VideoPlayerController.file(File(_videoPath!));
      await controller.initialize();
      // 视频播放到结尾时回到静态图，避免停在最后一帧
      controller.addListener(() {
        if (controller.value.isCompleted && _playing) {
          stopPlayback();
        }
      });
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
