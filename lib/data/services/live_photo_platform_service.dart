import 'package:flutter/services.dart';

/// 原生桥接客户端（MethodChannel + EventChannel 封装）。
class LivePhotoPlatformService {
  const LivePhotoPlatformService();

  static const MethodChannel _channel = MethodChannel(
    'com.livemanager/live_photo',
  );
  static const EventChannel _events = EventChannel(
    'com.livemanager/live_photo_events',
  );

  /// 冒烟测试：与原生层完成一次通信，返回设备信息。
  Future<Map<String, dynamic>> ping() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('ping');
    return result ?? const {};
  }

  /// 请求媒体读取权限。返回 granted（是否已授权）与 pending（是否弹窗等待）。
  Future<Map<String, dynamic>> requestPermissions() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'requestPermissions',
    );
    return result ?? const {};
  }

  /// 查询当前权限状态。
  Future<Map<String, dynamic>> permissionStatus() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'permissionStatus',
    );
    return result ?? const {};
  }

  /// 扫描并返回全部照片（含 Live 标记）。
  Future<List<Map<String, dynamic>>> scanAllPhotos() async {
    final result = await _channel.invokeListMethod<dynamic>('scanAllPhotos');
    return (result ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// 读取上次扫描留下的轻量照片列表快照；不请求权限、不读取照片文件。
  Future<List<Map<String, dynamic>>> scanSnapshot() async {
    final result = await _channel.invokeListMethod<dynamic>('scanSnapshot');
    return (result ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// 获取（并缓存）缩略图，返回本地缓存文件路径。
  Future<String> getThumbnail({
    required int imageId,
    required String imageUri,
    int size = 512,
  }) async {
    final path = await _channel.invokeMethod<String>('getThumbnail', {
      'imageId': imageId,
      'imageUri': imageUri,
      'size': size,
    });
    return path ?? '';
  }

  /// 从标准单文件 Motion Photo 中只读提取尾部视频到 app cache，返回缓存 MP4 路径。
  Future<String> getMotionVideo({
    required int imageId,
    required String imageUri,
    required int totalSize,
    required int videoSize,
  }) async {
    final path = await _channel.invokeMethod<String>('getMotionVideo', {
      'imageId': imageId,
      'imageUri': imageUri,
      'totalSize': totalSize,
      'videoSize': videoSize,
    });
    return path ?? '';
  }

  /// 读取 JPG 的 EXIF 信息（只读）。
  Future<Map<String, dynamic>> getExif(String imageUri) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getExif', {
      'imageUri': imageUri,
    });
    return result ?? const {};
  }

  /// 调用系统分享面板分享图片。
  Future<void> shareImage(String imageUri) async {
    await _channel.invokeMethod<void>('shareImage', {'imageUri': imageUri});
  }

  /// 调用系统分享面板分享多张图片。
  Future<void> shareImages(List<String> imageUris) async {
    await _channel.invokeMethod<void>('shareImages', {'imageUris': imageUris});
  }

  /// 更新 EXIF 字段。传空字符串会清空对应字段。
  Future<bool> updateExif(String imageUri, Map<String, String> values) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'updateExif',
      {'imageUri': imageUri, 'values': values},
    );
    return result?['ok'] == true;
  }

  /// 清除 GPS、设备、软件、拍摄时间等敏感 EXIF。
  Future<bool> clearSensitiveExif(String imageUri, List<String> groups) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'clearSensitiveExif',
      {'imageUri': imageUri, 'groups': groups},
    );
    return result?['ok'] == true;
  }

  /// 把文件移入应用回收站。返回 {entry, needsConsent}。
  Future<Map<String, dynamic>> moveToTrash({
    required String uri,
    required String fileName,
    required String relativePath,
    required String mediaType,
    required int dateTaken,
    int? imageId,
    int? videoId,
  }) async {
    final result = await _channel
        .invokeMapMethod<String, dynamic>('moveToTrash', {
          'uri': uri,
          'fileName': fileName,
          'relativePath': relativePath,
          'mediaType': mediaType,
          'dateTaken': dateTaken,
          'imageId': imageId,
          'videoId': videoId,
        });
    return result ?? const {};
  }

  /// 是否已授予“所有文件访问”权限。
  Future<bool> hasAllFilesAccess() async {
    return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
  }

  /// 打开“所有文件访问”设置页。
  Future<void> openAllFilesAccessSettings() async {
    await _channel.invokeMethod<void>('openAllFilesAccessSettings');
  }

  /// 尝试用系统文件管理器打开相对目录。
  Future<String> openFolder(String relativePath) async {
    final result = await _channel.invokeMethod<String>('openFolder', {
      'relativePath': relativePath,
    });
    return result ?? 'failed';
  }

  /// 回收站条目列表。
  Future<List<Map<String, dynamic>>> listTrash() async {
    final result = await _channel.invokeListMethod<dynamic>('listTrash');
    return (result ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  /// 回收站条目的预览图（图片解码/视频取帧），返回本地缓存路径。
  Future<String> getTrashPreview({required String id, int size = 512}) async {
    final path = await _channel.invokeMethod<String>('getTrashPreview', {
      'id': id,
      'size': size,
    });
    return path ?? '';
  }

  /// 从回收站恢复，返回新文件信息（供首页原地更新）。
  Future<Map<String, dynamic>?> restoreTrash(String id) async {
    return await _channel.invokeMapMethod<String, dynamic>('restoreTrash', {
      'id': id,
    });
  }

  /// 彻底删除回收站条目。
  Future<bool> permanentDeleteTrash(String id) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'permanentDeleteTrash',
      {'id': id},
    );
    return result?['ok'] == true;
  }

  /// 原生事件流（权限变化、删除结果等）。
  Stream<Map<String, dynamic>> events() {
    return _events.receiveBroadcastStream().map(
      (e) => Map<String, dynamic>.from(e as Map),
    );
  }
}
