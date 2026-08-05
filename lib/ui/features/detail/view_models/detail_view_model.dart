import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/photo_item.dart';

/// 详情页 ViewModel：加载大图/视频/EXIF，并处理删除（移入应用回收站）。
class DetailViewModel extends ChangeNotifier {
  DetailViewModel({
    required this.item,
    required this.repository,
    this.thumbnailPath,
    this.thumbnailFuture,
  });

  final PhotoItem item;
  final LivePhotoRepository repository;
  final String? thumbnailPath;
  final Future<String>? thumbnailFuture;

  bool _loading = true;
  String? _imagePath;
  String? _videoPath;
  Map<String, dynamic>? _exif;
  String? _error;
  VideoPlayerController? _controller;
  bool _playing = false;
  bool _fullImageReady = false;
  String? _fullImageError;
  StreamSubscription<Map<String, dynamic>>? _deleteSub;
  Completer<bool>? _deleteCompleter;
  bool _busy = false;

  bool get loading => _loading;
  String? get imagePath => _imagePath;
  Map<String, dynamic>? get exif => _exif;
  String? get error => _error;
  VideoPlayerController? get controller => _controller;
  bool get isPlaying => _playing;
  bool get videoReady => _controller?.value.isInitialized ?? false;
  bool get fullImageReady => _fullImageReady;
  String? get fullImageError => _fullImageError;

  Future<void> init() async {
    // 第一帧必有图：已有缩略图直接显示，否则等缩略图 Future。
    final thumb = thumbnailPath;
    if (thumb != null && thumb.isNotEmpty) {
      _showThumb(thumb);
    } else if (thumbnailFuture != null) {
      thumbnailFuture!
          .then((path) {
            if (!_fullImageReady && path.isNotEmpty) _showThumb(path);
          })
          .catchError((_) {});
    }

    await _loadFullContent();
  }

  void _showThumb(String path) {
    _imagePath = path;
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadFullContent() async {
    String? fullPath;
    String? videoPath;
    Map<String, dynamic>? exif;
    try {
      fullPath = await repository.fullImagePathFor(item);
    } catch (e) {
      _error = e.toString();
      _fullImageError = e.toString();
    }
    if (item.isLive) {
      try {
        videoPath = await repository.videoFilePathFor(item);
      } catch (_) {
        // 视频不可用不影响看图与 EXIF
      }
    }
    try {
      exif = await repository.exifFor(item);
    } catch (_) {
      // EXIF 缺失仅影响信息展示
    }

    if (fullPath != null && fullPath.isNotEmpty) {
      _imagePath = fullPath;
      _fullImageReady = true;
    }
    _videoPath = videoPath;
    _exif = exif;
    _loading = false;
    notifyListeners();

    // 预加载视频控制器：长按时可立即播放（仅 Live 照片）。
    if (_videoPath == null || _videoPath!.isEmpty) return;
    try {
      final controller = VideoPlayerController.file(File(_videoPath!));
      await controller.initialize();
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

  /// 把动态视频（或非 Live 照片）移入应用回收站。
  /// 返回 true 表示已移入回收站，false 表示取消或失败。
  Future<bool> startDelete() async {
    if (_busy) return false;
    _busy = true;
    try {
      // 先建立事件监听（系统确认结果通过事件回传）
      final completer = Completer<bool>();
      _deleteCompleter = completer;
      _deleteSub ??= repository.events().listen((event) {
        if (event['type'] == 'deleteResult') {
          final target = _deleteCompleter;
          if (target != null && !target.isCompleted) {
            target.complete(event['success'] == true);
          }
        }
      });

      final plan = await repository
          .moveToTrash(item, deleteVideo: item.isLive)
          .timeout(const Duration(seconds: 30));
      if (plan['needsConsent'] == true) {
        final ok = await completer.future
            .timeout(const Duration(minutes: 2), onTimeout: () => false);
        return ok;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      _deleteCompleter = null;
      _busy = false;
    }
  }

  @override
  void dispose() {
    _deleteSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}
