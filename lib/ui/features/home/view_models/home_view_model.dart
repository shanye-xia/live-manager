import 'package:flutter/foundation.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/photo_item.dart';

enum HomeStatus { initial, loading, ready, error }

/// 首页 ViewModel：管理扫描状态、照片列表与缩略图缓存。
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({required this.repository});

  final LivePhotoRepository repository;

  HomeStatus _status = HomeStatus.initial;
  List<PhotoItem> _items = const [];
  String? _error;
  final Map<int, Future<String>> _thumbnailFutures = {};
  final Map<int, String> _thumbnailPaths = {};

  HomeStatus get status => _status;
  List<PhotoItem> get items => _items;
  String? get error => _error;

  int get totalBytes =>
      _items.fold<int>(0, (sum, item) => sum + item.totalSize);

  int get liveCount => _items.where((item) => item.isLive).length;

  int get liveImageTotalBytes => _items
      .where((item) => item.isLive)
      .fold<int>(0, (sum, item) => sum + item.imageSize);

  int get liveVideoTotalBytes => _items
      .where((item) => item.isLive)
      .fold<int>(0, (sum, item) => sum + (item.videoSize ?? 0));

  Future<void> load() async {
    _status = HomeStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final scanned = await repository.scan();
      _items = scanned;
      _thumbnailFutures.clear();
      _status = HomeStatus.ready;
    } catch (e) {
      _error = e.toString();
      _status = HomeStatus.error;
    }
    notifyListeners();
  }

  /// 返回缩略图文件路径（同一 item 只请求一次，Future 记忆化）。
  Future<String> thumbnailPathFor(PhotoItem item) {
    return _thumbnailFutures.putIfAbsent(
      item.imageId,
      () async {
        final path = await repository.thumbnailPathFor(item);
        _thumbnailPaths[item.imageId] = path;
        return path;
      },
    );
  }

  /// 原地应用删除结果（不重新扫描）：动态视频被删则取消 LIVE 标记，
  /// 整张照片被删则从列表移除。保持滚动位置。
  void applyDelete(int imageId, {required bool videoOnly}) {
    if (videoOnly) {
      _items = [
        for (final item in _items)
          if (item.imageId == imageId)
            item.copyWith(
              isLive: false,
              videoId: null,
              videoUri: null,
              videoSize: null,
              videoDurationMs: null,
            )
          else
            item,
      ];
    } else {
      _items = _items.where((item) => item.imageId != imageId).toList();
    }
    _thumbnailFutures.remove(imageId);
    _thumbnailPaths.remove(imageId);
    notifyListeners();
  }

  /// 原地应用恢复结果：视频恢复则把同名 JPG 恢复 LIVE 标记，
  /// 图片恢复则按时间插回列表。不重新扫描、保持滚动位置。
  void applyRestored(Map<String, dynamic> info) {
    final mediaType = info['mediaType'] as String? ?? 'image';
    if (mediaType == 'video') {
      final base = (info['displayName'] as String? ?? '')
          .replaceAll(RegExp(r'\.mp4$'), '');
      final rel = info['relativePath'] as String? ?? '';
      _items = [
        for (final item in _items)
          if (!item.isLive &&
              item.displayName.replaceAll(RegExp(r'\.jpg$'), '') == base &&
              item.relativePath == rel)
            item.copyWith(
              isLive: true,
              videoId: (info['id'] as num?)?.toInt(),
              videoUri: info['uri'] as String?,
              videoSize: (info['size'] as num?)?.toInt(),
              videoDurationMs: (info['durationMs'] as num?)?.toInt(),
            )
          else
            item,
      ];
    } else {
      final item = PhotoItem(
        imageId: (info['id'] as num?)?.toInt() ?? 0,
        imageUri: info['uri'] as String? ?? '',
        displayName: info['displayName'] as String? ?? '',
        createTime: DateTime.fromMillisecondsSinceEpoch(
          (info['dateTaken'] as num?)?.toInt() ?? 0,
        ),
        imageSize: (info['size'] as num?)?.toInt() ?? 0,
        relativePath: info['relativePath'] as String? ?? '',
        isLive: false,
      );
      _items = [..._items, item]
        ..sort((a, b) => b.createTime.compareTo(a.createTime));
    }
    notifyListeners();
  }
}
