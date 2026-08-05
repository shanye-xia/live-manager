import 'package:flutter_test/flutter_test.dart';
import 'package:live_manager/domain/models/live_photo.dart';

void main() {
  group('LivePhoto 序列化', () {
    final json = <String, dynamic>{
      'imageId': 1001,
      'videoId': 2001,
      'imageUri': 'content://media/external/images/media/1001',
      'videoUri': 'content://media/external/video/media/2001',
      'displayName': 'IMG_20260803_224902',
      'createTime': 1780000000000,
      'imageSize': 2200000,
      'videoSize': 3800000,
      'videoDurationMs': 2400,
    };

    test('fromJson 正确解析全部字段', () {
      final item = LivePhoto.fromJson(json);

      expect(item.imageId, 1001);
      expect(item.videoId, 2001);
      expect(item.imageUri, 'content://media/external/images/media/1001');
      expect(item.videoUri, 'content://media/external/video/media/2001');
      expect(item.displayName, 'IMG_20260803_224902');
      expect(item.createTime,
          DateTime.fromMillisecondsSinceEpoch(1780000000000));
      expect(item.imageSize, 2200000);
      expect(item.videoSize, 3800000);
      expect(item.videoDurationMs, 2400);
      expect(item.totalSize, 6000000);
    });

    test('toJson 与 fromJson 可往返', () {
      final item = LivePhoto.fromJson(json);
      final roundTrip = LivePhoto.fromJson(item.toJson());

      expect(roundTrip.imageId, item.imageId);
      expect(roundTrip.displayName, item.displayName);
      expect(roundTrip.createTime, item.createTime);
      expect(roundTrip.totalSize, item.totalSize);
    });

    test('字段缺失时抛出 FormatException', () {
      expect(
        () => LivePhoto.fromJson(const {'imageId': 1}),
        throwsFormatException,
      );
    });
  });
}
