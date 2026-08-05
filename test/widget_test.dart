import 'package:flutter_test/flutter_test.dart';
import 'package:live_manager/data/repositories/live_photo_repository.dart';
import 'package:live_manager/domain/models/photo_item.dart';
import 'package:live_manager/domain/models/trash_entry.dart';
import 'package:live_manager/main.dart';

class _FakeRepository implements LivePhotoRepository {
  @override
  Future<List<PhotoItem>> scan() async {
    return [
      PhotoItem(
        imageId: 1,
        imageUri: 'content://media/external/images/media/1',
        displayName: 'IMG_TEST_0001.jpg',
        createTime: DateTime(2026, 8, 1),
        imageSize: 1000,
        relativePath: 'DCIM/Camera/',
        videoId: 2,
        videoUri: 'content://media/external/video/media/2',
        videoSize: 2000,
        videoDurationMs: 1500,
        isLive: true,
      ),
      PhotoItem(
        imageId: 3,
        imageUri: 'content://media/external/images/media/3',
        displayName: 'IMG_TEST_0002.jpg',
        createTime: DateTime(2026, 8, 2),
        imageSize: 2000,
        relativePath: 'DCIM/Camera/',
        isLive: false,
      ),
    ];
  }

  @override
  Future<String> thumbnailPathFor(PhotoItem item) async {
    return '/nonexistent/${item.imageId}.jpg';
  }

  @override
  Future<String> fullImagePathFor(PhotoItem item) async {
    return '/nonexistent/${item.imageId}_full.jpg';
  }

  @override
  Future<String> videoFilePathFor(PhotoItem item) async {
    return '/nonexistent/${item.videoId}.mp4';
  }

  @override
  Future<Map<String, dynamic>> exifFor(PhotoItem item) async {
    return const {'model': 'vivo X200 Pro mini', 'iso': '1741'};
  }

  @override
  Future<Map<String, dynamic>> moveToTrash(
    PhotoItem item, {
    required bool deleteVideo,
  }) async {
    return const {'needsConsent': false};
  }

  @override
  Future<List<TrashEntry>> trashEntries() async => const [];

  @override
  Future<bool> restoreTrash(String id) async => true;

  @override
  Future<bool> permanentDeleteTrash(String id) async => true;

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

void main() {
  testWidgets('首页展示全部照片与 LIVE 角标', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Live Manager'), findsOneWidget);
    expect(find.text('共 2 张照片 · 1 张 Live'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
  });
}
