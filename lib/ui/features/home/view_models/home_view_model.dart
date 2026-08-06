import 'package:flutter/foundation.dart';

import '../../../../data/repositories/live_photo_repository.dart';
import '../../../../domain/models/photo_item.dart';

enum HomeStatus { initial, loading, ready, error }

/// 批量删除结果统计。
class BatchDeleteResult {
  const BatchDeleteResult({
    required this.deleted,
    required this.videoOnly,
    required this.failed,
  });

  final int deleted;
  final int videoOnly;
  final int failed;
}

/// 首页 ViewModel：管理扫描状态、照片列表与缩略图缓存。
class HomeViewModel extends ChangeNotifier {
  HomeViewModel({required this.repository});

  final LivePhotoRepository repository;

  HomeStatus _status = HomeStatus.initial;
  List<PhotoItem> _items = const [];
  String? _error;
  final Map<int, Future<String>> _thumbnailFutures = {};
  final Map<int, String> _thumbnailPaths = {};
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  int _selectedLiveCount = 0;

  HomeStatus get status => _status;
  List<PhotoItem> get items => _items;
  String? get error => _error;
  bool get selectionMode => _selectionMode;
  int get selectedCount => _selectedIds.length;
  Set<int> get selectedIds => Set.unmodifiable(_selectedIds);
  int get selectedLiveCount => _selectedLiveCount;
  bool get hasLiveSelected => _selectedLiveCount > 0;

  int get totalBytes =>
      _items.fold<int>(0, (sum, item) => sum + item.totalSize);

  int get liveCount => _items.where((item) => item.isLive).length;

  int get liveImageTotalBytes => _items
      .where((item) => item.isLive)
      .fold<int>(0, (sum, item) => sum + item.imageSize);

  int get liveVideoTotalBytes => _items
      .where((item) => item.isLive)
      .fold<int>(0, (sum, item) => sum + (item.videoSize ?? 0));

  bool get allVisibleSelected {
    return _items.isNotEmpty &&
        _items.every((e) => _selectedIds.contains(e.imageId));
  }

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

  // ---- 多选 ----

  void enterSelectionMode(PhotoItem item) {
    _selectionMode = true;
    if (_selectedIds.add(item.imageId) && item.isLive) {
      _selectedLiveCount++;
    }
    notifyListeners();
  }

  /// 滑动多选：把指定项设置成选中/取消（无变化时不通知，避免无谓重建）。
  void setSelection(PhotoItem item, {required bool selected}) {
    if (!_selectionMode) return;
    final contains = _selectedIds.contains(item.imageId);
    if (selected == contains) return;
    if (selected) {
      _selectedIds.add(item.imageId);
      if (item.isLive) _selectedLiveCount++;
    } else {
      _selectedIds.remove(item.imageId);
      if (item.isLive) _selectedLiveCount--;
    }
    notifyListeners();
  }

  void toggleSelection(PhotoItem item) {
    if (!_selectionMode) return;
    if (!_selectedIds.add(item.imageId)) {
      _selectedIds.remove(item.imageId);
      if (item.isLive) _selectedLiveCount--;
    } else if (item.isLive) {
      _selectedLiveCount++;
    }
    notifyListeners();
  }

  void toggleSelectAllVisible() {
    if (allVisibleSelected) {
      _selectedIds.clear();
      _selectedLiveCount = 0;
    } else {
      _selectedIds.addAll(_items.map((e) => e.imageId));
      _selectedLiveCount = _items.where((e) => e.isLive).length;
    }
    notifyListeners();
  }

  void exitSelectionMode() {
    _selectionMode = false;
    _selectedIds.clear();
    _selectedLiveCount = 0;
    notifyListeners();
  }

  /// 批量删除：Live 先删视频再删图片；失败项保持原状，部分成功则降级为非 Live。
  /// 删除后原地更新列表，不重新扫描、不重置滚动位置。
  Future<BatchDeleteResult> deleteSelected() async {
    final targets = _items
        .where((e) => _selectedIds.contains(e.imageId))
        .toList();
    var deleted = 0;
    var videoOnly = 0;
    var failed = 0;
    final deletedIds = <int>{};
    final videoOnlyIds = <int>{};

    for (final item in targets) {
      try {
        if (item.isLive) {
          final videoResult = await repository.moveToTrash(
            item,
            deleteVideo: true,
          );
          if (videoResult['status'] != 'ok') {
            failed++;
            continue;
          }
          final imageResult = await repository.moveToTrash(
            item,
            deleteVideo: false,
          );
          if (imageResult['status'] == 'ok') {
            deleted++;
            deletedIds.add(item.imageId);
          } else {
            videoOnly++;
            videoOnlyIds.add(item.imageId);
          }
        } else {
          final imageResult = await repository.moveToTrash(
            item,
            deleteVideo: false,
          );
          if (imageResult['status'] == 'ok') {
            deleted++;
            deletedIds.add(item.imageId);
          } else {
            failed++;
          }
        }
      } catch (_) {
        failed++;
      }
    }

    if (deletedIds.isNotEmpty || videoOnlyIds.isNotEmpty) {
      final newItems = <PhotoItem>[];
      for (final item in _items) {
        if (deletedIds.contains(item.imageId)) {
          _thumbnailFutures.remove(item.imageId);
          _thumbnailPaths.remove(item.imageId);
          continue;
        }
        if (videoOnlyIds.contains(item.imageId)) {
          newItems.add(
            PhotoItem(
              imageId: item.imageId,
              imageUri: item.imageUri,
              displayName: item.displayName,
              createTime: item.createTime,
              imageSize: item.imageSize,
              relativePath: item.relativePath,
              isLive: false,
            ),
          );
          continue;
        }
        newItems.add(item);
      }
      _items = newItems;
    }
    _selectionMode = false;
    _selectedIds.clear();
    _selectedLiveCount = 0;
    notifyListeners();
    return BatchDeleteResult(
      deleted: deleted,
      videoOnly: videoOnly,
      failed: failed,
    );
  }

  /// 批量仅删除选中 Live 图的动态视频：照片保留并去掉 LIVE 标记，
  /// 普通照片不受影响。删除后原地更新列表、保持滚动位置。
  Future<BatchDeleteResult> deleteLiveParts() async {
    final targets = _items
        .where((e) => _selectedIds.contains(e.imageId) && e.isLive)
        .toList();
    var videoOnly = 0;
    var failed = 0;
    final videoOnlyIds = <int>{};
    for (final item in targets) {
      try {
        final result = await repository.moveToTrash(item, deleteVideo: true);
        if (result['status'] == 'ok') {
          videoOnly++;
          videoOnlyIds.add(item.imageId);
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }
    if (videoOnlyIds.isNotEmpty) {
      _items = [
        for (final item in _items)
          if (videoOnlyIds.contains(item.imageId))
            PhotoItem(
              imageId: item.imageId,
              imageUri: item.imageUri,
              displayName: item.displayName,
              createTime: item.createTime,
              imageSize: item.imageSize,
              relativePath: item.relativePath,
              isLive: false,
            )
          else
            item,
      ];
    }
    _selectionMode = false;
    _selectedIds.clear();
    _selectedLiveCount = 0;
    notifyListeners();
    return BatchDeleteResult(
      deleted: 0,
      videoOnly: videoOnly,
      failed: failed,
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
