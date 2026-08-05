import 'package:flutter/services.dart';

/// 原生桥接客户端（MethodChannel + EventChannel 封装）。
class LivePhotoPlatformService {
  const LivePhotoPlatformService();

  static const MethodChannel _channel =
      MethodChannel('com.livemanager/live_photo');
  static const EventChannel _events =
      EventChannel('com.livemanager/live_photo_events');

  /// 冒烟测试：与原生层完成一次通信，返回设备信息。
  Future<Map<String, dynamic>> ping() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('ping');
    return result ?? const {};
  }

  /// 请求媒体读取权限。返回 granted（是否已授权）与 pending（是否弹窗等待）。
  Future<Map<String, dynamic>> requestPermissions() async {
    final result = await _channel
        .invokeMapMethod<String, dynamic>('requestPermissions');
    return result ?? const {};
  }

  /// 查询当前权限状态。
  Future<Map<String, dynamic>> permissionStatus() async {
    final result =
        await _channel.invokeMapMethod<String, dynamic>('permissionStatus');
    return result ?? const {};
  }

  /// 扫描并返回所有配对的 Live Photo（只读）。
  Future<List<Map<String, dynamic>>> scanLivePhotos() async {
    final result = await _channel.invokeListMethod<dynamic>('scanLivePhotos');
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

  /// 读取 JPG 的 EXIF 信息（只读）。
  Future<Map<String, dynamic>> getExif(String imageUri) async {
    final result =
        await _channel.invokeMapMethod<String, dynamic>('getExif', {
      'imageUri': imageUri,
    });
    return result ?? const {};
  }

  /// 删除动态视频（进入系统回收站，需用户在系统弹窗确认）。
  /// 安全约束：仅在用户明确要求时调用。
  Future<Map<String, dynamic>> deleteVideo(String videoUri) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'deleteVideo',
      {'videoUri': videoUri},
    );
    return result ?? const {};
  }

  /// 原生事件流（权限变化、删除结果等）。
  Stream<Map<String, dynamic>> events() {
    return _events
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map));
  }
}
