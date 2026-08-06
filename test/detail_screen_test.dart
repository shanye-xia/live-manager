import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_manager/data/repositories/live_photo_repository.dart';
import 'package:live_manager/domain/models/photo_item.dart';
import 'package:live_manager/domain/models/trash_entry.dart';
import 'package:live_manager/ui/features/detail/views/detail_screen.dart';

class _FakeRepository implements LivePhotoRepository {
  _FakeRepository();

  final List<bool> deleteVideoCalls = [];

  @override
  Future<List<PhotoItem>> scan() async => const [];

  @override
  Future<String> thumbnailPathFor(PhotoItem item) async =>
      '/fake/${item.imageId}.jpg';

  @override
  Future<String> fullImagePathFor(PhotoItem item) async =>
      '/fake/${item.imageId}_full.jpg';

  @override
  Future<String> videoFilePathFor(PhotoItem item) async =>
      '/fake/${item.videoId}.mp4';

  @override
  Future<Map<String, dynamic>> exifFor(PhotoItem item) async => const {};

  @override
  Future<Map<String, dynamic>> moveToTrash(
    PhotoItem item, {
    required bool deleteVideo,
  }) async {
    deleteVideoCalls.add(deleteVideo);
    return const {'status': 'ok'};
  }

  @override
  Future<bool> hasAllFilesAccess() async => true;

  @override
  Future<void> openAllFilesAccessSettings() async {}

  @override
  Future<List<TrashEntry>> trashEntries() async => const [];

  @override
  Future<String> trashPreviewPath(TrashEntry entry, {int size = 512}) async =>
      '/fake/trash.jpg';

  @override
  Future<Map<String, dynamic>?> restoreTrash(String id) async => null;

  @override
  Future<bool> permanentDeleteTrash(String id) async => true;

  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

void main() {
  final liveItem = PhotoItem(
    imageId: 1,
    imageUri: 'content://media/external/images/media/1',
    displayName: 'IMG_LIVE.jpg',
    createTime: DateTime(2026, 8, 1),
    imageSize: 1000,
    relativePath: 'DCIM/Camera/',
    videoId: 2,
    videoUri: 'content://media/external/video/media/2',
    videoSize: 2000,
    videoDurationMs: 1500,
    isLive: true,
  );
  final normalItem = PhotoItem(
    imageId: 3,
    imageUri: 'content://media/external/images/media/3',
    displayName: 'IMG_NORMAL.jpg',
    createTime: DateTime(2026, 8, 2),
    imageSize: 2000,
    relativePath: 'DCIM/Camera/',
    isLive: false,
  );

  Future<_FakeRepository> pumpDetail(
    WidgetTester tester, {
    required List<PhotoItem> items,
    required void Function(int imageId, bool videoOnly) onDelete,
  }) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          items: items,
          initialIndex: 0,
          repository: repository,
          thumbnailLoader: (item) async => '/fake/${item.imageId}.jpg',
          onDelete: onDelete,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets(
    'live detail delete shows two options',
    (WidgetTester tester) async {
      await pumpDetail(
        tester,
        items: [liveItem, normalItem],
        onDelete: (_, _) {},
      );

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('仅删除Live动态'), findsOneWidget);
      expect(find.text('全部删除'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    },
  );

  testWidgets(
    'live video-only delete keeps photo',
    (WidgetTester tester) async {
      final calls = <(int, bool)>[];
      final repository = await pumpDetail(
        tester,
        items: [liveItem, normalItem],
        onDelete: (imageId, videoOnly) => calls.add((imageId, videoOnly)),
      );

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅删除Live动态'));
      await tester.pumpAndSettle();

      expect(calls, [(1, true)]);
      expect(repository.deleteVideoCalls, [true]);
      expect(find.text('已删除'), findsOneWidget);
    },
  );

  testWidgets(
    'live full delete removes photo and video',
    (WidgetTester tester) async {
      final calls = <(int, bool)>[];
      final repository = await pumpDetail(
        tester,
        items: [liveItem, normalItem],
        onDelete: (imageId, videoOnly) => calls.add((imageId, videoOnly)),
      );

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部删除'));
      await tester.pumpAndSettle();

      expect(calls, [(1, false)]);
      expect(repository.deleteVideoCalls, [true, false]);
      expect(find.text('已删除'), findsOneWidget);
    },
  );
}
