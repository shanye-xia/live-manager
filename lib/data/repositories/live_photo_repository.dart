import '../../domain/models/live_photo.dart';
import '../services/live_photo_platform_service.dart';

/// 媒体读取权限被拒绝时抛出。
class PermissionDeniedException implements Exception {
  const PermissionDeniedException();

  @override
  String toString() => '需要相册读取权限才能扫描 Live 图片';
}

/// Live Photo 数据仓库：数据层的单一入口。
abstract class LivePhotoRepository {
  /// 请求权限并扫描全部 Live 图片（只读）。
  Future<List<LivePhoto>> scan();

  /// 获取（并缓存）某条 Live Photo 的缩略图文件路径。
  Future<String> thumbnailPathFor(LivePhoto item);

  /// 获取原始图片的本地缓存路径（详情页大图）。
  Future<String> fullImagePathFor(LivePhoto item);

  /// 获取动态视频的本地缓存路径（长按播放）。
  Future<String> videoFilePathFor(LivePhoto item);

  /// 读取 JPG 的 EXIF 信息。
  Future<Map<String, dynamic>> exifFor(LivePhoto item);
}

/// 基于 MediaStore 原生桥接的实现。
class MediaStoreLivePhotoRepository implements LivePhotoRepository {
  const MediaStoreLivePhotoRepository({LivePhotoPlatformService? service})
      : _service = service ?? const LivePhotoPlatformService();

  final LivePhotoPlatformService _service;

  @override
  Future<List<LivePhoto>> scan() async {
    final permission = await _service.requestPermissions();
    if (permission['granted'] != true) {
      throw const PermissionDeniedException();
    }
    final maps = await _service.scanLivePhotos();
    return maps.map(LivePhoto.fromJson).toList();
  }

  @override
  Future<String> thumbnailPathFor(LivePhoto item) {
    return _service.getThumbnail(
      imageId: item.imageId,
      imageUri: item.imageUri,
      size: 512,
    );
  }

  @override
  Future<String> fullImagePathFor(LivePhoto item) {
    return _service.getFullImage(
      imageId: item.imageId,
      imageUri: item.imageUri,
    );
  }

  @override
  Future<String> videoFilePathFor(LivePhoto item) {
    return _service.getVideoFile(
      videoId: item.videoId,
      videoUri: item.videoUri,
    );
  }

  @override
  Future<Map<String, dynamic>> exifFor(LivePhoto item) {
    return _service.getExif(item.imageUri);
  }
}
