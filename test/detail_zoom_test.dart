import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_manager/data/repositories/live_photo_repository.dart';
import 'package:live_manager/domain/models/photo_item.dart';
import 'package:live_manager/domain/models/trash_entry.dart';
import 'package:live_manager/ui/features/detail/views/detail_screen.dart';
import 'package:photo_view/photo_view.dart';

class _FakeRepository implements LivePhotoRepository {
  _FakeRepository(this.imagePath);
  final String imagePath;

  @override
  Future<List<PhotoItem>> scan() async => const [];
  @override
  Future<String> thumbnailPathFor(PhotoItem item) async => imagePath;
  @override
  Future<String> fullImagePathFor(PhotoItem item) async => imagePath;
  @override
  Future<String> videoFilePathFor(PhotoItem item) async => '/fake/${item.videoId}.mp4';
  @override
  Future<Map<String, dynamic>> exifFor(PhotoItem item) async => const {};
  @override
  Future<void> share(PhotoItem item) async {}
  @override
  Future<void> shareAll(List<PhotoItem> items) async {}
  @override
  Future<bool> updateExif(PhotoItem item, Map<String, String> values) async => true;
  @override
  Future<bool> clearSensitiveExif(PhotoItem item, List<String> groups) async => true;
  @override
  Future<Map<String, dynamic>> moveToTrash(PhotoItem item, {required bool deleteVideo}) async => const {'status': 'ok'};
  @override
  Future<bool> hasAllFilesAccess() async => true;
  @override
  Future<void> openAllFilesAccessSettings() async {}
  @override
  Future<String> openFolder(PhotoItem item) async => 'folder';
  @override
  Future<List<TrashEntry>> trashEntries() async => const [];
  @override
  Future<String> trashPreviewPath(TrashEntry entry, {int size = 512}) async => '/fake/trash.jpg';
  @override
  Future<Map<String, dynamic>?> restoreTrash(String id) async => null;
  @override
  Future<bool> permanentDeleteTrash(String id) async => true;
  @override
  Stream<Map<String, dynamic>> events() => const Stream.empty();
}

void main() {
  late String testImage;

  setUpAll(() async {
    // photo_view 需要真实图片才能加载出手势层；先生成一张 800x300 的 PNG。
    final dir = await Directory.systemTemp.createTemp('livephoto_test_');
    testImage = '${dir.path}${Platform.pathSeparator}test.png';
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 800, 300),
      Paint()..color = const Color(0xFF4488FF),
    );
    final image = await recorder.endRecording().toImage(800, 300);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(testImage).writeAsBytes(bytes!.buffer.asUint8List());
  });

  PhotoItem item(int id, {bool live = false}) => PhotoItem(
        imageId: id,
        imageUri: 'content://media/external/images/media/$id',
        displayName: 'IMG_$id.jpg',
        createTime: DateTime(2026, 8, 1),
        imageSize: 1000,
        relativePath: 'DCIM/Camera/',
        videoId: live ? id + 100 : null,
        videoUri: live ? 'content://media/external/video/media/${id + 100}' : null,
        videoSize: live ? 2000 : null,
        videoDurationMs: live ? 1500 : null,
        isLive: live,
      );

  /// 把图片解码进全局缓存，保证 pumpWidget 后 PhotoView 同步拿到图。
  Future<void> warmCache(String path) async {
    final provider = FileImage(File(path));
    final stream = provider.resolve(ImageConfiguration.empty);
    final completer = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete(info);
      },
      onError: (e, _) {
        stream.removeListener(listener);
        completer.completeError(e);
      },
    );
    stream.addListener(listener);
    await completer.future.timeout(const Duration(seconds: 5));
  }

  Future<void> pumpDetail(WidgetTester tester,
      {int initialIndex = 0, Size size = const Size(1600, 1200)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => warmCache(testImage));
    await tester.pumpWidget(
      MaterialApp(
        home: DetailScreen(
          items: [item(1), item(2), item(3)],
          initialIndex: initialIndex,
          repository: _FakeRepository(testImage),
          thumbnailLoader: (i) async => testImage,
          onDelete: (_, _) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  /// 当前可见页的 PhotoView（切页后旧页可能仍在树中，需按位置筛选）。
  PhotoView visiblePhotoView(WidgetTester tester) {
    final rect = tester.getRect(find.byType(PageView));
    for (final e in find.byType(PhotoView).evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      if (r.center.dx >= rect.left && r.center.dx <= rect.right) {
        return e.widget as PhotoView;
      }
    }
    return tester.widget<PhotoView>(find.byType(PhotoView).first);
  }

  double scaleOf(WidgetTester tester) =>
      visiblePhotoView(tester).controller!.value.scale!;

  String pos(WidgetTester tester) =>
      tester.widget<Text>(find.textContaining('/ 3').first).data!;

  Future<void> doubleTap(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(PhotoView).first);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
  }

  /// 慢速拖动：结束时停顿 400ms 再松手，保证松手速度≈0，
  /// 停靠完全由“滑过一半”判定，测试可预测。
  Future<void> slowDrag(WidgetTester tester, Offset start, Offset total) async {
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 16));
    const step = 10.0;
    final steps = (total.dx.abs() / step).ceil();
    for (var i = 0; i < steps; i++) {
      final dx = total.dx / steps;
      final dy = total.dy / steps;
      await g.moveBy(Offset(dx, dy));
      await tester.pump(const Duration(milliseconds: 12));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('double-tap zooms to covering and back to fit', (tester) async {
    await pumpDetail(tester);
    // 800x300 contained 在 1600x1200 中：贴合比例 = 2.0，covering = 4.0
    expect(scaleOf(tester), closeTo(2.0, 0.01));

    await doubleTap(tester);
    expect(scaleOf(tester), greaterThan(1.5));

    await doubleTap(tester);
    expect(scaleOf(tester), closeTo(2.0, 0.01));
  });

  testWidgets('zoomed single-finger pan within bounds does not page',
      (tester) async {
    await pumpDetail(tester);
    final center = tester.getCenter(find.byType(PhotoView).first);
    await doubleTap(tester);
    expect(scaleOf(tester), greaterThan(1.5));

    // 4x 下平移范围 = (800*4-1600)/2 = 800px；-300px 仍在图片内。
    await slowDrag(tester, center, const Offset(-300, 0));
    expect(pos(tester), '1 / 3', reason: 'panning must not switch page');
    expect(scaleOf(tester), greaterThan(1.5), reason: 'zoom must be kept');
  });

  testWidgets('zoomed edge drag left switches to NEXT page at fit',
      (tester) async {
    await pumpDetail(tester);
    final center = tester.getCenter(find.byType(PhotoView).first);
    await doubleTap(tester);

    // 先平移 800px 到图片右边界，再向左外推 900px（过半）→ 停靠到下一张。
    await slowDrag(tester, center, const Offset(-1700, 0));
    expect(pos(tester), '2 / 3', reason: 'left edge push should go to next page');
    expect(scaleOf(tester), closeTo(2.0, 0.05), reason: 'new page at fit');
  });

  testWidgets('zoomed edge drag right switches to PREVIOUS page at fit',
      (tester) async {
    await pumpDetail(tester, initialIndex: 1);
    final center = tester.getCenter(find.byType(PhotoView).first);
    await doubleTap(tester);

    // 先平移 800px 到图片左边界，再向右外推 900px → 停靠到上一张。
    await slowDrag(tester, center, const Offset(1700, 0));
    expect(pos(tester), '1 / 3', reason: 'right edge push should go to previous page');
    expect(scaleOf(tester), closeTo(2.0, 0.05), reason: 'new page at fit');
  });

  testWidgets('zoomed small edge drag snaps back and keeps zoom',
      (tester) async {
    await pumpDetail(tester);
    final center = tester.getCenter(find.byType(PhotoView).first);
    await doubleTap(tester);

    // 平移 800px 到边界后只外推 50px（未过半）→ 弹回当前页并保持放大。
    await slowDrag(tester, center, const Offset(-850, 0));
    expect(pos(tester), '1 / 3', reason: 'small edge drag should snap back');
    expect(scaleOf(tester), greaterThan(1.5), reason: 'snap back keeps zoom');
  });

  testWidgets('pinch zooms and must not page even with horizontal drift',
      (tester) async {
    await pumpDetail(tester);
    final center = tester.getCenter(find.byType(PhotoView).first);
    final g1 = await tester.startGesture(center - const Offset(80, 0));
    final g2 = await tester.startGesture(center + const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 12; i++) {
      await g1.moveBy(const Offset(-45, 0));
      await g2.moveBy(const Offset(45, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 双指保持捏合并一起向左漂移——绝不能变成翻页。
    for (var i = 0; i < 8; i++) {
      await g1.moveBy(const Offset(-60, 0));
      await g2.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    expect(pos(tester), '1 / 3', reason: 'pinch drift must not switch page');
    expect(scaleOf(tester), greaterThan(1.5), reason: 'pinch should zoom');
  });

  testWidgets('pinch after a one-finger pre-move must cancel page drag',
      (tester) async {
    await pumpDetail(tester);
    final center = tester.getCenter(find.byType(PhotoView).first);

    // 第一根手指先左移越过阈值（触发翻页跟手），第二根手指再落下张开。
    final g1 = await tester.startGesture(center);
    await g1.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    final g2 = await tester.startGesture(center + const Offset(100, 0));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 10; i++) {
      await g1.moveBy(const Offset(-45, 0));
      await g2.moveBy(const Offset(45, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();

    expect(pos(tester), '1 / 3', reason: 'second finger must cancel page drag');
    expect(scaleOf(tester), greaterThan(1.5), reason: 'pinch should zoom');
  });

  testWidgets('after two-finger pinch, remaining single finger never pages',
      (tester) async {
    await pumpDetail(tester);
    final center = tester.getCenter(find.byType(PhotoView).first);

    // 双指一起向左平移（捏合会话），随后抬起一根，剩下的一根继续左滑。
    final g1 = await tester.startGesture(center - const Offset(80, 0));
    final g2 = await tester.startGesture(center + const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 6; i++) {
      await g1.moveBy(const Offset(-40, 0));
      await g2.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 6; i++) {
      await g2.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g2.up();
    await tester.pumpAndSettle();

    expect(pos(tester), '1 / 3',
        reason: 'single finger left from a pinch session must not page');
  });

  testWidgets('1x horizontal drag past half switches page', (tester) async {
    await pumpDetail(tester);
    final center = tester.getCenter(find.byType(PhotoView).first);
    await slowDrag(tester, center, const Offset(-900, 0));
    expect(pos(tester), '2 / 3', reason: 'drag past half should settle on next page');
    expect(scaleOf(tester), closeTo(2.0, 0.05));
  });

  testWidgets('1x small horizontal drag snaps back', (tester) async {
    await pumpDetail(tester);
    final center = tester.getCenter(find.byType(PhotoView).first);
    await slowDrag(tester, center, const Offset(-300, 0));
    expect(pos(tester), '1 / 3', reason: 'small drag should snap back');
  });

  testWidgets('1x vertical drag does not page', (tester) async {
    await pumpDetail(tester);
    final center = tester.getCenter(find.byType(PhotoView).first);
    await slowDrag(tester, center, const Offset(0, 300));
    expect(pos(tester), '1 / 3', reason: 'vertical drag must not switch page');
  });

  /// 单指连续手势：不抬手，按段依次移动（覆盖“中途反向”场景）。
  Future<void> gesturePath(WidgetTester tester, List<Offset> segments) async {
    final g = await tester
        .startGesture(tester.getCenter(find.byType(PhotoView).first));
    await tester.pump(const Duration(milliseconds: 16));
    const step = 10.0;
    for (final seg in segments) {
      final steps = (seg.dx.abs() / step).ceil();
      for (var i = 0; i < steps; i++) {
        await g.moveBy(Offset(seg.dx / steps, seg.dy / steps));
        await tester.pump(const Duration(milliseconds: 12));
      }
    }
    await tester.pump(const Duration(milliseconds: 400));
    await g.up();
    await tester.pumpAndSettle();
  }

  testWidgets('zoomed mid-gesture reversal must not switch page',
      (tester) async {
    await pumpDetail(tester);
    await doubleTap(tester);
    expect(scaleOf(tester), greaterThan(1.5));

    // 不抬手：左移 500 → 反向 700（仍在图内）。反向瞬间不能触发边界外推。
    await gesturePath(tester, [const Offset(-500, 0), const Offset(700, 0)]);
    expect(pos(tester), '1 / 3',
        reason: 'reversal at mid-pan must not switch page');
    expect(scaleOf(tester), greaterThan(1.5),
        reason: 'zoom must be kept after reversal');
  });

  testWidgets('zoomed reversal then edge push keeps finger direction',
      (tester) async {
    await pumpDetail(tester);
    await doubleTap(tester);

    // 左移 500 → 反向 300 → 再大幅左移越过边界：只能切到下一张，绝不能反向切上一张。
    await gesturePath(tester, [
      const Offset(-500, 0),
      const Offset(300, 0),
      const Offset(-1800, 0),
    ]);
    expect(pos(tester), '2 / 3',
        reason: 'edge push direction must follow finger, never reverse');
    expect(scaleOf(tester), closeTo(2.0, 0.05));
  });

  /// 快速甩动：用带真实时间戳的事件模拟高速滑动（远高于慢速拖动阈值）。
  Future<void> fastFling(WidgetTester tester, Offset total) async {
    await tester.flingFrom(
      tester.getCenter(find.byType(PhotoView).first),
      total,
      2000, // px/s
    );
    await tester.pumpAndSettle();
  }

  testWidgets('zoomed fast fling from mid-image glides to edge, no page switch',
      (tester) async {
    await pumpDetail(tester);
    await doubleTap(tester);
    expect(scaleOf(tester), greaterThan(1.5));

    // 不在边缘快速左甩：绝不切页；松手后图片应惯性滑到左边缘停住。
    await fastFling(tester, const Offset(-400, 0));
    expect(pos(tester), '1 / 3',
        reason: 'fling from mid-image must not switch page');
    expect(scaleOf(tester), greaterThan(1.5),
        reason: 'zoom must be kept after inertia');
    final controller = visiblePhotoView(tester).controller!;
    expect(controller.position.dx, lessThanOrEqualTo(-700),
        reason: 'image should glide toward left edge by inertia');
  });

  testWidgets('zoomed fast fling from edge switches to next page',
      (tester) async {
    await pumpDetail(tester);
    await doubleTap(tester);
    // 把图片直接放到左边缘（4x 时平移范围 800px）。
    final controller = visiblePhotoView(tester).controller!;
    controller.position = const Offset(-800, 0);
    await tester.pump();

    await fastFling(tester, const Offset(-300, 0));
    expect(pos(tester), '2 / 3',
        reason: 'fling at left edge should switch to next page');
    expect(scaleOf(tester), closeTo(2.0, 0.05),
        reason: 'new page settles at fit');
  });
}
