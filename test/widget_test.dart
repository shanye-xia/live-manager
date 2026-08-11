import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  Future<void> share(PhotoItem item) async {}

  @override
  Future<void> shareAll(List<PhotoItem> items) async {}

  @override
  Future<bool> updateExif(PhotoItem item, Map<String, String> values) async =>
      true;

  @override
  Future<bool> clearSensitiveExif(PhotoItem item, List<String> groups) async =>
      true;

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
  Future<String> openFolder(PhotoItem item) async => 'folder';

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

class _FakeTrashRepository extends _FakeRepository {
  final List<TrashEntry> items = [
    TrashEntry(
      id: 't1',
      originalFileName: 'IMG_DEL_1.jpg',
      originalRelativePath: 'DCIM/Camera/',
      mediaType: 'image',
      size: 1000,
      dateTaken: DateTime(2026, 8, 3, 12),
      trashedAt: DateTime(2026, 8, 3, 12, 30),
    ),
    TrashEntry(
      id: 't2',
      originalFileName: 'IMG_DEL_2.jpg',
      originalRelativePath: 'DCIM/Camera/',
      mediaType: 'image',
      size: 2000,
      dateTaken: DateTime(2026, 8, 4, 12),
      trashedAt: DateTime(2026, 8, 4, 12, 30),
    ),
  ];

  @override
  Future<List<TrashEntry>> trashEntries() async => List.of(items);

  @override
  Future<String> trashPreviewPath(TrashEntry entry, {int size = 512}) async {
    return '/nonexistent/trash_${entry.id}.jpg';
  }

  @override
  Future<Map<String, dynamic>?> restoreTrash(String id) async {
    final i = items.indexWhere((e) => e.id == id);
    if (i < 0) return null;
    final e = items.removeAt(i);
    return {
      'mediaType': 'image',
      'displayName': e.originalFileName,
      'relativePath': e.originalRelativePath,
      'size': e.size,
      'dateTaken': e.trashedAt.millisecondsSinceEpoch,
      'uri': 'content://media/external/images/media/999',
      'id': 999,
      'durationMs': null,
    };
  }

  @override
  Future<bool> permanentDeleteTrash(String id) async {
    final before = items.length;
    items.removeWhere((e) => e.id == id);
    return items.length < before;
  }
}

class _FakeGridRepository extends _FakeRepository {
  @override
  Future<List<PhotoItem>> scan() async {
    return [
      for (var i = 0; i < 12; i++)
        PhotoItem(
          imageId: i + 1,
          imageUri: 'content://media/external/images/media/${i + 1}',
          displayName: 'IMG_${i + 1}.jpg',
          createTime: DateTime(2026, 8, 1).add(Duration(minutes: i)),
          imageSize: 1000 + i,
          relativePath: 'DCIM/Camera/',
          videoId: i == 0 ? 1000 : null,
          videoUri: i == 0
              ? 'content://media/external/video/media/1000'
              : null,
          videoSize: i == 0 ? 2000 : null,
          videoDurationMs: i == 0 ? 1500 : null,
          isLive: i == 0,
        ),
    ];
  }
}

void main() {
  testWidgets('首页展示全部照片与 LIVE 角标', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Live Manager'), findsOneWidget);
    expect(find.text('全部照片'), findsOneWidget);
    expect(find.text('Live'), findsNWidgets(2));
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

    expect(find.text('取消'), findsOneWidget);

    // simulate system back button
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // still on home screen, selection mode exited
    expect(find.text('Live Manager'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
  });

  testWidgets('long-press and drag over grid selects multiple photos', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeRepository()));
    await tester.pumpAndSettle();

    final start = tester.getCenter(find.text('LIVE'));
    final gesture = await tester.startGesture(start);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(start + const Offset(160, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining('已选 2 项'), findsOneWidget);
  });

  testWidgets('selection bar hides delete-live button when no live selected', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeRepository()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('LIVE'));
    await tester.pumpAndSettle();

    expect(find.text('删除Live部分'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // 取消选中 Live 图，只剩普通图未选，隐藏快捷键
    await tester.tap(find.text('LIVE'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('删除Live部分'), findsNothing);
  });

  testWidgets('horizontal swipe in selection mode selects', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeGridRepository()));
    await tester.pumpAndSettle();

    // 长按进入多选
    await tester.longPress(find.text('LIVE'));
    await tester.pumpAndSettle();

    // 松开后，从第二张（未选中）开始横向滑动，划过即选中
    final textTopLeft = tester.getTopLeft(find.text('LIVE'));
    final tile1Center = textTopLeft + const Offset(226.4, 70.8);
    final gesture = await tester.startGesture(tile1Center);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(140, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 起点格(长按) + 第2、3张段选 = 3
    expect(find.textContaining('已选 3 项'), findsOneWidget);
  });

  testWidgets('diagonal sweep selects whole rows crossed', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeGridRepository()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('LIVE'));
    await tester.pumpAndSettle();

    // 从第二张开始横向滑动，再带纵向偏移滑入下一行，下一行整行选中
    final textTopLeft = tester.getTopLeft(find.text('LIVE'));
    final tile1Center = textTopLeft + const Offset(226.4, 70.8);
    final gesture = await tester.startGesture(tile1Center);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(140, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 起点格(长按选中) + 第1行段选 2 张 + 第2行整行 5 张 = 8
    expect(find.textContaining('已选 8 项'), findsOneWidget);
  });

  testWidgets('sweep down then back up deselects crossed rows', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeGridRepository()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('LIVE'));
    await tester.pumpAndSettle();

    final textTopLeft = tester.getTopLeft(find.text('LIVE'));
    final tile1Center = textTopLeft + const Offset(226.4, 70.8);
    final gesture = await tester.startGesture(tile1Center);
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(140, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump();
    expect(find.textContaining('已选 8 项'), findsOneWidget);
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining('已选 3 项'), findsOneWidget);
  });

  testWidgets('vertical swipe pages without selecting', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeGridRepository()));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('LIVE'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 1 项'), findsOneWidget);

    final before = tester.getTopLeft(find.text('LIVE')).dy;
    await tester.drag(find.text('LIVE'), const Offset(0, -300),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.text('LIVE')).dy;

    expect(after, lessThan(before)); // 列表向上翻页
    expect(find.textContaining('已选 1 项'), findsOneWidget); // 纵向滑动不选中
  });
  testWidgets('bottom nav switches to Live-only grid', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeGridRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Live'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Live 动态'), findsOneWidget);
    expect(find.text('全部照片'), findsNothing);
    expect(find.text('12 张'), findsNothing);
    expect(find.text('1 张'), findsOneWidget);
  });

  testWidgets('selection mode hides bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeGridRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.longPress(find.text('LIVE'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.textContaining('已选 1 项'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('recycle bin tab opens', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('回收站'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('回收站为空'), findsOneWidget);
  });

  testWidgets('swipe left/right switches tabs', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeGridRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Live Manager'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Live 动态'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('回收站为空'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text('Live 动态'), findsOneWidget);
  });

  testWidgets('trash selection: long-press, select-all, batch delete', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeTrashRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('回收站'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('IMG_DEL_1.jpg'), findsOneWidget);
    expect(find.text('IMG_DEL_2.jpg'), findsOneWidget);

    // 长按进入多选
    await tester.longPress(find.text('IMG_DEL_1.jpg'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 1 项'), findsOneWidget);

    // 全选后批量彻底删除（带二次确认）
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已选 2 项'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('彻底删除选中项？'), findsOneWidget);
    await tester.tap(find.text('彻底删除').last);
    await tester.pumpAndSettle();

    expect(find.text('回收站为空'), findsOneWidget);
    expect(find.text('IMG_DEL_1.jpg'), findsNothing);
  });

  testWidgets('trash restore-all keeps empty state', (WidgetTester tester) async {
    await tester.pumpWidget(LiveManagerApp(repository: _FakeTrashRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('回收站'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.restore),
    ));
    await tester.pumpAndSettle();
    expect(find.text('全部恢复？'), findsOneWidget);
    await tester.tap(find.text('全部恢复'));
    await tester.pumpAndSettle();

    expect(find.text('回收站为空'), findsOneWidget);
  });
}
