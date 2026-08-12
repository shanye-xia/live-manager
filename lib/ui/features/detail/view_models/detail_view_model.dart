import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/photo_item.dart';

/// 删除操作结果。
enum DeleteOutcome { done, needPermission, videoOnly, failed }

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
  String? _videoError;
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
  String? get videoError => _videoError;

  Future<void> init() async {
    // 缩略图与原图并行加载：谁先就绪先显示谁，避免互相阻塞
    unawaited(_loadFullContent());
    final thumb = thumbnailPath;
    if (thumb != null && thumb.isNotEmpty) {
      _showThumb(thumb);
    } else {
      try {
        final path =
            await (thumbnailFuture ?? repository.thumbnailPathFor(item));
        if (!_fullImageReady && path.isNotEmpty) _showThumb(path);
      } catch (_) {
        // 缩略图失败不阻塞原图加载
      }
    }
  }

  void _showThumb(String path) {
    if (_fullImageReady) {
      return; // already showing original, never downgrade to thumb
    }
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

    // Show original as soon as its path is ready; do not wait for video/EXIF.
    if (fullPath != null && fullPath.isNotEmpty) {
      _imagePath = fullPath;
      _fullImageReady = true;
      _loading = false;
      notifyListeners();
    }

    if (item.canPlayLiveVideo) {
      try {
        videoPath = await repository.videoFilePathFor(item);
      } catch (e) {
        _videoError = e.toString();
        // 视频不可用不影响看图与 EXIF
      }
    }
    try {
      exif = await repository.exifFor(item);
    } catch (_) {
      // EXIF 缺失仅影响信息展示
    }

    _videoPath = videoPath;
    _exif = exif;
    _loading = false;
    notifyListeners();

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
    } catch (e) {
      _videoError = e.toString();
      notifyListeners();
      // 忽略：视频不可用时仍可查看静态图
    }
  }

  Future<void> startPlayback() async {
    var controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      // 视频仍在后台加载：最多等 3 秒就绪后播放
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
        controller = _controller;
        if (controller != null && controller.value.isInitialized) break;
      }
    }
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

  Future<void> share() => repository.share(item);

  Future<bool> updateExif(Map<String, String> values) async {
    if (_busy) return false;
    _busy = true;
    try {
      final ok = await repository.updateExif(item, values);
      if (ok) {
        try {
          _exif = await repository.exifFor(item);
          notifyListeners();
        } catch (_) {}
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<bool> clearSensitiveExif(List<String> groups) async {
    if (_busy) return false;
    _busy = true;
    try {
      final ok = await repository.clearSensitiveExif(item, groups);
      if (ok) {
        try {
          _exif = await repository.exifFor(item);
          notifyListeners();
        } catch (_) {
          _exif = const {};
          notifyListeners();
        }
      }
      return ok;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }

  /// 把动态视频（或非 Live 照片）移入应用回收站。
  Future<DeleteOutcome> startDelete({bool videoOnly = true}) async {
    if (_busy) return DeleteOutcome.failed;
    if (videoOnly && item.isLive && !item.canDeleteLivePart) {
      return DeleteOutcome.failed;
    }
    _busy = true;
    try {
      if (item.canDeleteLivePart && !videoOnly) {
        final videoPlan = await repository
            .moveToTrash(item, deleteVideo: true)
            .timeout(const Duration(seconds: 30));
        if (videoPlan['status'] != 'ok') {
          return videoPlan['status'] == 'need_permission'
              ? DeleteOutcome.needPermission
              : DeleteOutcome.failed;
        }
        final imagePlan = await repository
            .moveToTrash(item, deleteVideo: false)
            .timeout(const Duration(seconds: 30));
        if (imagePlan['status'] == 'ok') return DeleteOutcome.done;
        return DeleteOutcome.videoOnly;
      }
      final plan = await repository
          .moveToTrash(item, deleteVideo: item.canDeleteLivePart && videoOnly)
          .timeout(const Duration(seconds: 30));
      return switch (plan['status']) {
        'ok' => DeleteOutcome.done,
        'need_permission' => DeleteOutcome.needPermission,
        _ => DeleteOutcome.failed,
      };
    } catch (_) {
      return DeleteOutcome.failed;
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
