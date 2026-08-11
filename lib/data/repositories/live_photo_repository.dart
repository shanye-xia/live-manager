import 'dart:io';

import '../../domain/models/photo_item.dart';
import '../../domain/models/trash_entry.dart';
import '../services/live_photo_platform_service.dart';

/// 媒体读取权限被拒绝时抛出。
class PermissionDeniedException implements Exception {
  const PermissionDeniedException();

  @override
  String toString() => '需要相册读取权限才能扫描照片';
}

/// 数据仓库：数据层的单一入口。
abstract class LivePhotoRepository {
  /// 请求权限并扫描全部照片。
  Future<List<PhotoItem>> scan();

  /// 获取（并缓存）某张照片的缩略图文件路径。
  Future<String> thumbnailPathFor(PhotoItem item);

  /// 获取原始图片的真实文件路径（详情页大图）。
  Future<String> fullImagePathFor(PhotoItem item);

  /// 获取动态视频的真实文件路径（长按播放）。
  Future<String> videoFilePathFor(PhotoItem item);

  /// 读取 JPG 的 EXIF 信息。
  Future<Map<String, dynamic>> exifFor(PhotoItem item);

  /// 调用系统分享面板分享图片。
  Future<void> share(PhotoItem item);

  /// 调用系统分享面板分享多张图片。
  Future<void> shareAll(List<PhotoItem> items);

  /// 更新 EXIF 字段。
  Future<bool> updateExif(PhotoItem item, Map<String, String> values);

  /// 清除 GPS、设备、软件、拍摄时间等敏感 EXIF。
  Future<bool> clearSensitiveExif(PhotoItem item, List<String> groups);

  /// 把动态视频（或非 Live 照片）移入应用回收站。
  /// 返回 {status, entry?}；status 为 ok / need_permission / failed。
  Future<Map<String, dynamic>> moveToTrash(
    PhotoItem item, {
    required bool deleteVideo,
  });

  /// 是否已授予“所有文件访问”权限。
  Future<bool> hasAllFilesAccess();

  /// 打开“所有文件访问”设置页。
  Future<void> openAllFilesAccessSettings();

  /// 尝试用文件管理器打开照片所在目录。
  /// 返回 folder / app / failed。
  Future<String> openFolder(PhotoItem item);

  /// 回收站条目。
  Future<List<TrashEntry>> trashEntries();

  /// 回收站条目的预览图路径。
  Future<String> trashPreviewPath(TrashEntry entry, {int size = 512});

  /// 恢复回收站条目，返回新文件信息（供首页原地更新）。
  Future<Map<String, dynamic>?> restoreTrash(String id);

  /// 彻底删除回收站条目。
  Future<bool> permanentDeleteTrash(String id);

  /// 原生事件流（删除确认结果等）。
  Stream<Map<String, dynamic>> events();
}

/// 基于 MediaStore 原生桥接的实现。
class MediaStoreLivePhotoRepository implements LivePhotoRepository {
  const MediaStoreLivePhotoRepository({LivePhotoPlatformService? service})
      : _service = service ?? const LivePhotoPlatformService();

  final LivePhotoPlatformService _service;

  Future<String> _directStoragePath(
    PhotoItem item, {
    required bool video,
  }) async {
    final relativePath = item.relativePath;
    final fileName = video
        ? '${item.displayName.replaceAll('.jpg', '')}.mp4'
        : item.displayName;
    if (relativePath.isEmpty || fileName.isEmpty) {
      throw const FileSystemException('媒体文件路径为空');
    }
    final path = '/storage/emulated/0/$relativePath$fileName';
    if (await File(path).exists()) return path;
    throw FileSystemException('无法直接读取媒体文件', path);
  }

  @override
  Future<List<PhotoItem>> scan() async {
    final permission = await _service.requestPermissions();
    if (permission['granted'] != true) {
      throw const PermissionDeniedException();
    }
    final maps = await _service.scanAllPhotos();
    return maps.map(PhotoItem.fromJson).toList();
  }

  @override
  Future<String> thumbnailPathFor(PhotoItem item) {
    return _service.getThumbnail(
      imageId: item.imageId,
      imageUri: item.imageUri,
      size: 512,
    );
  }

  @override
  Future<String> fullImagePathFor(PhotoItem item) {
    return _directStoragePath(item, video: false);
  }

  @override
  Future<String> videoFilePathFor(PhotoItem item) {
    return _directStoragePath(item, video: true);
  }

  @override
  Future<Map<String, dynamic>> exifFor(PhotoItem item) {
    return _service.getExif(item.imageUri);
  }

  @override
  Future<void> share(PhotoItem item) {
    return _service.shareImage(item.imageUri);
  }

  @override
  Future<void> shareAll(List<PhotoItem> items) {
    return _service.shareImages(items.map((item) => item.imageUri).toList());
  }

  @override
  Future<bool> updateExif(PhotoItem item, Map<String, String> values) {
    return _service.updateExif(item.imageUri, values);
  }

  @override
  Future<bool> clearSensitiveExif(PhotoItem item, List<String> groups) {
    return _service.clearSensitiveExif(item.imageUri, groups);
  }

  @override
  Future<Map<String, dynamic>> moveToTrash(
    PhotoItem item, {
    required bool deleteVideo,
  }) {
    final uri = deleteVideo ? item.videoUri! : item.imageUri;
    final fileName = deleteVideo
        ? '${item.displayName.replaceAll('.jpg', '')}.mp4'
        : item.displayName;
    return _service.moveToTrash(
      uri: uri,
      fileName: fileName,
      relativePath: item.relativePath,
      mediaType: deleteVideo ? 'video' : 'image',
      dateTaken: item.createTime.millisecondsSinceEpoch,
      imageId: item.imageId,
      videoId: item.videoId,
    );
  }

  @override
  Future<bool> hasAllFilesAccess() => _service.hasAllFilesAccess();

  @override
  Future<void> openAllFilesAccessSettings() =>
      _service.openAllFilesAccessSettings();

  @override
  Future<String> openFolder(PhotoItem item) {
    return _service.openFolder(item.relativePath);
  }

  @override
  Future<List<TrashEntry>> trashEntries() async {
    final maps = await _service.listTrash();
    return maps.map(TrashEntry.fromJson).toList();
  }

  @override
  Future<String> trashPreviewPath(TrashEntry entry, {int size = 512}) {
    return _service.getTrashPreview(id: entry.id, size: size);
  }

  @override
  Future<Map<String, dynamic>?> restoreTrash(String id) =>
      _service.restoreTrash(id);

  @override
  Future<bool> permanentDeleteTrash(String id) =>
      _service.permanentDeleteTrash(id);

  @override
  Stream<Map<String, dynamic>> events() => _service.events();
}
