import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
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
    return const {'status': 'ok'};
  }

  @override
  Future<bool> hasAllFilesAccess() async => true;

  @override
  Future<void> openAllFilesAccessSettings() async {}

  @override
  Future<List<TrashEntry>> trashEntries() async => const [];

  @override
  Future<String> trashPreviewPath(TrashEntry entry, {int size = 512}) async {
    return '/nonexistent/trash_${entry.id}.jpg';
  }

  @override
  Future<Map<String, dynamic>?> restoreTrash(String id) async {
    return {
      'mediaType': 'image',
      'displayName': 'IMG_RESTORED.jpg',
      'relativePath': 'DCIM/Camera/',
      'size': 1000,
      'dateTaken': 1780000000000,
      'uri': 'content://media/external/images/media/999',
      'id': 999,
      'durationMs': null,
    };
  }

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
    expect(find.text('全部照片'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(find.text('2 张'), findsOneWidget);
    expect(find.text('1 张'), findsOneWidget);

    await tester.tap(find.text('全部照片'));
    await tester.pumpAndSettle();

    expect(find.textContaining('图片'), findsOneWidget);
    expect(find.textContaining('视频'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('selection mode back exits selection mode instead of app', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeRepository()));
    await tester.pumpAndSettle();

    // long-press first LIVE photo to enter selection mode
    await tester.longPress(find.text('LIVE'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget);

    // simulate system back button
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // still on home screen, selection mode exited
    expect(find.text('Live Manager'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
  });
}
