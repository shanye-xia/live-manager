import 'package:flutter_test/flutter_test.dart';
import 'package:live_manager/domain/models/photo_item.dart';

void main() {
  group('PhotoItem 序列化', () {
    final liveJson = <String, dynamic>{
      'imageId': 1001,
      'imageUri': 'content://media/external/images/media/1001',
      'displayName': 'IMG_20260803_224902.jpg',
      'createTime': 1780000000000,
      'imageSize': 2200000,
      'relativePath': 'DCIM/Camera/',
      'videoId': 2001,
      'videoUri': 'content://media/external/video/media/2001',
      'videoSize': 3800000,
      'videoDurationMs': 2400,
      'isLive': true,
    };

    test('fromJson 正确解析 Live 照片', () {
      final item = PhotoItem.fromJson(liveJson);

      expect(item.imageId, 1001);
      expect(item.imageUri, 'content://media/external/images/media/1001');
      expect(item.displayName, 'IMG_20260803_224902.jpg');
      expect(item.createTime,
          DateTime.fromMillisecondsSinceEpoch(1780000000000));
      expect(item.imageSize, 2200000);
      expect(item.relativePath, 'DCIM/Camera/');
      expect(item.videoId, 2001);
      expect(item.videoUri, 'content://media/external/video/media/2001');
      expect(item.videoSize, 3800000);
      expect(item.videoDurationMs, 2400);
      expect(item.isLive, isTrue);
      expect(item.totalSize, 6000000);
    });

    test('非 Live 照片视频字段为 null', () {
      final item = PhotoItem.fromJson({
        'imageId': 1002,
        'imageUri': 'content://media/external/images/media/1002',
        'displayName': 'IMG_0001.jpg',
        'createTime': 1780000000000,
        'imageSize': 1000,
        'relativePath': 'DCIM/Camera/',
        'isLive': false,
      });

      expect(item.isLive, isFalse);
      expect(item.videoUri, isNull);
      expect(item.totalSize, 1000);
    });

    test('toJson 与 fromJson 可往返', () {
      final item = PhotoItem.fromJson(liveJson);
      final roundTrip = PhotoItem.fromJson(item.toJson());

      expect(roundTrip.imageId, item.imageId);
      expect(roundTrip.displayName, item.displayName);
      expect(roundTrip.isLive, item.isLive);
      expect(roundTrip.totalSize, item.totalSize);
    });
  });
}
